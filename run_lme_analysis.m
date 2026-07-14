%% =========================================================================
%  run_lme_analysis
%  Linear mixed-effects models of burst rate, duration, and amplitude
%  across Stimulation Type x Time, Subject as a random intercept -- same
%  model structure as the original tACS analysis, run here on this
%  project's own corrected pipeline output (straight-line aperiodic
%  removal, flexible intervals, C3 only).
%
%  REQUIRES: Statistics and Machine Learning Toolbox (fitlme, anova).
%
%  INPUT
%    T - the table from summarize_batch_results (StimType, Timepoint,
%        SubjectID, rate_per_sec, mean_duration_ms, mean_amplitude_scaled
%        columns required)
%
%  OUTPUT
%    lme_results - struct with one field per feature ('rate_per_sec',
%      'mean_duration_ms', 'mean_amplitude_scaled'), each containing:
%        .model - the fitted LinearMixedModel object
%        .anova - the fixed-effects ANOVA table (F, df, p-value per term)
%
%  NOTE ON SAMPLE SIZE: rate is defined even for sessions with zero
%  detected bursts (rate = 0), but duration/amplitude/bandwidth are only
%  defined when at least one burst was detected -- so the duration and
%  amplitude models will have a slightly smaller N than the rate model.
%  fitlme drops those rows automatically (listwise deletion on NaN); this
%  is expected, not a bug, and is worth mentioning if reporting N per model.
% =========================================================================
function lme_results = run_lme_analysis(T)

    % Keep only successfully-processed sessions
    T = T(strcmp(T.status, 'OK'), :);

    % Categorical predictors, with an explicit (not alphabetical-default)
    % reference level: Sham and Baseline as the natural comparison points.
    T.SubjectID = categorical(T.SubjectID);
    T.StimType  = categorical(T.StimType);
    T.StimType  = reordercats(T.StimType, {'Sham', '20 Hz', '70 Hz'});
    T.Timepoint = categorical(T.Timepoint);
    T.Timepoint = reordercats(T.Timepoint, {'BL', '15min', '45min'});

    features = {'rate_per_sec', 'mean_duration_ms', 'mean_amplitude_scaled'};
    lme_results = struct();

    for i = 1:numel(features)
        feat = features{i};
        formula = sprintf('%s ~ StimType*Timepoint + (1|SubjectID)', feat);

        lme = fitlme(T, formula);
        lme_anova = anova(lme);

        lme_results.(feat).model = lme;
        lme_results.(feat).anova = lme_anova;

        fprintf('\n========== %s (N = %d) ==========\n', feat, lme.NumObservations);
        disp(lme_anova);
    end
end

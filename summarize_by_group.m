%% =========================================================================
%  summarize_by_group
%  Descriptive statistics (mean, std, N) for burst count, rate, duration,
%  and amplitude, grouped by Stimulation Type x Timepoint -- the actual
%  numbers behind the LME models in run_lme_analysis.m.
%
%  INPUT
%    T - the table from summarize_batch_results
%
%  OUTPUT
%    group_summary - a table, one row per StimType x Timepoint combination,
%      with GroupCount (total sessions in that group) plus mean/std for
%      n_bursts, rate_per_sec, mean_duration_ms, mean_amplitude_scaled.
%
%  NOTE: mean/std for mean_duration_ms and mean_amplitude_scaled
%  automatically ignore NaN rows (sessions with zero detected bursts,
%  where duration/amplitude are undefined) -- but GroupCount still
%  reflects the TOTAL sessions in that group, including those zero-burst
%  ones. So GroupCount is not the same as "N used for the duration/
%  amplitude mean" -- worth keeping in mind when reporting.
% =========================================================================
function group_summary = summarize_by_group(T)

    T = T(strcmp(T.status, 'OK'), :);
    T.StimType  = categorical(T.StimType);
    T.StimType  = reordercats(T.StimType, {'Sham', '20 Hz', '70 Hz'});
    T.Timepoint = categorical(T.Timepoint);
    T.Timepoint = reordercats(T.Timepoint, {'BL', '15min', '45min'});

    group_summary = groupsummary(T, {'StimType', 'Timepoint'}, {'mean', 'std'}, ...
        {'n_bursts', 'rate_per_sec', 'mean_duration_ms', 'mean_amplitude_scaled'});
end

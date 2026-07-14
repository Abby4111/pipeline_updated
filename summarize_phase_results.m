%% =========================================================================
%  summarize_phase_results
%  Turns phase_results (from run_batch_phases) into a long-format table:
%  one row per session x phase (43 sessions x 3 phases = up to 129 rows).
%  From this single table, both requested figures can be built:
%    - Figure 11 style: filter to StimType='Sham', Timepoint='BL', group
%      by Phase (pre_movement / movement / post_movement).
%    - Figure 13/14 style: filter to Phase='movement', group by
%      Timepoint, separately for each StimType.
%
%  INPUT
%    phase_results - the struct array returned by run_batch_phases
%
%  OUTPUT
%    phase_table - table with columns: SubjectID, Session, StimType,
%      Timepoint, Phase, n_bursts, rate_per_sec, mean_duration_ms,
%      mean_amplitude_scaled
%    Also writes 'phase_summary_long.csv' in the current folder.
% =========================================================================
function phase_table = summarize_phase_results(phase_results)

    phase_durations = [0.9, 3.0, 3.0];   % pre-movement, movement, post-movement (seconds)

    rows = {};
    for i = 1:numel(phase_results)
        r = phase_results(i);
        if ~strcmp(r.status, 'OK') || isempty(r.results)
            continue;
        end

        phase_names = r.results.phase_names;
        for ph = 1:numel(phase_names)
            bursts = r.results.phase_bursts{1, ph};
            n_b = numel(bursts);
            rate = n_b / phase_durations(ph);

            if n_b > 0
                dur_ms = mean([bursts.duration_ms]);
                amp_scaled = mean([bursts.mean_amplitude]) * 1e12;
            else
                dur_ms = NaN;
                amp_scaled = NaN;
            end

            rows(end+1, :) = {r.SubjectID, r.Session, r.StimType, r.Timepoint, ...
                phase_names{ph}, n_b, rate, dur_ms, amp_scaled}; %#ok<AGROW>
        end
    end

    phase_table = cell2table(rows, 'VariableNames', ...
        {'SubjectID', 'Session', 'StimType', 'Timepoint', 'Phase', ...
         'n_bursts', 'rate_per_sec', 'mean_duration_ms', 'mean_amplitude_scaled'});

    writetable(phase_table, 'phase_summary_long.csv');
    fprintf('Wrote phase_summary_long.csv (%d rows)\n', height(phase_table));
end

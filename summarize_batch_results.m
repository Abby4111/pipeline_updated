%% =========================================================================
%  summarize_batch_results
%  Turns the nested all_results struct array (from run_batch_older_adults)
%  into one flat row per session -- burst count, rate, mean duration,
%  mean amplitude -- ready for grouping/comparison by StimType and
%  Timepoint.
%
%  INPUT
%    all_results - the struct array returned by run_batch_older_adults
%
%  OUTPUT
%    summary_table - a MATLAB table, one row per session, columns:
%      SubjectID, Session, StimType, Timepoint, status,
%      n_bursts, rate_per_sec, mean_duration_ms, mean_amplitude,
%      mean_amplitude_scaled, mean_bandwidth
%    mean_amplitude is in the file's raw physical units (V^2, per
%    Options.PowerUnits = 'physical' in the source timefreq_morlet file)
%    -- NOT the uV^2/Hz scale used in the S99 report's PSD plots, so the
%    two should never be compared directly without converting. 1 V^2 =
%    1e12 uV^2, so mean_amplitude_scaled = mean_amplitude * 1e12 gives an
%    approximate uV^2-scale number for readability alongside the raw value.
%    Sessions that failed (status ~= 'OK') get NaN for the numeric
%    columns, but still appear as a row -- so you can see failure rate
%    alongside real results, not just silently dropped.
% =========================================================================
function summary_table = summarize_batch_results(all_results)

    n = numel(all_results);
    SubjectID = cell(n, 1);
    Session   = cell(n, 1);
    StimType  = cell(n, 1);
    Timepoint = cell(n, 1);
    status    = cell(n, 1);

    n_bursts               = nan(n, 1);
    rate_per_sec           = nan(n, 1);
    mean_duration_ms       = nan(n, 1);
    mean_amplitude         = nan(n, 1);
    mean_amplitude_scaled  = nan(n, 1);
    mean_bandwidth         = nan(n, 1);

    for i = 1:n
        r = all_results(i);
        SubjectID{i} = r.SubjectID;
        Session{i}   = r.Session;
        StimType{i}  = r.StimType;
        Timepoint{i} = r.Timepoint;
        status{i}    = r.status;

        if ~strcmp(r.status, 'OK') || isempty(r.results)
            continue;
        end

        all_bursts = [r.results.ioi_bursts{:}];   % concatenate bursts across all IOIs (single channel: C3)
        n_b = numel(all_bursts);
        n_bursts(i) = n_b;

        epoch_duration_sec = numel(r.results.ioi_starts_time) * 1;   % ioi_len_sec default = 1
        rate_per_sec(i) = n_b / epoch_duration_sec;

        if n_b > 0
            mean_duration_ms(i)      = mean([all_bursts.duration_ms]);
            mean_amplitude(i)        = mean([all_bursts.mean_amplitude]);
            mean_amplitude_scaled(i) = mean_amplitude(i) * 1e12;
            mean_bandwidth(i)        = mean([all_bursts.bandwidth]);
        end
    end

    summary_table = table(SubjectID, Session, StimType, Timepoint, status, ...
        n_bursts, rate_per_sec, mean_duration_ms, mean_amplitude, mean_amplitude_scaled, mean_bandwidth);
end

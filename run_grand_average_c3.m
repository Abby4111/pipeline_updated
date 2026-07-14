%% =========================================================================
%  run_grand_average_c3
%  "Average first, then extract" burst analysis for the older-adult tACS
%  dataset. For each of the 9 Stimulation Type x Timepoint cells:
%    1. Load every included session matching that cell's C3 broadband TF
%    2. Average them together into ONE grand-average trace for that cell
%    3. Fit the aperiodic (straight-line) model on the grand-average
%    4. Threshold and detect bursts on the grand-average -- run TWICE,
%       once with mean+1SD, once with 75th percentile
%    5. Extract burst count and mean power (amplitude) for each
%
%  OUTPUT ORGANIZATION: one dedicated set of figures PER STIMULATION TYPE,
%  each showing that stim type's own 3 timepoints as rows -- e.g. 70Hz
%  gets its own heatmap (3 rows: Baseline/15min/45min), separate from
%  Sham's and 20Hz's own heatmaps. NOT one combined plot mixing groups.
%
%  This is a genuinely different measurement than the per-session
%  pipeline (run_batch_older_adults.m), which detects bursts per session
%  and averages the resulting FEATURES afterward. Here, averaging happens
%  BEFORE burst detection.
%
%  Reuses load_timefreq_morlet, fit_aperiodic_straightline, extract_bursts,
%  extract_bursts_percentile, and extract_bursts_flexible_intervals
%  unchanged.
%
%  INPUT
%    data_root - folder containing per-subject data folders (auto-detected
%                if not given)
%    csv_path  - path to included_sessions.csv (default: same name, current folder)
%
%  OUTPUT
%    grand_results - struct array, one entry per (StimType, Timepoint)
%                     cell (9 total), with fields: StimType, Timepoint,
%                     n_sessions, n_bursts_1sd, mean_power_1sd,
%                     n_bursts_p75, mean_power_p75
%  Also saves, for EACH stim type (Sham, 20Hz, 70Hz):
%    grand_avg_heatmap_<StimType>.png            - 3-row z-scored power heatmap
%    grand_avg_binarized_<StimType>_mean1sd.png  - 3-row binarized bursts, mean+1SD
%    grand_avg_binarized_<StimType>_p75.png      - 3-row binarized bursts, 75th pct
%    grand_average_results.csv                   - the full summary table
% =========================================================================
function grand_results = run_grand_average_c3(data_root, csv_path)

    SCRIPT_VERSION = 'v3 -- crossed StimType x Timepoint, one dedicated figure set per stim type';
    fprintf('=== run_grand_average_c3 %s ===\n', SCRIPT_VERSION);

    if nargin < 2 || isempty(csv_path)
        csv_path = 'included_sessions.csv';
    end
    if nargin < 1 || isempty(data_root)
        fprintf('No data_root given -- searching this computer for timefreq_morlet_*.mat files...\n');
        data_root = find_data_root_auto();
        if isempty(data_root)
            error('Could not automatically find timefreq_morlet_*.mat files. Pass data_root explicitly.');
        end
        fprintf('Found it. Using data_root = %s\n', data_root);
    end
    if ~isfile(csv_path)
        error('''%s'' was not found in the current folder (%s).', csv_path, pwd);
    end
    if ~isfolder(data_root)
        error('data_root does not exist: %s', data_root);
    end

    sessions = readtable(csv_path);

    f_beta = 13:30;
    sfreq  = 250;

    stim_types = {'Sham', '20 Hz', '70 Hz'};
    stim_file_tags = {'Sham', '20Hz', '70Hz'};
    timepoints = {'BL', '15min', '45min'};
    tp_labels  = {'Baseline', '15min', '45min'};

    grand_results = struct('StimType', {}, 'Timepoint', {}, 'n_sessions', {}, ...
        'n_bursts_1sd', {}, 'mean_power_1sd', {}, 'n_bursts_p75', {}, 'mean_power_p75', {});

    for si = 1:numel(stim_types)
        stim = stim_types{si};

        heatmap_rows       = [];
        binarized_1sd_rows = [];
        binarized_p75_rows = [];
        t_common = [];

        for ti = 1:numel(timepoints)
            tp = timepoints{ti};
            sub_sessions = sessions(strcmp(sessions.StimType, stim) & strcmp(sessions.Timepoint, tp), :);

            [row_result, z_power, bin_1sd, bin_p75, t_common] = load_average_detect( ...
                sub_sessions, stim, tp, data_root, f_beta, sfreq, t_common);

            if isempty(row_result)
                continue;   % this cell had zero usable sessions, skip its row entirely
            end

            grand_results(end+1) = row_result; %#ok<AGROW>
            heatmap_rows(end+1, :) = z_power; %#ok<AGROW>
            binarized_1sd_rows(end+1, :) = bin_1sd; %#ok<AGROW>
            binarized_p75_rows(end+1, :) = bin_p75; %#ok<AGROW>
        end

        if isempty(heatmap_rows)
            fprintf('\nNo usable data for %s at all -- skipping its figures.\n', stim);
            continue;
        end

        % --- This stim type's own dedicated heatmap (rows = its timepoints) ---
        figure('Position', [100 100 900 400]);
        imagesc(t_common, 1:size(heatmap_rows, 1), heatmap_rows);
        colormap(hot); colorbar;
        xline(0, '--w', 'LineWidth', 1.5);
        xline(4, ':w', 'LineWidth', 1.5);
        set(gca, 'YTick', 1:size(heatmap_rows, 1), 'YTickLabel', tp_labels(1:size(heatmap_rows, 1)));
        xlabel('Time (s)');
        title(sprintf('C3 Grand-Average Beta Power (z-scored) -- %s', stim));
        saveas(gcf, sprintf('grand_avg_heatmap_%s.png', stim_file_tags{si}));

        % --- This stim type's own binarized bursts, mean+1SD ---
        figure('Position', [100 100 900 400]);
        plot_binarized_grand(binarized_1sd_rows, t_common, tp_labels(1:size(heatmap_rows, 1)), ...
            sprintf('C3 Grand-Average Bursts -- %s -- Mean + 1SD', stim));
        saveas(gcf, sprintf('grand_avg_binarized_%s_mean1sd.png', stim_file_tags{si}));

        % --- This stim type's own binarized bursts, 75th percentile ---
        figure('Position', [100 100 900 400]);
        plot_binarized_grand(binarized_p75_rows, t_common, tp_labels(1:size(heatmap_rows, 1)), ...
            sprintf('C3 Grand-Average Bursts -- %s -- 75th Percentile', stim));
        saveas(gcf, sprintf('grand_avg_binarized_%s_p75.png', stim_file_tags{si}));

        fprintf('Saved 3 figures for %s\n', stim);
    end

    % --- Summary table + CSV (all 9 cells together, for reference) ---
    T = struct2table(grand_results);
    writetable(T, 'grand_average_results.csv');
    fprintf('\nWrote grand_average_results.csv (%d rows)\n', height(T));
    disp(T);
end


%% =========================================================================
%  load_average_detect  (local function)
%  Loads + averages every session in ONE (StimType, Timepoint) cell, runs
%  both threshold methods on the grand-average, and returns the summary
%  row plus the data needed for that cell's heatmap/binarized rows.
% =========================================================================
function [row_result, z_power, bin_1sd, bin_p75, t_common] = load_average_detect( ...
    sub_sessions, stim, tp, data_root, f_beta, sfreq, t_common)

    n_samples_target = round(9 * sfreq) + 1;   % 2251 samples, -1 to 8s @ 250Hz

    fprintf('\n--- %s | %s (%d candidate sessions) ---\n', stim, tp, height(sub_sessions));

    TF_sum = [];
    n_loaded = 0;
    freqs_all_ref = [];
    row_result = [];
    z_power = [];
    bin_1sd = [];
    bin_p75 = [];

    for k = 1:height(sub_sessions)
        subj = sub_sessions.SubjectID{k};
        sess = sub_sessions.Session{k};

        tp_folder = tp;
        if strcmpi(tp, 'BL')
            tp_folder = 'Baseline';
        end
        folder_pattern = sprintf('%s_%s_%s_Motor_band_notch_resample*', subj, sess, tp_folder);
        subject_dir = fullfile(data_root, subj);

        if ~isfolder(subject_dir)
            fprintf('  %s | %s: subject folder not found, skipping\n', subj, sess);
            continue;
        end
        matching_folders = dir(fullfile(subject_dir, folder_pattern));
        matching_folders = matching_folders([matching_folders.isdir]);
        if isempty(matching_folders)
            fprintf('  %s | %s: no matching folder, skipping\n', subj, sess);
            continue;
        end
        session_folder = fullfile(matching_folders(1).folder, matching_folders(1).name);

        all_mat_files = dir(fullfile(session_folder, 'timefreq_morlet_*.mat'));
        base_mask = ~contains({all_mat_files.name}, '_ersd');
        mat_files = all_mat_files(base_mask);
        if isempty(mat_files)
            fprintf('  %s | %s: no base file, skipping\n', subj, sess);
            continue;
        end
        file_path = fullfile(mat_files(1).folder, mat_files(1).name);

        try
            [TF_c3_full, freqs_all, t_raw, sfreq_file] = load_timefreq_morlet(file_path); %#ok<ASGLU>
        catch ME
            fprintf('  %s | %s: load failed (%s), skipping\n', subj, sess, ME.message);
            continue;
        end

        [~, idx_start] = min(abs(t_raw - (-1)));
        idx_end = idx_start + n_samples_target - 1;
        if idx_end > numel(t_raw)
            idx_end = numel(t_raw);
            idx_start = idx_end - n_samples_target + 1;
        end
        if idx_start < 1 || (idx_end - idx_start + 1) ~= n_samples_target
            fprintf('  %s | %s: insufficient samples, skipping\n', subj, sess);
            continue;
        end
        crop_idx = idx_start:idx_end;
        TF_cropped = TF_c3_full(:, crop_idx, :);
        t_this = t_raw(crop_idx);

        if isempty(t_common)
            t_common = t_this;
        end
        if isempty(freqs_all_ref)
            freqs_all_ref = freqs_all;
        end

        if ~isequal(freqs_all, freqs_all_ref)
            fprintf('  %s | %s: frequency axis differs from the reference (%d vs %d bins) -- skipping\n', ...
                subj, sess, numel(freqs_all), numel(freqs_all_ref));
            continue;
        end
        if ~isempty(TF_sum) && ~isequal(size(TF_cropped), size(TF_sum))
            fprintf('  %s | %s: TF shape [%s] does not match running average [%s] -- skipping\n', ...
                subj, sess, num2str(size(TF_cropped)), num2str(size(TF_sum)));
            continue;
        end

        if isempty(TF_sum)
            TF_sum = TF_cropped;
        else
            TF_sum = TF_sum + TF_cropped;
        end
        n_loaded = n_loaded + 1;
        fprintf('  %s | %s: loaded\n', subj, sess);
    end

    if n_loaded == 0
        warning('No sessions loaded for %s | %s -- skipping this cell entirely.', stim, tp);
        return;
    end

    TF_grand_avg = TF_sum / n_loaded;
    fprintf('  -> grand average built from %d sessions\n', n_loaded);

    beta_mask = ismember(freqs_all_ref, f_beta);
    TF_beta = TF_grand_avg(:, :, beta_mask);
    ap_beta = fit_aperiodic_straightline(TF_grand_avg, freqs_all_ref, f_beta, sfreq);

    % --- Method A: mean + 1SD ---
    burst_1sd_raw = extract_bursts(TF_beta, ap_beta, sfreq, 1);
    [bursts_1sd, ~] = extract_bursts_flexible_intervals(burst_1sd_raw, t_common, sfreq, 'f_beta', f_beta);
    all_b_1sd = [bursts_1sd{:}];
    n_b_1sd = numel(all_b_1sd);
    if n_b_1sd > 0
        mean_pow_1sd = mean([all_b_1sd.mean_amplitude]);
    else
        mean_pow_1sd = NaN;
    end

    % --- Method B: 75th percentile ---
    burst_p75_raw = extract_bursts_percentile(TF_beta, ap_beta, sfreq, 75);
    [bursts_p75, ~] = extract_bursts_flexible_intervals(burst_p75_raw, t_common, sfreq, 'f_beta', f_beta);
    all_b_p75 = [bursts_p75{:}];
    n_b_p75 = numel(all_b_p75);
    if n_b_p75 > 0
        mean_pow_p75 = mean([all_b_p75.mean_amplitude]);
    else
        mean_pow_p75 = NaN;
    end

    fprintf('  -> mean+1SD: %d bursts | 75th pct: %d bursts\n', n_b_1sd, n_b_p75);

    row_result = struct('StimType', stim, 'Timepoint', tp, 'n_sessions', n_loaded, ...
        'n_bursts_1sd', n_b_1sd, 'mean_power_1sd', mean_pow_1sd, ...
        'n_bursts_p75', n_b_p75, 'mean_power_p75', mean_pow_p75);

    beta_power_t = squeeze(mean(TF_beta, 3));
    z_power = (beta_power_t - mean(beta_power_t)) / std(beta_power_t);

    bin_1sd_filt = filter_bursts_by_duration(burst_1sd_raw, 30);
    bin_1sd = any(bin_1sd_filt > 0, 3);

    bin_p75_filt = filter_bursts_by_duration(burst_p75_raw, 30);
    bin_p75 = any(bin_p75_filt > 0, 3);
end


function plot_binarized_grand(bin_mat, t, row_labels, title_str)
    hold on;
    for r = 1:size(bin_mat, 1)
        idx = find(bin_mat(r, :));
        if ~isempty(idx)
            scatter(t(idx), repmat(r, 1, numel(idx)), 10, 'r', 'filled');
        end
    end
    xline(0, '--k'); xline(4, ':k');
    set(gca, 'YTick', 1:numel(row_labels), 'YTickLabel', row_labels);
    xlabel('Time (s)');
    title(title_str);
    ylim([0, size(bin_mat, 1) + 1]);
    box on;
end

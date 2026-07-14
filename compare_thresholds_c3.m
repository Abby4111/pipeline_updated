%% =========================================================================
%  compare_thresholds_c3
%  Builds the exact two-step visualization from the S99 report (z-scored
%  power heatmap, then binarized burst detection) for THREE threshold
%  methods side by side: mean+2SD (current default), mean+1SD (looser),
%  and 75th percentile, so burst count under each can be compared directly.
%
%  *** FLAGGED ASSUMPTION ***
%  c3_row defaults to 13 (1-based), carried over from a DIFFERENT
%  subject's (AD0109, older-adult dataset) channel.mat file -- it has
%  NOT been independently confirmed against S99's own channel montage.
%  If S99 has its own channel.mat, check it the same way AD0109's was
%  checked (find(strcmp(Channel_names, 'C3'))) before trusting this.
%
%  Reuses compute_TF, compute_aperiodic_beta, extract_bursts,
%  extract_bursts_percentile, and filter_bursts_by_duration unchanged.
%
%  INPUT
%    trial_folder - folder containing data_S_99_trial*.mat files
%                   (default: current folder)
%    c3_row       - 1-based row index of C3 in the 64-channel data
%                   (default: 13, SEE ASSUMPTION ABOVE)
%
%  OUTPUT: saves 5 figures to the current folder:
%    c3_heatmap.png                     - z-scored power, all trials
%    c3_binarized_mean2sd.png           - detected bursts, mean+2SD
%    c3_binarized_mean1sd.png           - detected bursts, mean+1SD
%    c3_binarized_p75.png               - detected bursts, 75th percentile
%    threshold_comparison_burst_count.png - bar chart, total burst count
%  Also prints the burst count for each method to the console.
% =========================================================================
function compare_thresholds_c3(trial_folder, c3_row)

    if nargin < 1 || isempty(trial_folder)
        trial_folder = pwd;
    end
    if nargin < 2 || isempty(c3_row)
        c3_row = 13;
        warning(['Using C3 = row 13, an assumption carried over from a DIFFERENT ' ...
            'subject''s channel file (AD0109). Confirm against S99''s own channel ' ...
            'montage if exact precision matters.']);
    end

    trial_files = dir(fullfile(trial_folder, 'data_S_99_trial*.mat'));
    if isempty(trial_files)
        error('No data_S_99_trial*.mat files found in: %s', trial_folder);
    end
    fprintf('Found %d trial files in %s\n', numel(trial_files), trial_folder);

    sfreq  = 250;
    f_beta = 13:30;
    min_dur_samples = 30;   % 120ms @ 250Hz, matches S99 pipeline convention

    heatmap_data  = [];
    binarized_2sd = [];
    binarized_1sd = [];
    binarized_p75 = [];
    t_common = [];

    for i = 1:numel(trial_files)
        fpath = fullfile(trial_files(i).folder, trial_files(i).name);
        S = load(fpath, 'F', 'Time');

        % Crop to a FIXED sample count (not a floating-point Time
        % comparison) so every trial produces exactly the same length,
        % regardless of tiny floating-point differences in each trial's
        % own Time vector (one trial's -1 to 8s window came out 1 sample
        % shorter than another's under a direct >=/<= comparison).
        n_samples_target = round(9 * sfreq) + 1;   % 2251 samples, -1 to 8s @ 250Hz
        [~, idx_start] = min(abs(S.Time - (-1)));
        idx_end = idx_start + n_samples_target - 1;
        if idx_end > numel(S.Time)
            idx_end = numel(S.Time);
            idx_start = idx_end - n_samples_target + 1;
        end
        crop_idx = idx_start:idx_end;
        Value_c3 = S.F(c3_row, crop_idx);
        t = S.Time(crop_idx);
        if isempty(t_common)
            t_common = t;
        end

        if numel(t) ~= n_samples_target
            warning('Trial %s produced %d samples (expected %d) -- skipping.', ...
                trial_files(i).name, numel(t), n_samples_target);
            continue;
        end

        fprintf('[%d/%d] %s ... ', i, numel(trial_files), trial_files(i).name);

        % --- Shared steps (threshold-independent) ---
        TF = compute_TF(Value_c3, t, f_beta);
        [ap_beta, ~] = compute_aperiodic_beta(Value_c3, f_beta, sfreq);

        % --- Heatmap: z-scored beta-band power (no thresholding) ---
        beta_power_t = squeeze(mean(TF, 3));
        z_power = (beta_power_t - mean(beta_power_t)) / std(beta_power_t);
        heatmap_data(end+1, :) = z_power; %#ok<AGROW>

        % --- Method 1: mean + 2SD (current pipeline default) ---
        burst_2sd = extract_bursts(TF, ap_beta, sfreq, 2);
        burst_2sd_filt = filter_bursts_by_duration(burst_2sd, min_dur_samples);
        binarized_2sd(end+1, :) = any(burst_2sd_filt > 0, 3); %#ok<AGROW>

        % --- Method 2: mean + 1SD (looser SD-based cutoff) ---
        burst_1sd = extract_bursts(TF, ap_beta, sfreq, 1);
        burst_1sd_filt = filter_bursts_by_duration(burst_1sd, min_dur_samples);
        binarized_1sd(end+1, :) = any(burst_1sd_filt > 0, 3); %#ok<AGROW>

        % --- Method 3: 75th percentile ---
        burst_p75 = extract_bursts_percentile(TF, ap_beta, sfreq, 75);
        burst_p75_filt = filter_bursts_by_duration(burst_p75, min_dur_samples);
        binarized_p75(end+1, :) = any(burst_p75_filt > 0, 3); %#ok<AGROW>

        % --- Diagnostic: confirm WHY the methods diverge, rather      ---
        % --- than just observing that they do. Prints, for one          ---
        % --- representative window, the actual threshold each method   ---
        % --- computed vs. the max residual available in that window -- ---
        % --- if a threshold exceeds the max, zero detections there is  ---
        % --- mathematically correct, not a bug.                        ---
        win_samples = round(sfreq);
        w_check = 5;   % a representative window (~t=3-4s)
        idx_check = (w_check-1)*win_samples+1 : min(w_check*win_samples, numel(t));
        ap_w = ap_beta(:, w_check, :);
        resi_check = TF(:, idx_check, :) - ap_w;
        resi_check(resi_check < 0) = 0;
        thre_2sd = mean(resi_check, 2) + 2*std(resi_check, 0, 2);
        thre_1sd = mean(resi_check, 2) + 1*std(resi_check, 0, 2);
        thre_p75 = prctile(resi_check, 75, 2);
        fprintf('\n  [diagnostic, window %d] max residual = %.4g | mean+2SD = %.4g | mean+1SD = %.4g | 75th-pct = %.4g\n', ...
            w_check, max(resi_check(:)), max(thre_2sd(:)), max(thre_1sd(:)), max(thre_p75(:)));

        fprintf('done\n');
    end

    % --- Burst counts: count contiguous supra-threshold runs per trial ---
    count_bursts = @(bin_mat) sum(arrayfun(@(r) ...
        sum(diff([0, bin_mat(r, :), 0]) == 1), 1:size(bin_mat, 1)));
    n_bursts_2sd = count_bursts(binarized_2sd);
    n_bursts_1sd = count_bursts(binarized_1sd);
    n_bursts_p75 = count_bursts(binarized_p75);

    fprintf('\n=== Burst count comparison (C3, %d trials) ===\n', numel(trial_files));
    fprintf('Mean + 2SD:      %d bursts total\n', n_bursts_2sd);
    fprintf('Mean + 1SD:      %d bursts total\n', n_bursts_1sd);
    fprintf('75th percentile: %d bursts total\n', n_bursts_p75);

    % --- Figure 1: z-scored heatmap ---
    figure('Position', [100 100 900 500]);
    imagesc(t_common, 1:size(heatmap_data, 1), heatmap_data);
    colormap(hot); colorbar;
    xline(0, '--w', 'LineWidth', 1.5);
    xline(4, ':w', 'LineWidth', 1.5);
    xlabel('Time (s)'); ylabel('Trial');
    title('C3 Beta Power Heatmap (z-scored)');
    saveas(gcf, 'c3_heatmap.png');

    % --- Figure 2: binarized, mean+2SD ---
    figure('Position', [100 100 900 500]);
    plot_binarized_local(binarized_2sd, t_common, ...
        sprintf('C3 Binarized Beta Bursts -- Mean + 2SD (%d bursts)', n_bursts_2sd));
    saveas(gcf, 'c3_binarized_mean2sd.png');

    % --- Figure 3: binarized, mean+1SD ---
    figure('Position', [100 100 900 500]);
    plot_binarized_local(binarized_1sd, t_common, ...
        sprintf('C3 Binarized Beta Bursts -- Mean + 1SD (%d bursts)', n_bursts_1sd));
    saveas(gcf, 'c3_binarized_mean1sd.png');

    % --- Figure 4: binarized, 75th percentile ---
    figure('Position', [100 100 900 500]);
    plot_binarized_local(binarized_p75, t_common, ...
        sprintf('C3 Binarized Beta Bursts -- 75th Percentile (%d bursts)', n_bursts_p75));
    saveas(gcf, 'c3_binarized_p75.png');

    % --- Figure 5: burst count comparison bar chart ---
    figure('Position', [100 100 500 400]);
    bar([n_bursts_2sd, n_bursts_1sd, n_bursts_p75]);
    set(gca, 'XTickLabel', {'Mean + 2SD', 'Mean + 1SD', '75th Percentile'});
    ylabel('Total Burst Count');
    title(sprintf('Burst Count by Threshold Method (%d trials)', numel(trial_files)));
    saveas(gcf, 'threshold_comparison_burst_count.png');

    fprintf('\nSaved: c3_heatmap.png, c3_binarized_mean2sd.png, c3_binarized_mean1sd.png, c3_binarized_p75.png, threshold_comparison_burst_count.png\n');
end

function plot_binarized_local(bin_mat, t, title_str)
    hold on;
    for r = 1:size(bin_mat, 1)
        idx = find(bin_mat(r, :));
        if ~isempty(idx)
            scatter(t(idx), repmat(r, 1, numel(idx)), 10, 'r', 'filled');
        end
    end
    xline(0, '--k'); xline(4, ':k');
    xlabel('Time (s)'); ylabel('Trial');
    title(title_str);
    ylim([0, size(bin_mat, 1) + 1]);
    box on;
end

%% =========================================================================
%  extract_bursts_percentile
%  Same structure as extract_bursts.m, but thresholds each window at a
%  PERCENTILE of the residual distribution instead of mean + k*SD.
%  Built to directly compare against the current mean+2SD method.
%
%  For each 1-second window:
%    1. Subtract this window's aperiodic baseline from TF power
%    2. Rectify (negative residuals -> 0)
%    3. Threshold at the Nth percentile of the residual distribution
%       within this window (default: 75th percentile)
%
%  INPUT
%    TF         - [channels x timepoints x beta_freqs] Morlet power
%    ap_beta    - [channels x n_windows x beta_freqs] aperiodic per window
%    sfreq      - sampling frequency (Hz)
%    percentile - threshold percentile, 0-100 (default: 75)
%
%  OUTPUT
%    burst_raw - [channels x timepoints x beta_freqs] thresholded burst power
% =========================================================================
function burst_raw = extract_bursts_percentile(TF, ap_beta, sfreq, percentile)

    if nargin < 4 || isempty(percentile)
        percentile = 75;   % matches the percentile-based method referenced
                            % in the tACS pipeline documentation (Long et al.)
    end

    [n_chan, n_time, n_freq] = size(TF);
    n_windows   = size(ap_beta, 2);
    win_samples = round(sfreq);

    burst_raw = zeros(n_chan, n_time, n_freq);

    for w = 1:n_windows
        idx_start = (w-1) * win_samples + 1;
        idx_end   = min(w * win_samples, n_time);
        win_idx   = idx_start:idx_end;

        ap_w = ap_beta(:, w, :);

        resi = TF(:, win_idx, :) - ap_w;
        resi(resi < 0) = 0;

        % Threshold: Nth percentile computed within this window only
        % (same "per window, per channel, per frequency" granularity as
        % the mean+kSD method, just a different summary statistic).
        thre = prctile(resi, percentile, 2);

        win_burst = resi - thre;
        win_burst(win_burst < 0) = 0;

        burst_raw(:, win_idx, :) = win_burst;
    end
end

%% =========================================================================
%  run_batch_mrbd
%  Computes MRBD (Movement-Related Beta Desynchronization, %) time-course
%  for every included session -- a completely different metric from burst
%  detection: this is straight beta-band POWER over time, normalized to a
%  pre-movement baseline, expressed as % change. Matches the "Down" panel
%  style in Figures 13/14 (motor task, one line per timepoint).
%
%  MRBD(t) = (beta_power(t) - baseline_power) / baseline_power * 100
%  where baseline_power = mean beta power during -1.0 to 0s (pre-movement,
%  the widest pre-movement window our data actually covers).
%
%  *** IMPORTANT: this baseline is the PRE-MOVEMENT period WITHIN each
%  trial/session -- NOT the "Baseline" stimulation timepoint. Each of the
%  three timepoint sessions (Baseline/15min/45min) gets normalized to its
%  OWN pre-movement period, matching standard ERD/ERS convention. ***
%
%  Reuses load_timefreq_morlet and find_data_root_auto unchanged. No
%  burst detection involved at all -- just beta-band power averaging.
%
%  OUTPUT: writes 'mrbd_long.csv' (SubjectID, StimType, Timepoint, time_s,
%  mrbd_percent) -- one row per session per timepoint sample (~2251 rows
%  per session).
% =========================================================================
function all_mrbd = run_batch_mrbd(data_root, csv_path)

    SCRIPT_VERSION = 'v1 -- MRBD (%) time-course, normalized to pre-movement baseline (-1 to 0s)';
    fprintf('=== run_batch_mrbd %s ===\n', SCRIPT_VERSION);

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
    n = height(sessions);
    all_mrbd = struct('SubjectID', {}, 'Session', {}, 'StimType', {}, ...
        'Timepoint', {}, 't', {}, 'mrbd', {}, 'status', {});

    rows = {};   % accumulate for the long-format CSV as we go

    for i = 1:n
        subj = sessions.SubjectID{i};
        sess = sessions.Session{i};
        stim = sessions.StimType{i};
        tp   = sessions.Timepoint{i};

        tp_folder = tp;
        if strcmpi(tp, 'BL')
            tp_folder = 'Baseline';
        end
        folder_pattern = sprintf('%s_%s_%s_Motor_band_notch_resample*', subj, sess, tp_folder);
        subject_dir = fullfile(data_root, subj);

        fprintf('\n[%d/%d] %s | %s | %s | %s\n', i, n, subj, sess, stim, tp);

        if ~isfolder(subject_dir)
            warning('Subject folder not found, skipping: %s', subject_dir);
            all_mrbd(end+1) = struct('SubjectID', subj, 'Session', sess, ...
                'StimType', stim, 'Timepoint', tp, 't', [], 'mrbd', [], 'status', 'SUBJECT_FOLDER_NOT_FOUND'); %#ok<AGROW>
            continue;
        end

        matching_folders = dir(fullfile(subject_dir, folder_pattern));
        matching_folders = matching_folders([matching_folders.isdir]);
        if isempty(matching_folders)
            warning('No folder matching "%s" found.', folder_pattern);
            all_mrbd(end+1) = struct('SubjectID', subj, 'Session', sess, ...
                'StimType', stim, 'Timepoint', tp, 't', [], 'mrbd', [], 'status', 'FOLDER_NOT_FOUND'); %#ok<AGROW>
            continue;
        end
        session_folder = fullfile(matching_folders(1).folder, matching_folders(1).name);

        all_mat_files = dir(fullfile(session_folder, 'timefreq_morlet_*.mat'));
        base_mask = ~contains({all_mat_files.name}, '_ersd');
        mat_files = all_mat_files(base_mask);
        if isempty(mat_files)
            warning('No base timefreq_morlet file found in %s -- skipping.', session_folder);
            all_mrbd(end+1) = struct('SubjectID', subj, 'Session', sess, ...
                'StimType', stim, 'Timepoint', tp, 't', [], 'mrbd', [], 'status', 'NO_BASE_FILE_FOUND'); %#ok<AGROW>
            continue;
        end
        file_path = fullfile(mat_files(1).folder, mat_files(1).name);

        try
            [TF_c3_full, freqs_all, t, sfreq] = load_timefreq_morlet(file_path); %#ok<ASGLU>
        catch ME
            warning('Failed to load %s: %s', file_path, ME.message);
            all_mrbd(end+1) = struct('SubjectID', subj, 'Session', sess, ...
                'StimType', stim, 'Timepoint', tp, 't', [], 'mrbd', [], 'status', 'LOAD_FAILED'); %#ok<AGROW>
            continue;
        end

        f_beta     = 13:30;
        beta_mask  = ismember(freqs_all, f_beta);
        TF_c3_beta = TF_c3_full(:, :, beta_mask);          % [1 x timepoints x 18]
        beta_power_t = squeeze(mean(TF_c3_beta, 3));       % [timepoints x 1], averaged across beta freqs

        baseline_idx   = (t >= -1.0) & (t <= 0);
        baseline_power = mean(beta_power_t(baseline_idx));
        mrbd_t = (beta_power_t - baseline_power) / baseline_power * 100;

        all_mrbd(end+1) = struct('SubjectID', subj, 'Session', sess, ...
            'StimType', stim, 'Timepoint', tp, 't', t, 'mrbd', mrbd_t, 'status', 'OK'); %#ok<AGROW>

        for k = 1:numel(t)
            rows(end+1, :) = {subj, stim, tp, t(k), mrbd_t(k)}; %#ok<AGROW>
        end
    end

    ok_count = sum(strcmp({all_mrbd.status}, 'OK'));
    fprintf('\n=== Batch complete: %d / %d sessions processed successfully ===\n', ok_count, n);

    mrbd_table = cell2table(rows, 'VariableNames', {'SubjectID', 'StimType', 'Timepoint', 'time_s', 'mrbd_percent'});
    writetable(mrbd_table, 'mrbd_long.csv');
    fprintf('Wrote mrbd_long.csv (%d rows)\n', height(mrbd_table));
end

%% =========================================================================
%  run_batch_phases
%  Same pipeline as run_batch_older_adults.m (C3, straight-line aperiodic
%  removal, flexible intervals) but bucketed into George's THREE MOVEMENT
%  PHASES instead of uniform 1-second windows:
%    Pre-movement:  -1.0 to -0.1s  (clipped from George's -1.1 to -0.1s --
%                   our data starts at exactly -1.0s, confirmed from the
%                   file itself, so his window needs 0.1s we don't have)
%    Movement:       0.5 to  3.5s  (matches George's definition exactly)
%    Post-movement:  5.0 to  8.0s  (matches George's definition exactly)
%
%  This is needed for two specific figures that CANNOT be built from
%  run_batch_older_adults.m's output, since that aggregates across the
%  whole epoch rather than these three specific phases:
%    1. Movement-phase burst characteristics (Sham/Baseline only) --
%       Figure 11 style.
%    2. Per-timepoint burst characteristics extracted from the MOVEMENT
%       phase specifically, one figure per stimulation type -- Figure
%       13/14 style.
%
%  Reuses load_timefreq_morlet, fit_aperiodic_straightline, extract_bursts
%  unchanged. Only the interval-of-interest definition changes.
%
%  INPUT / OUTPUT: same as run_batch_older_adults.m, except
%  all_results(i).results.ioi_bursts / .ioi_starts_time now correspond to
%  the 3 phases (in order: pre-movement, movement, post-movement) instead
%  of 9 uniform 1-second windows.
% =========================================================================
function all_results = run_batch_phases(data_root, csv_path)

    SCRIPT_VERSION = 'v1 -- movement-phase bucketing (pre/movement/post), reuses run_batch_older_adults.m building blocks';
    fprintf('=== run_batch_phases %s ===\n', SCRIPT_VERSION);

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
    all_results = struct('SubjectID', {}, 'Session', {}, 'StimType', {}, ...
        'Timepoint', {}, 'results', {}, 'status', {});

    % George's three movement phases, clipped to what our data actually
    % covers (see header comment).
    phase_bounds    = [-1.0 -0.1; 0.5 3.5; 5.0 8.0];
    phase_names     = {'pre_movement', 'movement', 'post_movement'};

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
            all_results(end+1) = struct('SubjectID', subj, 'Session', sess, ...
                'StimType', stim, 'Timepoint', tp, 'results', [], 'status', 'SUBJECT_FOLDER_NOT_FOUND'); %#ok<AGROW>
            continue;
        end

        matching_folders = dir(fullfile(subject_dir, folder_pattern));
        matching_folders = matching_folders([matching_folders.isdir]);
        if isempty(matching_folders)
            warning('No folder matching "%s" found under: %s', folder_pattern, subject_dir);
            all_results(end+1) = struct('SubjectID', subj, 'Session', sess, ...
                'StimType', stim, 'Timepoint', tp, 'results', [], 'status', 'FOLDER_NOT_FOUND'); %#ok<AGROW>
            continue;
        end
        if numel(matching_folders) > 1
            warning('Multiple folders matched "%s" -- using the first (%s).', folder_pattern, matching_folders(1).name);
        end
        session_folder = fullfile(matching_folders(1).folder, matching_folders(1).name);

        all_mat_files = dir(fullfile(session_folder, 'timefreq_morlet_*.mat'));
        base_mask = ~contains({all_mat_files.name}, '_ersd');
        mat_files = all_mat_files(base_mask);

        if isempty(mat_files)
            warning('No base timefreq_morlet file found in %s -- skipping.', session_folder);
            all_results(end+1) = struct('SubjectID', subj, 'Session', sess, ...
                'StimType', stim, 'Timepoint', tp, 'results', [], 'status', 'NO_BASE_FILE_FOUND'); %#ok<AGROW>
            continue;
        end
        if numel(mat_files) > 1
            warning('Multiple base files found in %s -- using the first (%s).', session_folder, mat_files(1).name);
        end
        file_path = fullfile(mat_files(1).folder, mat_files(1).name);

        try
            [TF_c3_full, freqs_all, t, sfreq] = load_timefreq_morlet(file_path);
        catch ME
            warning('Failed to load %s: %s', file_path, ME.message);
            all_results(end+1) = struct('SubjectID', subj, 'Session', sess, ...
                'StimType', stim, 'Timepoint', tp, 'results', [], 'status', 'LOAD_FAILED'); %#ok<AGROW>
            continue;
        end

        f_beta     = 13:30;
        beta_mask  = ismember(freqs_all, f_beta);
        TF_c3_beta = TF_c3_full(:, :, beta_mask);

        ap_beta   = fit_aperiodic_straightline(TF_c3_full, freqs_all, f_beta, sfreq);
        burst_raw = extract_bursts(TF_c3_beta, ap_beta, sfreq, 2);

        [phase_bursts, phase_starts_time] = extract_bursts_flexible_intervals(burst_raw, t, sfreq, ...
            'f_beta', f_beta, 'custom_intervals', phase_bounds);

        results.phase_bursts      = phase_bursts;       % {1 x 3}: pre, movement, post
        results.phase_names       = phase_names;
        results.phase_starts_time = phase_starts_time;

        all_results(end+1) = struct('SubjectID', subj, 'Session', sess, ...
            'StimType', stim, 'Timepoint', tp, 'results', results, 'status', 'OK'); %#ok<AGROW>
    end

    ok_count = sum(strcmp({all_results.status}, 'OK'));
    fprintf('\n=== Batch complete: %d / %d sessions processed successfully ===\n', ok_count, n);
end

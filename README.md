# Beta Burst Detection & Analysis — Full Code Archive

This folder contains every script used across the full analysis: from validating
the burst-detection pipeline on Subject S99, through to applying it to the
15-participant older-adult tACS dataset, running statistics, and generating
every figure produced along the way.

---

## Directory structure

```
README.md                                  This file
Beta_Burst_tACS_Report.docx                First report (full pipeline + tACS results)
Threshold_and_GrandAverage_Findings.docx   Second report (threshold validation + grand-average findings)
matlab/
  s99_pipeline/            Original single-subject (S99) validation pipeline
  older_adults_pipeline/   The pipeline actually used on the tACS dataset
  analysis/                Summarization, statistics, and phase/MRBD analyses
  threshold_comparison/    Mean+2SD vs mean+1SD vs 75th-percentile, tested on real S99 data
  grand_average/           "Average first, then extract" analysis for the tACS dataset (precomputed-TF version)
  real_sprint_average_first/ Same "average first" philosophy, but on REAL raw per-trial signal with FULL SPRiNT -- see Section 7, a major discovery
python_plotting/           Scripts that generated the final report figures
figures/                   All generated figures (12 PNGs)
data/                      Supporting data files (inclusion lists, exported CSVs)
presentations/             Final slide decks + speaking script
```

---

## 1. Project overview, in order

1. **`s99_pipeline/`** — A beta burst detection pipeline was built and validated
   on a single subject (S99), using full SPRiNT for aperiodic (1/f) background
   removal on **raw EEG signal**, then Morlet wavelet decomposition, thresholding,
   and 2D (time × frequency) blob-based burst detection.
2. **`older_adults_pipeline/`** — The same general approach was then applied to
   the 15-participant older-adult tACS dataset (C3 electrode only, per George
   Lungoci's thesis methodology). **Important divergence found along the way:**
   the tACS dataset's exported files (`timefreq_morlet_*.mat`) turned out to be
   **Brainstorm-precomputed, 46-trial-averaged Morlet power** — not raw signal.
   This meant full SPRiNT (which needs raw signal to run its own internal
   spectral decomposition) could not be used here. A **straight-line log-log
   fit** was used instead for aperiodic removal on this dataset
   (`fit_aperiodic_straightline.m`) — a genuinely different, simpler method
   than SPRiNT, not a drop-in equivalent. This is also very possibly why the
   *original* tACS analysis (George's thesis) used a simplified fit rather
   than full SPRiNT — it may not have had raw signal access either.
3. **`analysis/`** — Burst-level results were summarized, aggregated by
   Stimulation Type × Timepoint, and tested with linear mixed-effects models.
   Two follow-up analyses were then built on top of the same underlying data:
   - **Movement-phase bucketing** (`run_batch_phases.m`) — re-detects bursts
     using George's actual movement-phase boundaries (pre-movement /
     movement / post-movement) instead of uniform 1-second windows, to
     reproduce his Figure 11/13/14-style comparisons.
   - **MRBD** (`run_batch_mrbd.m`) — a completely separate metric (% beta
     power change from a pre-movement baseline, no burst detection involved)
     that reproduces the classic ERD/ERS motor-cortex signature, and serves
     as an independent check on the pipeline.

---

## 2. `matlab/s99_pipeline/` — Single-subject validation

| File | Purpose |
|---|---|
| `run_burst_pipeline.m` | Main entry point. Raw EEG → Morlet → SPRiNT aperiodic removal → threshold (mean+2SD/window) → duration filter → peak detection. All-channel (64ch), full epoch. |
| `compute_TF.m` | Morlet wavelet time-frequency decomposition. |
| `compute_aperiodic_beta.m` | Full SPRiNT aperiodic fit (needs raw signal). |
| `extract_bursts.m` | Per-window thresholding (mean + k·SD). |
| `filter_bursts_by_duration.m` | Minimum-duration filter (original, non-flexible-interval version). |
| `burst_detection-2.m` | Original 2D blob-detection functions (`find_all_peaks_3D`, `detect_peaks_2D`, `extract_peak_info`) that the flexible-interval detector's frequency-merging logic was ported from. |
| `test_peak_detection_example.m` | Smoke test for the above. |

**To run:** `results = run_burst_pipeline(Value, t, 'sfreq', 250)` where `Value`
is a `[channels x timepoints]` raw signal and `t` is the matching time vector.
Requires the SPRiNT and Brainstorm MATLAB toolboxes on the path.

---

## 3. `matlab/older_adults_pipeline/` — Applied to the tACS dataset

| File | Purpose |
|---|---|
| `run_batch_older_adults.m` | **Main batch entry point.** Loops over every included session, loads precomputed TF, runs aperiodic removal + burst detection, aggregates results. Auto-detects the data folder if not given one. |
| `load_timefreq_morlet.m` | Loads a `timefreq_morlet_*.mat` file, extracts C3 **by channel name** (its row index is *not* fixed across files — confirmed one file had it at row 12, another convention would put it at row 13). |
| `find_data_root_auto.m` | Searches Desktop/Downloads/Documents/Home for a `timefreq_morlet_*.mat` file to infer the data root automatically. |
| `fit_aperiodic_straightline.m` | Straight-line log-log aperiodic fit — used **instead of SPRiNT** because this dataset's files are precomputed TF power, not raw signal. |
| `extract_bursts_flexible_intervals.m` | **Core burst detector.** Combines two things: (1) George Lungoci's "flexible intervals" method (thesis p.47) so bursts aren't truncated at an interval boundary, and (2) 2D connected-blob detection so a burst spanning several adjacent frequency bins counts once, not once per bin. Supports both uniform 1-second windows AND custom non-uniform intervals (used for phase bucketing, see below). |
| `run_burst_pipeline_older_adults_C3.m` | **Superseded / not used for final results.** An earlier attempt that assumed raw signal input before the precomputed-TF discovery was made. Kept for reference only. |

**To run:**
```matlab
all_results = run_batch_older_adults();   % auto-detects data_root
% or explicitly:
all_results = run_batch_older_adults(data_root, 'included_sessions.csv');
```

**Known limitation:** `extended_pad_sec` (the flexible-interval padding size)
is a placeholder value (0.5s) — the real value from George's thesis was never
confirmed. This affects exact burst boundary handling near interval edges.

---

## 4. `matlab/analysis/` — Summarization, statistics, phases, MRBD

| File | Purpose |
|---|---|
| `summarize_batch_results.m` | Turns `all_results` into one row per session (burst count, rate, mean duration, mean amplitude — raw **and** ×10¹² scaled for numerical stability / readability). |
| `summarize_by_group.m` | Groups the above by Stimulation Type × Timepoint (mean, std, N per cell). |
| `run_lme_analysis.m` | Linear mixed-effects models (Subject as random intercept) testing Stimulation Type × Time on rate, duration, and amplitude. **Result: no significant effects found** (all p > 0.19) — see caveats below on why this isn't directly comparable to the original tACS analysis's significant findings. |
| `run_batch_phases.m` | Re-runs burst detection using George's **movement-phase boundaries** (pre-movement −1.0 to −0.1s [clipped from his −1.1 to −0.1s — our data starts at exactly −1.0s], movement 0.5–3.5s, post-movement 5.0–8.0s) instead of uniform windows. |
| `summarize_phase_results.m` | Long-format export of phase-bucketed results (`phase_summary_long.csv`) — one row per session × phase. |
| `run_batch_mrbd.m` | Computes MRBD (%) time-course per session: beta power at each timepoint, normalized to that session's own pre-movement baseline (−1.0 to 0s). No burst detection involved — pure power. Exports `mrbd_long.csv`. |

---

## 5. `matlab/threshold_comparison/` — Which threshold method should we actually use?

| File | Purpose |
|---|---|
| `extract_bursts_percentile.m` | Same structure as `extract_bursts.m`, but thresholds each window at a **percentile** (default 75th) of the residual distribution instead of mean + k·SD. |
| `compare_thresholds_c3.m` | Runs **three** threshold methods side by side on real S99 trial data (mean+2SD, mean+1SD, 75th percentile), reproducing the exact two-step visualization style from the original S99 report (z-scored heatmap, then binarized burst plot) for each. Includes a built-in diagnostic that prints the actual threshold value vs. the max residual in a representative window, so any "zero bursts detected" result can be verified as mathematically real rather than assumed to be a bug. |

**Key finding (see the second report, `Threshold_and_GrandAverage_Findings.docx`, for full detail): on real S99 trial data, mean+2SD detected 0 bursts while 75th percentile detected 36, on the same two trials.** This was not a bug — the diagnostic confirmed the mean+2SD threshold sat meaningfully higher than the max residual value available in a representative window, driven by the residual distribution's shape after rectification (a spike at zero plus a right-skewed tail, not normal — exactly the concern flagged much earlier in this project). Mean+1SD was added as a third, intermediate method for the same comparison.

**Only 2 of the original 36 S99 trials were used for this comparison** (`data_S_99_trial005.mat`, `007.mat` — the only two ever actually uploaded/available). The mechanism is clearly real, but confirming it holds at full scale requires running this same script against all 36 trial files.

---

## 6. `matlab/grand_average/` — "Average first, then extract" for the tACS dataset

| File | Purpose |
|---|---|
| `run_grand_average_c3.m` | For each of the 9 Stimulation Type × Timepoint cells: loads every included session's C3 broadband power, **averages them together into one grand-average trace BEFORE running aperiodic removal or burst detection** (not per-session detection averaged afterward — a genuinely different measurement). Runs both mean+1SD and 75th percentile on each grand-average. Produces one dedicated heatmap + two binarized-burst figures **per stimulation type** (so 70Hz's figures show only its own 3 timepoints, not mixed with Sham/20Hz). |

**Critical data-quality issue found while running this, not yet fixed:** many sessions were silently dropped with the message *"frequency axis differs from the reference (90 vs 55 bins)"*. Roughly half of all sessions apparently have a 90-bin frequency axis instead of the expected 55-bin one, and the script currently just discards whichever session doesn't match whatever loaded first in that cell — it does **not** crop to a shared/common frequency range. This is a distinct issue from the earlier AD0109 epoch-length inconsistency, and it's more severe: some cells (e.g. `20 Hz / Baseline`) ended up averaging **exactly 1 session** out of 4 candidates. **This needs fixing (crop every session to the overlapping 1–55Hz range instead of dropping mismatches) before the grand-average results should be trusted or reported further.**

---

## 7. `matlab/real_sprint_average_first/` — A major discovery: real per-trial data exists

| File | Purpose |
|---|---|
| `burst_prop_one.m` | Uploaded reference script (burst propagation + lateral regression analysis). Its own configuration (`data_dir` pointing at an AD0109 folder, `subject_id = 'S_99'`) is what **confirmed** the `data_S_99_trial*.mat` files used throughout the S99-labeled parts of this project are actually AD0109's raw per-trial signal — not a separate validation subject, and not the precomputed TF used for the rest of the tACS dataset. |
| `run_average_first_c3_real_sprint.m` | Given that discovery: loads every good raw trial for one session, averages them together FIRST (same "average first" philosophy as `run_grand_average_c3.m`), then runs **full SPRiNT** (not the straight-line approximation) on that real average. Detects bursts under **three** threshold methods side by side (mean+2SD, mean+1SD, 75th percentile) and reports rate/duration/amplitude for pre/movement/post-movement phases. |

**A second major discovery while running this**: a folder never referenced anywhere else in this project, `BS_trial_data_extracted_from_BS_db_Kenya_Preprocessed 3` (note the `3`, distinct from the `2` folder every other tACS script uses), contains **raw per-trial data for every subject and session** in the study, not just AD0109. This means the straight-line-fit workaround relied on throughout Sections 3 and 6 may not have been necessary at all for any of the tACS analysis — real per-trial data, and therefore real full SPRiNT, may be available study-wide. **This has not been scaled up yet** — only one session (AD0109, Baseline, 31 trials) has been run this way. Deciding whether to redo the tACS analysis study-wide with real SPRiNT is a real, substantial decision, documented as an open question in the third report.

**Result on that one session** (Table, also see `figures/threshold_comparison_real_sprint.png`):

| Method | Pre-movement | Movement | Post-movement |
|---|---|---|---|
| Mean + 2SD | 2 bursts, 2.00/s | 5 bursts, 1.25/s | 4 bursts, 1.00/s |
| Mean + 1SD | 3 bursts, 3.00/s | 8 bursts, 2.00/s | 11 bursts, 2.75/s |
| 75th percentile | 4 bursts, 4.00/s | 10 bursts, 2.50/s | 14 bursts, 3.50/s |

Unlike the earlier 2-trial S99/AD0109 comparison (Section 5), mean+2SD did **not** collapse to zero here — averaging 31 real trials together smooths out the noise spikes that made the strict threshold so unstable on single-trial data. All three methods now agree on the general shape (rising through the phases), though mean+2SD remains consistently the strictest.

---

## 8. `python_plotting/` — Figure generation

These read the CSVs in `data/` (or the values pasted directly into
`plot_timepoint_comparisons.py` from MATLAB's console output) and produce the
final PNGs in `figures/`. Requires `pandas` and `matplotlib`.

```bash
cd python_plotting
python plot_timepoint_comparisons.py           # burst_count/rate/duration/amplitude.png
python plot_phase_comparisons.py                # fig1_*.png, fig2_movement_*.png (needs ../data/phase_summary_long.csv)
python plot_mrbd.py                             # mrbd_*.png (needs ../data/mrbd_long.csv)
python plot_grand_average_summary.py            # grand_avg_summary_4panel.png (needs ../data/grand_average_results.csv)
python plot_real_sprint_threshold_comparison.py # threshold_comparison_real_sprint.png (needs ../data/real_sprint_threshold_comparison.csv)
```

---

## 9. Figures reference

| File | What it shows |
|---|---|
| `burst_count.png`, `burst_rate.png`, `burst_duration.png`, `burst_amplitude.png` | Whole-epoch burst characteristics, Sham/20Hz/70Hz × Baseline/15min/45min. |
| `fig1_movement_phase_sham_baseline.png` | Rate/Duration/Amplitude across Pre-movement→Movement→Post-movement, Sham+Baseline only. **N=3 subjects — illustrative only.** |
| `fig2_movement_Sham.png`, `fig2_movement_20Hz.png`, `fig2_movement_70Hz.png` | Rate/Duration/Amplitude across Baseline→15min→45min, extracted from the movement phase specifically, one figure per stimulation type. |
| `mrbd_Sham.png`, `mrbd_20Hz.png`, `mrbd_70Hz.png` | MRBD (%) time-course, −1 to 8s, one line per timepoint. Shows the expected ERD (desynchronization after movement onset) → ERS (post-movement beta rebound) pattern in all three conditions. |
| `grand_avg_summary_4panel.png` | Burst count and mean power, mean+1SD vs. 75th percentile, all 9 Stimulation Type × Timepoint cells, "average first" method (precomputed-TF version). Each point labeled with its actual session count (n). |
| `threshold_comparison_real_sprint.png` | Rate/Duration/Amplitude, all 3 threshold methods, real full-SPRiNT data (AD0109, Baseline, 31 trials averaged). |

---

## 10. Data files

| File | Contents |
|---|---|
| `included_sessions.csv` | The 47 sessions that passed strict quality filtering (any quality note or "Extract again" flag → excluded). 43 of these actually processed successfully; 4 have genuinely missing data folders (FB0901 S2 BL/45min, MB0522 S3 BL, FB0210 S1 BL). |
| `Session_Inclusion_Cleaned.xlsx` | Full inclusion/exclusion audit trail — which sessions were kept, which excluded and why, including the ones whose quality note actually read as approving despite being caught by the strict rule. |
| `phase_summary_long.csv` | Output of `summarize_phase_results.m` — 129 rows (43 sessions × 3 phases). |
| `mrbd_long.csv` | Output of `run_batch_mrbd.m` — ~95,000 rows (43 sessions × ~2200 timepoints each). |
| `grand_average_results.csv` | Output of `run_grand_average_c3.m` — 9 rows (one per StimType × Timepoint cell), burst count and mean power for both threshold methods, plus the actual session count that went into each grand average. |
| `real_sprint_threshold_comparison.csv` | Output of `run_average_first_c3_real_sprint.m` — 9 rows (3 methods × 3 phases), real full-SPRiNT results for AD0109's Baseline session. |

---

## 11. `presentations/` — Slide decks and speaking notes

| File | Contents |
|---|---|
| `Beta_Burst_tACS_FullDeck.pptx` | 14-slide, full-detail deck — pipeline explanation, all S99 figures with interpretation, full ANOVA table (all 9 effects, not just the significant ones), gender comparison, outlier-robustness check. The comprehensive version. |
| `Lab_Progress_Summary.pptx` | 12-slide, lean lab-progress deck — warm editorial theme (cream/terracotta/espresso), first-person voice throughout ("What I've Learned," not "What You've Learned"). Covers: what was built, why beta bursts matter, the pipeline, S99 validation findings (feature-level results + propagation), applying it to the tACS dataset, the tACS ANOVA results (significant effects only), current focus (decisions made vs. actively refining), and a closing summary. This is the deck actually meant for presenting to the lab. |
| `Speaking_Script.md` | Slide-by-slide talking points for `Lab_Progress_Summary.pptx`, written in first person, ~10 minutes at normal pace. Includes a dedicated "if someone pushes back" section anticipating the two hardest likely questions (the SD-threshold percentage question, and whether the propagation finding is causal). |

**Two earlier draft versions of these decks were built and then superseded during iteration** (a 7-slide overview draft, and an 11-slide pre-redesign version) — intentionally not included here, since they were fully replaced by the two final versions above and including them alongside the finished decks would just create confusion about which is current.

---

## 12. Important caveats to carry into the report

- **Aperiodic removal method differs from the original analysis.** Straight-line
  log-log fit here, vs. whatever (likely no real aperiodic removal) the
  original tACS analysis used. Not a like-for-like comparison.
- **Amplitude units are not directly comparable to George's thesis figures.**
  Our amplitude is raw wavelet **power** (physical units, inferred to be V²,
  never independently confirmed); his are given in **pV** (a voltage-amplitude
  unit). A √power conversion was attempted and landed ~17,000–35,000× off his
  reported range — meaning either the V² unit assumption is wrong, his
  "amplitude" isn't simply √power, or both. This was **not resolved** — treat
  the two sets of numbers as being on different, currently-unreconciled scales.
- **Sample sizes are small throughout** — typically N=3–6 sessions per
  Stimulation Type × Timepoint cell, occasionally down to N=3, and as low as
  **N=1** in the grand-average analysis (Section 6).
- **This tACS re-analysis found no significant effects** (`run_lme_analysis.m`),
  in contrast to the original analysis's several significant findings. Likely
  contributors: ~100× less data (session-level N=43 vs. trial-level N=4,242
  in the original), trial-averaging *before* burst detection (which smooths
  out the trial-to-trial variability bursts are defined by), and the different
  aperiodic-removal method. This should be reported as "this specific
  lower-powered re-analysis didn't detect them," not as evidence the original
  effects were wrong.
- **Subject AD0109 has inconsistent epoch lengths** across its sessions (three
  sessions truncated to ~4s instead of the standard 8s, one extended to 14s) —
  affects the MRBD curves for `Sham 15min`, `Sham 45min`, and `20Hz 15min`,
  which lose one contributing subject partway through the movement/
  post-movement portion of the time-course.
- **`extended_pad_sec` (flexible-interval padding) was never confirmed**
  against the actual value in George's thesis — currently a placeholder
  (0.5s).
- **Mean+2SD can produce zero detected bursts on real single-trial S99 data**
  (Section 5) — confirmed via diagnostic, not a bug, but a real consequence
  of the rectified residual distribution's shape combined with the 120ms
  minimum-duration filter. Worth deciding deliberately which threshold
  convention to standardize on going forward.
- **The grand-average ("average first") tACS analysis has an unresolved
  frequency-axis bug** (Section 6) causing severe, undocumented sample-size
  loss in several cells (as low as N=1). Needs fixing before those specific
  results are used in any report.
- **The grand-average method structurally cannot produce error bars** — since
  burst detection runs once on a single already-averaged trace per condition,
  there is exactly one number per condition, not multiple session-level
  replicates to compute a spread from. This is a real trade-off versus the
  per-session-then-average approach (Sections 1–4), not an oversight.
- **The real-SPRiNT analysis (Section 7) has only been run on ONE session**
  (AD0109, Baseline, 31 trials). The discovery that raw per-trial data may
  exist study-wide (in the `"...Preprocessed 3"` folder) has NOT been acted
  on beyond this single proof-of-concept — deciding whether to redo the
  entire tACS analysis this way is a real, substantial decision that has
  not yet been made.

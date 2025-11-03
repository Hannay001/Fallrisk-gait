# FallRisk-Gait v0.2 — Data Card

## Motivation
Synthetic, clinic-safe dataset for prototyping fall-risk and gait models (tabular features from short walk or iTUG). **Not for clinical use**.

## Composition
- Rows: ~50,000 synthetic trials (one row = one trial)
- Columns: age/sex (optional), spatiotemporal gait features, iTUG sub-tasks, labels
- File: `fallrisk_tabular_v1.csv` (+ `sample_1k.csv`)

## Synthesis
- Procedural seed (~2k rows) with plausible distributions & correlations
- SDV GaussianCopulaSynthesizer → large sample
- No real patient data; no re-identification attempts permitted

## Columns (units)
- age_years (years), sex (categorical)
- gait_speed_mps (m/s), stride_length_m (m), cadence_spm (steps/min)
- stride_time_var (s^2 or CV), double_support_pct (%), symmetry_index (ratio)
- turn_time_s (s), sit_to_stand_s (s), stand_to_sit_s (s), tug_seconds (s)

## Label Policies
- **Policy-A (TUG-centric):** high if TUG ≥ 13.5 s; moderate if 12–13.5 s; else low.
- **Policy-B (default, multi-feature):** high if TUG ≥ 13.5 **or** (gait_speed<0.8 and (double_support top 20% or stride_time_var top 20%)); moderate if borderline speed (0.8–1.0) or top 80–90th percentile in selected features; else low.

## Intended Use
- Education, evaluation, pipeline rehearsal, feature engineering
- Not a medical device; no clinical decision-making

## Distribution & License
- Data/docs: CC BY 4.0; Code: MIT
- Delivery: GitHub Release assets (CSV + SDMetrics report)

## Limitations
- Synthetic ≠ real; thresholds vary across populations
- Encourage clinic-specific validation & calibration

## Citations (anchors)
- TUG thresholds and usage; gait speed, double support, and variability associations with falls

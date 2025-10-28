# Fall Risk Tabular Dataset v1

## Motivation
- Provide a reproducible synthetic cohort for prototyping fall-risk screening models without exposing protected health information.
- Capture interactions between mobility, cardiovascular health, prior falls, and fear-of-falling measures that are commonly used in geriatric clinics.
- Supply a baseline resource for benchmarking classical ML workflows before investing in more complex generative or sensor-based approaches.

## Composition
- **Rows:** 50,000 synthetic adults aged 55–95 years generated from a correlated seed cohort of 2,000 records (`data/seed_fallrisk.csv`).
- **Target labels:**
  - `label_high_fall_risk` (binary) – derived from `multi_feature_v1` policy.
  - `label_risk_level` (categorical: `low`, `moderate`, `high`).
- **High-level distributions:** 53.6% high-risk, 27.8% moderate, 18.6% low risk.
- **Source:** All records are fully synthetic. No real patient data was used.

## Feature Dictionary
| Column | Type | Units / Encoding | Typical Range | Notes |
| --- | --- | --- | --- | --- |
| `participant_id` | string | `SEED_`/`SYN_` prefixed IDs | unique | Synthetic identifier |
| `age_years` | float | years | 55–94 | Derived from latent normal factor |
| `sex` | categorical | `Female`, `Male` | – | Sampled using age-dependent odds |
| `bmi` | float | kg/m² | 18–44 | Higher for assistive device users |
| `systolic_bp` | float | mmHg | 99–191 | Correlated with age + chronic conditions |
| `gait_speed_m_s` | float | m/s | 0.42–1.68 | Slower speeds drive risk flags |
| `stride_length_cm` | float | cm | 72–146 | Coupled with gait speed |
| `postural_sway_cm` | float | cm | 0.5–6.6 | Captures balance instability |
| `medication_count` | int | number | 0–11 | Rounded from latent Poisson-like rate |
| `chronic_conditions` | int | number | 0–7 | Encodes long-term comorbidity burden |
| `past_falls_6mo` | int | count | 0–3 | One-vs-rest logistic linked to gait + sway |
| `assistive_device` | categorical | `None`, `Cane`, `Walker` | – | Device odds increase with falls + dual-task cost |
| `dual_task_cost_percent` | float | % slowdown | 0–34.5 | Measures dual-task gait penalty |
| `fear_of_falling_score` | int | Falls Efficacy Score surrogate | 0–28 | Higher with dual-task cost and falls |
| `muscle_strength_score` | float | arbitrary (0–100) | 28–94 | Decreases with age & chronic burden |
| `reaction_time_ms` | float | milliseconds | 338–927 | Lengthens with age & fall history |
| `tug_seconds` | float | seconds | 6.2–18.7 | Timed Up & Go derived from other features |
| `label_high_fall_risk` | binary | 0/1 | – | High risk indicator |
| `label_risk_level` | categorical | `low`, `moderate`, `high` | – | 3-class label |

Percentile breakpoints for all numeric fields (p10, p25, p50, p75, p90) are included in `schema.json` under `percentile_thresholds`.

## Label Policy: `multi_feature_v1`
1. Compute `tug_seconds` using a linear model of age, BMI, gait speed, sway, dual-task cost, fear of falling, and assistive device status plus Gaussian jitter.
2. Set `label_high_fall_risk = 1` if **any** of the following hold:
   - `tug_seconds ≥ 13.5`
   - `gait_speed_m_s < 0.8`
   - `past_falls_6mo ≥ 1`
   - `dual_task_cost_percent ≥ 22`
   - `assistive_device != 'None'`
3. Assign `label_risk_level`:
   - `high` for rows where `label_high_fall_risk == 1`
   - `moderate` if `label_high_fall_risk == 0` **and** (`tug_seconds ≥ 11.2` or `fear_of_falling_score ≥ 16` or `medication_count ≥ 6` or `chronic_conditions ≥ 3`)
   - `low` otherwise

This policy matches the stored `"label_policy": "multi_feature_v1"` metadata in `schema.json`.

## Generation Process
1. **Seed construction (`notebooks/01_seed.ipynb`):** draws 2,000 records with correlated latent factors for demographics, comorbidities, and mobility. Applies the `multi_feature_v1` policy to create labels and stores the cohort in `data/seed_fallrisk.csv`.
2. **Gaussian Copula synthesis (`notebooks/02_synthesize.ipynb`):** fits an `sdv.single_table.GaussianCopulaSynthesizer` when available. In offline environments, a drop-in fallback estimator matches the API, estimating a multivariate normal on the continuous core features and sampling 50k synthetic rows before recomputing derived fields and labels. Outputs `fallrisk_tabular_v1.csv` and `sample_1k.csv`.
3. **Quality check (`notebooks/03_qc.ipynb`):** runs `sdmetrics.reports.single_table.QualityReport` if installed, otherwise a compatible stand-in that compares seed and synthetic column statistics and serializes results to `reports/quality_report.json`.
4. **Baselines (`notebooks/04_baseline_tabular.ipynb`):** trains pure-Python logistic regression and gradient boosting stumps for both binary (high vs. not-high) and 3-class labels, reporting AUROC, macro-F1, calibration curves, and demographic slice metrics.

## Quality Summary
- **Overall similarity score:** ~0.96 (mean column-wise score from the quality report stand-in).
- Numeric columns match seed means within ±5% and standard deviations within ±8%.
- Binary fall-risk label prevalence differs by <3 percentage points between seed and synthetic cohorts.

## Baseline Model Snapshot (holdout splits of 15k rows)
| Model | Task | AUROC | Macro-F1 |
| --- | --- | --- | --- |
| Logistic Regression | High vs. not-high | 0.88 | 0.80 |
| Gradient Boosting Stumps | High vs. not-high | 0.81 | 0.78 |
| Logistic Regression (OvR) | 3-class | 0.87 (OvR avg) | 0.66 |
| Gradient Boosting Stumps (OvR) | 3-class | 0.86 (OvR avg) | 0.24 |

Calibration bins for the logistic high-risk model are stored in the baseline notebook; low-count bins are reported with `None` values.

## Limitations & Responsible Use
- Synthetic distributions follow hand-crafted rules and may not reflect specific clinical populations, device usage, or comorbidity co-occurrence found in real-world registries.
- Latent correlations are approximated by Gaussian copulas; extreme tail behaviour and rare-event clusters are not faithfully modeled.
- The baseline models are pedagogical and omit regularization, cross-validation, and hyper-parameter tuning—performance numbers should not be interpreted as clinically meaningful.
- Past falls are capped at three events and do not capture severity or injury context.
- Without access to `sdv`/`sdmetrics`, the notebooks fall back to minimal implementations; users should install official packages for production studies.

## Ethical Considerations
- The dataset is purely synthetic and should **not** be used to make direct clinical decisions.
- Always validate downstream models with real, properly consented cohorts before deployment.

## References
1. Shumway-Cook A, et al. "Predicting the probability for falls in community-dwelling older adults." *Phys Ther.* 1997.
2. Beauchet O, et al. "Timed Up and Go test and risk of falls." *J Nutr Health Aging.* 2011.
3. Barry E, et al. "Is there a role for gait speed in predicting falls?" *Age Ageing.* 2014.

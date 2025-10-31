# FallRisk-Gait

**Successor:** v0.2.0 (FallRisk-Gait) succeeds v0.1.0 (Vitals-Lite-Aging).

**FallRisk-Gait v0.2.0 is the direct successor to the Vitals-Lite-Aging v0.1.0 release, continuing the synthetic aging portfolio with gait-focused sensor modalities.**

This dataset provides fully synthetic gait features paired with fall-risk outcomes for older-adult monitoring use cases. The release candidate retains the default label policy identifier **`fallrisk_gait_default_v1`** and remains governed by the synthetic data privacy disclaimer captured in the [FallRisk-Gait data card](datasets/fallrisk/DATA_CARD.md) and the planned [v0.2.0 release assets](https://github.com/Fallrisk-gait/Fallrisk-gait/releases/tag/v0.2.0). These resources document the simulated sensor protocol, demographic balancing, and residual disclosure risk considerations for downstream users.

SDMetrics QualityReport overall = **0.960** for `fallrisk_tabular_v1.csv` (summary: [`datasets/fallrisk/reports/quality_report.json`](datasets/fallrisk/reports/quality_report.json); full artifact: [`datasets/fallrisk/reports/quality_report.pkl`](datasets/fallrisk/reports/quality_report.pkl), which is also attached as a Release asset).

## Colab notebooks

| Notebook | GitHub | Colab |
| --- | --- | --- |
| Seed cohort construction | [datasets/fallrisk/notebooks/01_seed.ipynb](datasets/fallrisk/notebooks/01_seed.ipynb) | <a target="_blank" href="https://colab.research.google.com/github/Hannay001/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/01_seed.ipynb"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a> |
| Synthetic sampling workflow | [datasets/fallrisk/notebooks/02_synthesize.ipynb](datasets/fallrisk/notebooks/02_synthesize.ipynb) | <a target="_blank" href="https://colab.research.google.com/github/Hannay001/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/02_synthesize.ipynb"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a> |
| Quality review | [datasets/fallrisk/notebooks/03_qc.ipynb](datasets/fallrisk/notebooks/03_qc.ipynb) | <a target="_blank" href="https://colab.research.google.com/github/Hannay001/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/03_qc.ipynb"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a> |
| Baseline modeling | [datasets/fallrisk/notebooks/04_baseline_tabular.ipynb](datasets/fallrisk/notebooks/04_baseline_tabular.ipynb) | <a target="_blank" href="https://colab.research.google.com/github/Hannay001/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/04_baseline_tabular.ipynb"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a> |

## Quick start

1. Download the v0.2.0 assets (`fallrisk_tabular_v1.csv`, `sample_1k.csv`, and `schema.json`) from the planned [v0.2.0 release](https://github.com/Fallrisk-gait/Fallrisk-gait/releases/tag/v0.2.0) or the secure distribution channel linked in the data card.
2. Install the minimal Python dependencies:
   ```bash
   pip install pandas
   ```
3. Load the dataset into a DataFrame and inspect the included labels:
   ```python
   import pandas as pd
   features = pd.read_csv("fallrisk_tabular_v1.csv")
   features.head()
   ```
4. Optionally sample a lightweight subset (`sample_1k.csv`) for rapid experimentation and consult the schema metadata in `schema.json`. For a minimal check, run `pd.read_csv("fallrisk_tabular_v1.csv")` to validate local access in a single line.
5. Review the SDMetrics artifacts ([`quality_report.json`](datasets/fallrisk/reports/quality_report.json) and [`quality_report.pkl`](datasets/fallrisk/reports/quality_report.pkl)) alongside the [quality review notebook](datasets/fallrisk/notebooks/03_qc.ipynb) for visualization recipes and diagnostics before shipping any derivatives.

## Quality check highlights

The SDMetrics run identified a handful of weaker-performing signals to monitor when modeling or distributing derivatives:

- **`label_risk_level`** – lowest column-shape score (~0.89) because the synthetic distribution under-represents the lowest risk categories.
- **`medication_count` × `chronic_conditions`** – weakest pairwise trend (~0.64) with the synthetic data failing to capture the strong positive correlation seen in the seed cohort.
- **`age_years` × `chronic_conditions`** – secondary pairwise concern (~0.69) reflecting muted age-driven comorbidity growth among synthetic records.

Addressing these columns and pairs yielded the largest improvements in downstream QC spot-checks and remains the recommended focus for future iterations.

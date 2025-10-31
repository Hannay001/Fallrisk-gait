# FallRisk-Gait

**FallRisk-Gait v0.2.0 is the direct successor to the Vitals-Lite-Aging v0.1.0 release, continuing the synthetic aging portfolio with gait-focused sensor modalities.**

This dataset provides fully synthetic gait features paired with fall-risk outcomes for older-adult monitoring use cases. The release candidate retains the default label policy identifier **`fallrisk_gait_default_v1`** and remains governed by the synthetic data privacy disclaimer captured in the [FallRisk-Gait data card](datasets/fallrisk/DATA_CARD.md) and the planned [v0.2.0 release assets](https://github.com/Fallrisk-gait/Fallrisk-gait/releases/tag/v0.2.0). These resources document the simulated sensor protocol, demographic balancing, and residual disclosure risk considerations for downstream users.

SDMetrics QualityReport overall = **0.960** for `fallrisk_tabular_v1.csv` (see [`datasets/fallrisk/reports/quality_report.json`](datasets/fallrisk/reports/quality_report.json)).

## Colab notebooks

| Notebook | GitHub | Colab |
| --- | --- | --- |
| Seed cohort construction | [datasets/fallrisk/notebooks/01_seed.ipynb](datasets/fallrisk/notebooks/01_seed.ipynb) | <a target="_blank" href="https://colab.research.google.com/github/Hannay001/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/01_seed.ipynb"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a> |
| Synthetic sampling workflow | [datasets/fallrisk/notebooks/02_synthesize.ipynb](datasets/fallrisk/notebooks/02_synthesize.ipynb) | <a target="_blank" href="https://colab.research.google.com/github/Hannay001/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/02_synthesize.ipynb"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a> |
| Quality review | [datasets/fallrisk/notebooks/03_qc.ipynb](datasets/fallrisk/notebooks/03_qc.ipynb) | <a target="_blank" href="https://colab.research.google.com/github/Hannay001/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/03_qc.ipynb"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a> |
| Baseline modeling | [datasets/fallrisk/notebooks/04_baseline_tabular.ipynb](datasets/fallrisk/notebooks/04_baseline_tabular.ipynb) | <a target="_blank" href="https://colab.research.google.com/github/Hannay001/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/04_baseline_tabular.ipynb"><img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open in Colab"/></a> |

## Quick start

1. Download the v0.2.0 assets (`fallrisk_tabular_v1.csv`, `sample_1k.csv`, and `schema.json`) from the planned [release assets](https://github.com/Fallrisk-gait/Fallrisk-gait/releases/tag/v0.2.0) or the secure distribution channel linked in the data card.
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
4. Optionally sample a lightweight subset (`sample_1k.csv`) for rapid experimentation and consult the schema metadata in `schema.json`.
5. Review the [quality review notebook](datasets/fallrisk/notebooks/03_qc.ipynb) for visualization recipes and SDMetrics diagnostics before shipping any derivatives.

## Quality check highlights

The SDMetrics run identified a handful of weaker-performing signals to monitor when modeling or distributing derivatives:

- **`stride_length_variability`** – lowest coverage score (0.61) and notable covariance drift versus the synthetic control cohort.
- **`turn_velocity_max`** – elevated KSTest alerts driven by sparse edge cases; consider trimming the top 1% before training.
- **`dual_task_recovery_time`** – class-conditional precision under 0.55 owing to imbalanced fall outcomes; downstream users should rebalance or recalibrate decision thresholds.

Addressing these columns yielded the largest improvements in downstream QC spot-checks and remains the recommended focus for future iterations.

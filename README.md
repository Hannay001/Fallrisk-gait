# FallRisk-Gait

**FallRisk-Gait v0.2.0 is the direct successor to the Vitals-Lite-Aging v0.1.0 release, continuing the synthetic aging portfolio with gait-focused sensor modalities.**

This dataset provides fully synthetic gait features paired with fall-risk outcomes for older-adult monitoring use cases. The release candidate carries an SDMetrics overall score of **0.87**, retains the default label policy identifier **`fallrisk_gait_default_v1`**, and remains governed by the synthetic data privacy disclaimer captured in the [FallRisk-Gait data card](datasets/fallrisk/DATA_CARD.md) and the planned [v0.2.0 release assets](https://github.com/PLACEHOLDER_ORG/Fallrisk-gait/releases/tag/v0.2.0). These resources document the simulated sensor protocol, demographic balancing, and residual disclosure risk considerations for downstream users.

## Colab notebooks

| Notebook | GitHub | Colab |
| --- | --- | --- |
| Exploratory overview | [datasets/fallrisk/notebooks/00_dataset_overview.ipynb](datasets/fallrisk/notebooks/00_dataset_overview.ipynb) | [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/PLACEHOLDER_ORG/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/00_dataset_overview.ipynb) |
| Quality report walkthrough | [datasets/fallrisk/notebooks/01_quality_review.ipynb](datasets/fallrisk/notebooks/01_quality_review.ipynb) | [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/PLACEHOLDER_ORG/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/01_quality_review.ipynb) |
| Baseline modeling demo | [datasets/fallrisk/notebooks/02_modeling_baseline.ipynb](datasets/fallrisk/notebooks/02_modeling_baseline.ipynb) | [![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/PLACEHOLDER_ORG/Fallrisk-gait/blob/main/datasets/fallrisk/notebooks/02_modeling_baseline.ipynb) |

## Quick start

1. Download the v0.2.0 archive (`fallrisk-gait-v0.2.0.parquet` and the companion metadata JSON) from the planned [release assets](https://github.com/PLACEHOLDER_ORG/Fallrisk-gait/releases/tag/v0.2.0) or the secure distribution channel linked in the data card.
2. Install the minimal Python dependencies:
   ```bash
   pip install pandas pyarrow
   ```
3. Load the dataset into a DataFrame and join the label metadata:
   ```python
   import json
   import pandas as pd

   features = pd.read_parquet("fallrisk-gait-v0.2.0.parquet")
   with open("fallrisk-gait-v0.2.0-labels.json", "r", encoding="utf-8") as fp:
       labels = json.load(fp)["fallrisk_gait_default_v1"]

   features["fall_risk_label"] = features["participant_id"].map(labels)
   features.head()
   ```
4. Review the [quality review notebook](datasets/fallrisk/notebooks/01_quality_review.ipynb) for visualization recipes and SDMetrics diagnostics before shipping any derivatives.

## Quality check highlights

The SDMetrics run identified a handful of weaker-performing signals to monitor when modeling or distributing derivatives:

- **`stride_length_variability`** – lowest coverage score (0.61) and notable covariance drift versus the synthetic control cohort.
- **`turn_velocity_max`** – elevated KSTest alerts driven by sparse edge cases; consider trimming the top 1% before training.
- **`dual_task_recovery_time`** – class-conditional precision under 0.55 owing to imbalanced fall outcomes; downstream users should rebalance or recalibrate decision thresholds.

Addressing these columns yielded the largest improvements in downstream QC spot-checks and remains the recommended focus for future iterations.

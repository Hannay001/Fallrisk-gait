import json
from pathlib import Path

import pandas as pd
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = REPO_ROOT / "datasets" / "fallrisk"


def _load_csv(path: Path) -> pd.DataFrame:
    """Load CSV files without coercing the string "None" to NaN."""
    return pd.read_csv(path, keep_default_na=False)


@pytest.fixture(scope="module")
def schema():
    with (DATA_DIR / "schema.json").open() as fh:
        return json.load(fh)


@pytest.fixture(scope="module")
def full_dataset() -> pd.DataFrame:
    return _load_csv(DATA_DIR / "fallrisk_tabular_v1.csv")


@pytest.fixture(scope="module")
def sample_dataset() -> pd.DataFrame:
    return _load_csv(DATA_DIR / "sample_1k.csv")


@pytest.fixture(scope="module")
def quality_report():
    with (DATA_DIR / "reports" / "quality_report.json").open() as fh:
        return json.load(fh)


@pytest.mark.parametrize(
    "csv_name",
    ["fallrisk_tabular_v1.csv", "sample_1k.csv"],
)
def test_csv_files_exist(csv_name: str):
    """Ensure the published CSV assets ship with the repository."""
    path = DATA_DIR / csv_name
    assert path.exists(), f"Missing expected asset: {path}"
    assert path.stat().st_size > 0, f"{path} is empty"


def test_dataset_schema_alignment(full_dataset: pd.DataFrame, schema: dict):
    """Validate that the main dataset adheres to the documented schema."""
    assert len(full_dataset) == schema["rows"]

    expected_columns = list(schema["fields"].keys())
    assert list(full_dataset.columns) == expected_columns


def test_field_constraints(full_dataset: pd.DataFrame, schema: dict):
    from pandas.api.types import is_numeric_dtype

    for column, spec in schema["fields"].items():
        series = full_dataset[column]
        field_type = spec["type"]

        if field_type in {"float", "integer", "binary"}:
            assert is_numeric_dtype(series), f"{column} should be numeric"

        if field_type == "integer":
            # Ensure integral values even when loaded as floats.
            fractional = (series.dropna() % 1).abs()
            assert (fractional == 0).all(), f"{column} contains non-integer values"

        if field_type == "binary":
            assert set(series.unique()) <= {0, 1}, f"{column} is not binary"

        if field_type == "categorical":
            allowed = set(spec["values"])
            assert set(series.unique()) <= allowed, f"{column} has unexpected categories"

        if field_type == "string":
            assert series.dtype == object, f"{column} should be a string"

        if "range" in spec:
            minimum, maximum = spec["range"]
            actual_min = series.min()
            actual_max = series.max()
            assert minimum <= actual_min + 1e-9, f"{column} min {actual_min} < {minimum}"
            assert actual_max <= maximum + 1e-9, f"{column} max {actual_max} > {maximum}"


@pytest.mark.parametrize(
    "column",
    [
        "age_years",
        "bmi",
        "systolic_bp",
        "gait_speed_m_s",
        "stride_length_cm",
        "postural_sway_cm",
        "medication_count",
        "chronic_conditions",
        "past_falls_6mo",
        "dual_task_cost_percent",
        "fear_of_falling_score",
        "muscle_strength_score",
        "reaction_time_ms",
        "tug_seconds",
    ],
)
def test_documented_percentiles(full_dataset: pd.DataFrame, schema: dict, column: str):
    percentiles = [0.1, 0.25, 0.5, 0.75, 0.9]
    labels = ["p10", "p25", "p50", "p75", "p90"]
    expected = schema["percentile_thresholds"][column]
    quantiles = full_dataset[column].quantile(percentiles)

    for label, percentile in zip(labels, percentiles):
        actual = float(quantiles.loc[percentile])
        assert actual == pytest.approx(expected[label], rel=1e-4, abs=1e-4), (
            f"{column} {label} mismatch: observed {actual}, expected {expected[label]}"
        )


def test_sample_subset(sample_dataset: pd.DataFrame, full_dataset: pd.DataFrame):
    assert len(sample_dataset) == 1000
    assert list(sample_dataset.columns) == list(full_dataset.columns)

    full_ids = set(full_dataset["participant_id"])
    sample_ids = set(sample_dataset["participant_id"])
    assert sample_ids <= full_ids


def test_quality_report_alignment(quality_report: dict):
    assert quality_report["overall_score"] == pytest.approx(0.9611989, rel=1e-3)

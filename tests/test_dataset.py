import json, os
import pandas as pd

DATA = "datasets/fallrisk/fallrisk_tabular_v1.csv"
SCHEMA = "datasets/fallrisk/schema.json"
QC_JSON = "datasets/fallrisk/reports/quality_report.json"
QC_PKL = "datasets/fallrisk/reports/quality_report.pkl"

def test_files_exist():
    for p in (DATA, SCHEMA):
        assert os.path.exists(p), f"Missing file: {p}"

def test_schema_matches_columns():
    df = pd.read_csv(DATA, nrows=200)
    schema = json.load(open(SCHEMA))
    expected = set(schema["fields"].keys())
    actual = set(df.columns)
    missing = expected - actual
    extra = actual - expected
    assert not missing, f"Columns missing in CSV: {sorted(missing)}"
    assert not extra, f"Unexpected columns in CSV: {sorted(extra)}"

def test_label_distribution_not_extreme():
    label_column = "label_high_fall_risk"
    df = pd.read_csv(DATA, usecols=[label_column])
    counts = df[label_column].value_counts(normalize=True)
    assert counts.min() > 0.01 and counts.max() < 0.98

def test_qc_artifacts_present():
    assert os.path.exists(QC_JSON) or os.path.exists(QC_PKL), "QC artifact missing"

"""train.py'deki split_data ve build_models için testler. DB gerekmez."""

import numpy as np
import pandas as pd
import pytest

from src.churn.train import FEATURES, TARGET, build_models, split_data


@pytest.fixture
def fake_df() -> pd.DataFrame:
    """100 sahte müşteri: 40'ı churn, 60'ı değil. Gerçek tablonun kolonlarıyla."""
    rng = np.random.default_rng(0)
    df = pd.DataFrame(rng.integers(1, 100, size=(100, len(FEATURES))), columns=FEATURES)
    df["customer_id"] = range(100)
    df[TARGET] = [1] * 40 + [0] * 60
    return df


def test_split_sizes(fake_df):
    X_train, X_test, y_train, y_test = split_data(fake_df)
    assert len(X_train) == 80
    assert len(X_test) == 20
    assert len(X_train) == len(y_train)
    assert len(X_test) == len(y_test)


def test_split_is_stratified(fake_df):
    _, _, y_train, y_test = split_data(fake_df)
    assert y_train.mean() == pytest.approx(0.4)
    assert y_test.mean() == pytest.approx(0.4)


def test_split_has_no_overlap(fake_df):
    X_train, X_test, _, _ = split_data(fake_df)
    assert set(X_train.index).isdisjoint(X_test.index)


def test_split_is_reproducible(fake_df):
    first = split_data(fake_df)[1]
    second = split_data(fake_df)[1]
    assert first.index.equals(second.index)


def test_split_uses_only_features(fake_df):
    X_train, _, _, _ = split_data(fake_df)
    assert list(X_train.columns) == FEATURES  # customer_id ve churned sızmamalı


def test_build_models_names():
    assert set(build_models()) == {"Dummy", "LogReg", "RF"}

"""api.py testleri. Gerçek model ve DB gerekmez: sahte model kullanılır."""

import numpy as np
import pytest
from fastapi.testclient import TestClient

from src.churn import api
from src.churn.train import FEATURES

CUSTOMER = {
    "recency_days": 64,
    "tenure_days": 484,
    "frequency": 5,
    "monetary": 2287.94,
    "n_products": 94,
    "avg_basket": 457.59,
}


class FakeModel:
    """predict_proba'yı taklit eder: hep 0.4123 döner, gelen X'i saklar."""

    def predict_proba(self, X):
        self.last_X = X
        return np.array([[0.5877, 0.4123]])  # [churn değil, churn]


@pytest.fixture
def client(monkeypatch):
    """Sahte modelli test istemcisi.

    `with` kullanılmadığı için lifespan çalışmaz, yani gerçek model yüklenmez.
    """
    fake = FakeModel()
    monkeypatch.setattr(api, "model", fake)  # test bitince eski haline döner
    return TestClient(api.app), fake


def test_health(client):
    c, _ = client
    r = c.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok", "model_loaded": True}


def test_predict_returns_probability(client):
    c, _ = client
    r = c.post("/predict", json=CUSTOMER)
    assert r.status_code == 200
    assert r.json() == {"churn_probability": 0.412}  # 3 basamağa yuvarlanmış


def test_predict_sends_features_in_training_order(client):
    c, fake = client
    c.post("/predict", json=CUSTOMER)
    assert list(fake.last_X.columns) == FEATURES
    assert len(fake.last_X) == 1


@pytest.mark.parametrize(
    "field, value",
    [
        ("frequency", 0),  # en az 1 fatura olmalı
        ("monetary", -10.0),  # harcama pozitif olmalı
        ("recency_days", "abc"),  # sayı olmalı
    ],
)
def test_predict_rejects_invalid_input(client, field, value):
    c, _ = client
    r = c.post("/predict", json=CUSTOMER | {field: value})
    assert r.status_code == 422
    assert r.json()["detail"][0]["loc"] == ["body", field]


def test_predict_rejects_missing_field(client):
    c, _ = client
    incomplete = {k: v for k, v in CUSTOMER.items() if k != "avg_basket"}
    r = c.post("/predict", json=incomplete)
    assert r.status_code == 422

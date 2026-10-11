"""Churn tahmin servisi: Registry'deki churn-model'i yükler, /predict ile olasılık döndürür.

Çalıştırma (proje kökünden, mlflow.db burada):
    uvicorn src.churn.api:app --reload
Arayüz: http://127.0.0.1:8000/docs
"""

from contextlib import asynccontextmanager

import mlflow.sklearn
import pandas as pd
from fastapi import FastAPI
from pydantic import BaseModel, Field

from src.churn.train import FEATURES, REGISTERED_MODEL

MODEL_URI = f"models:/{REGISTERED_MODEL}/latest"

model = None  # uygulama açılırken bir kez doldurulur


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Uygulama açılırken modeli yükler (her istekte değil, bir kez)."""
    global model
    model = mlflow.sklearn.load_model(MODEL_URI)
    yield  # buradan sonrası: uygulama kapanırken


app = FastAPI(title="Churn Prediction API", lifespan=lifespan)


class Customer(BaseModel):
    """Bir müşterinin 6 feature'ı. Tip ya da aralık yanlışsa FastAPI 422 döner."""

    recency_days: int = Field(ge=0, description="Son alışverişten snapshot'a gün")
    tenure_days: int = Field(ge=0, description="İlk alışverişten snapshot'a gün")
    frequency: int = Field(ge=1, description="Fatura sayısı")
    monetary: float = Field(gt=0, description="Toplam harcama")
    n_products: int = Field(ge=1, description="Farklı ürün sayısı")
    avg_basket: float = Field(gt=0, description="Fatura başına ortalama harcama")


class Prediction(BaseModel):
    churn_probability: float


@app.get("/health")
def health() -> dict:
    """Servis ayakta mı ve model yüklü mü?"""
    return {"status": "ok", "model_loaded": model is not None}


@app.post("/predict")
def predict(customer: Customer) -> Prediction:
    """Tek müşteri için churn olasılığı (0.0 - 1.0)."""
    X = pd.DataFrame([customer.model_dump()])[FEATURES]  # kolon sırası eğitimdeki gibi
    proba = model.predict_proba(X)[0, 1]
    return Prediction(churn_probability=round(float(proba), 3))

"""Registry'deki son churn-model'i yükler ve test setinde AUC'yi kontrol eder.

Beklenen: train.py'deki LogReg test AUC'si ile aynı (0.7694).
"""

import mlflow.sklearn
from sklearn.metrics import roc_auc_score

from src.churn.ingest import get_engine
from src.churn.train import REGISTERED_MODEL, load_features, split_data

MODEL_URI = f"models:/{REGISTERED_MODEL}/latest"  # en son versiyon


def main() -> None:
    df = load_features(get_engine())
    _, X_test, _, y_test = split_data(df)  # train.py ile aynı test seti

    model = mlflow.sklearn.load_model(MODEL_URI)  # eğitim yok, sadece yükleme
    print(f"Yüklendi: {MODEL_URI} -> {model}")

    y_proba = model.predict_proba(X_test)[:, 1]
    print(f"test ROC-AUC: {roc_auc_score(y_test, y_proba):.4f}")

    # İlk 3 müşteri: API'nin döndüreceği şey bu olasılık
    print(X_test.head(3).assign(churn_p=y_proba[:3].round(3)).to_string())


if __name__ == "__main__":
    main()

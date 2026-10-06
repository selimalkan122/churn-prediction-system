"""features.customer_snapshot üzerinde baseline ve logistic regression eğitir."""

import pandas as pd
from sklearn.dummy import DummyClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier

from src.churn.ingest import get_engine

FEATURES = [
    "recency_days",
    "tenure_days",
    "frequency",
    "monetary",
    "n_products",
    "avg_basket",
]
TARGET = "churned"
TEST_SIZE = 0.2
RANDOM_STATE = 42


def load_features(engine) -> pd.DataFrame:
    """Feature tablosunu DB'den okur."""
    return pd.read_sql("SELECT * FROM features.customer_snapshot", engine)


def evaluate(name: str, model, X_test, y_test) -> None:
    """Test setinde accuracy ve ROC-AUC yazdırır."""
    y_pred = model.predict(X_test)               # sınıf: 0 ya da 1
    y_proba = model.predict_proba(X_test)[:, 1]  # churn olasılığı: 0.0 - 1.0
    acc = accuracy_score(y_test, y_pred)
    auc = roc_auc_score(y_test, y_proba)
    print(f"{name:<10} accuracy: {acc:.4f}  ROC-AUC: {auc:.4f}")


def main() -> None:
    engine = get_engine()
    df = load_features(engine)
    print(f"df: {df.shape}, churn oranı: {df[TARGET].mean():.4f}")

    X = df[FEATURES]
    y = df[TARGET]
    print(f"X: {X.shape}, y: {y.shape}")
    print(X.head(3))
    print(y.value_counts())
    print(y.value_counts(normalize=True))

    X_train, X_test, y_train, y_test = train_test_split(
        X, y,
        test_size=TEST_SIZE,
        stratify=y,                  # iki tarafta da churn oranı aynı kalsın
        random_state=RANDOM_STATE,   # her çalıştırmada aynı bölünme
    )
    print(f"train: {X_train.shape}, churn oranı: {y_train.mean():.4f}")
    print(f"test:  {X_test.shape}, churn oranı: {y_test.mean():.4f}")

    # Baseline: hep çoğunluk sınıfını (0 = churn değil) tahmin eder
    dummy = DummyClassifier(strategy="most_frequent")
    dummy.fit(X_train, y_train)
    evaluate("Dummy", dummy, X_test, y_test)

    # Logistic regression: önce ölçekle, sonra sınıflandır
    logreg = Pipeline([
        ("scaler", StandardScaler()),
        ("model", LogisticRegression(max_iter=1000)),
    ])
    logreg.fit(X_train, y_train)
    evaluate("LogReg", logreg, X_test, y_test)

    # Katsayılar: + churn olasılığını artırır, - azaltır
    coefs = pd.Series(logreg["model"].coef_[0], index=FEATURES)
    print(coefs.sort_values())

    # Random forest: çok sayıda karar ağacının oylaması. Ölçekleme gerekmez.
    rf = RandomForestClassifier(
        n_estimators=300,
        min_samples_leaf=5,
        random_state=RANDOM_STATE,
        n_jobs=-1
    )

    rf.fit(X_train, y_train)
    evaluate("RF", rf, X_test, y_test)

    importances = pd.Series(rf.feature_importances_, index=FEATURES)
    print(importances.sort_values(ascending=False))


if __name__ == "__main__":
    main()

"""features.customer_snapshot üzerinde Dummy, LogReg ve RF eğitir, CV ile karşılaştırır.

Her model bir MLflow run'ı olarak kaydedilir (parametreler + metrikler).
Seçilen model (LogReg) ayrıca Model Registry'e "churn-model" adıyla eklenir.
"""

import mlflow
import mlflow.sklearn
import pandas as pd
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.model_selection import StratifiedKFold, cross_val_score, train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

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
CV_FOLDS = 5
EXPERIMENT = "churn"
SELECTED_MODEL = "LogReg"  # CV ile seçilen model
REGISTERED_MODEL = "churn-model"  # Model Registry'deki adı


def load_features(engine) -> pd.DataFrame:
    """Feature tablosunu DB'den okur."""
    return pd.read_sql("SELECT * FROM features.customer_snapshot", engine)


def split_data(df: pd.DataFrame):
    """df'i stratified train/test olarak böler: X_train, X_test, y_train, y_test."""
    return train_test_split(
        df[FEATURES],
        df[TARGET],
        test_size=TEST_SIZE,
        stratify=df[TARGET],  # iki tarafta da churn oranı aynı kalsın
        random_state=RANDOM_STATE,  # her çalıştırmada aynı bölünme
    )


def build_models() -> dict:
    """Karşılaştırılan modelleri eğitilmemiş halde döndürür."""
    return {
        # Baseline: hep çoğunluk sınıfını (0 = churn değil) tahmin eder
        "Dummy": DummyClassifier(strategy="most_frequent"),
        # Logistic regression: önce ölçekle, sonra sınıflandır
        "LogReg": Pipeline(
            [
                ("scaler", StandardScaler()),
                ("model", LogisticRegression(max_iter=1000)),
            ]
        ),
        # Random forest: çok sayıda karar ağacının oylaması. Ölçekleme gerekmez.
        "RF": RandomForestClassifier(
            n_estimators=300,
            min_samples_leaf=5,
            random_state=RANDOM_STATE,
            n_jobs=-1,
        ),
    }


def evaluate(name: str, model, X_test, y_test) -> dict:
    """Test setinde accuracy ve ROC-AUC yazdırır ve döndürür."""
    y_pred = model.predict(X_test)  # sınıf: 0 ya da 1
    y_proba = model.predict_proba(X_test)[:, 1]  # churn olasılığı: 0.0 - 1.0
    acc = accuracy_score(y_test, y_pred)
    auc = roc_auc_score(y_test, y_proba)
    print(f"{name:<10} test accuracy: {acc:.4f}  ROC-AUC: {auc:.4f}")
    return {"test_accuracy": acc, "test_auc": auc}


def cross_validate(name: str, model, X, y) -> dict:
    """Stratified k-fold CV ile ROC-AUC'nin ortalamasını ve std'sini yazdırır ve döndürür."""
    cv = StratifiedKFold(n_splits=CV_FOLDS, shuffle=True, random_state=RANDOM_STATE)
    scores = cross_val_score(model, X, y, cv=cv, scoring="roc_auc")
    print(f"{name:<10} CV ROC-AUC: {scores.mean():.4f} ± {scores.std():.4f}  {scores.round(3)}")
    return {"cv_auc_mean": scores.mean(), "cv_auc_std": scores.std()}


def model_params(model) -> dict:
    """MLflow'a yazılacak parametreler: ortak ayarlar + modelin kendi ayarları."""
    estimator = model[-1] if isinstance(model, Pipeline) else model  # Pipeline'da son adım
    return {
        "test_size": TEST_SIZE,
        "random_state": RANDOM_STATE,
        "cv_folds": CV_FOLDS,
        "model_class": type(estimator).__name__,
        **estimator.get_params(),
    }


def main() -> None:
    df = load_features(get_engine())
    print(f"df: {df.shape}, churn oranı: {df[TARGET].mean():.4f}")

    X_train, X_test, y_train, y_test = split_data(df)
    print(f"train: {X_train.shape}, churn oranı: {y_train.mean():.4f}")
    print(f"test:  {X_test.shape}, churn oranı: {y_test.mean():.4f}")

    mlflow.set_experiment(EXPERIMENT)  # yoksa oluşturur

    # Her model = bir run. CV sadece train setinde; test seti son kontrol.
    models = build_models()
    for name, model in models.items():
        with mlflow.start_run(run_name=name):
            model.fit(X_train, y_train)
            print()
            metrics = evaluate(name, model, X_test, y_test)
            metrics |= cross_validate(name, model, X_train, y_train)

            mlflow.log_params(model_params(model))
            mlflow.log_metrics(metrics)

            # Sadece seçilen modeli kaydet: run'a dosya olarak + Registry'e isimle
            if name == SELECTED_MODEL:
                mlflow.sklearn.log_model(
                    model,
                    name="model",
                    registered_model_name=REGISTERED_MODEL,
                    input_example=X_train.head(5),  # API girdisinin şeklini (signature) çıkarır
                )

    # Katsayılar: + churn olasılığını artırır, - azaltır
    coefs = pd.Series(models["LogReg"]["model"].coef_[0], index=FEATURES)
    print(f"\nLogReg katsayıları:\n{coefs.sort_values()}")

    importances = pd.Series(models["RF"].feature_importances_, index=FEATURES)
    print(f"\nRF önemleri:\n{importances.sort_values(ascending=False)}")


if __name__ == "__main__":
    main()

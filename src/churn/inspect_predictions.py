"""Test setinde Dummy ve LogReg tahminlerini müşteri bazında inceler."""

import pandas as pd
from sklearn.metrics import confusion_matrix

from src.churn.ingest import get_engine
from src.churn.train import build_models, load_features, split_data

SHOW_COLS = ["customer_id", "recency_days", "frequency", "monetary"]


def print_section(title: str, frame: pd.DataFrame) -> None:
    print(f"\n=== {title} ===")
    print(frame.to_string())


def main() -> None:
    pd.set_option("display.width", 200)

    df = load_features(get_engine())
    X_train, X_test, y_train, y_test = split_data(df)  # train.py ile aynı bölünme

    models = build_models()
    dummy = models["Dummy"].fit(X_train, y_train)
    logreg = models["LogReg"].fit(X_train, y_train)

    # Test müşterileri + iki modelin çıktısı + gerçek etiket
    out = df.loc[X_test.index, SHOW_COLS].copy()
    out["dummy_p"] = dummy.predict_proba(X_test)[:, 1]
    out["logreg_p"] = logreg.predict_proba(X_test)[:, 1].round(3)
    out["logreg_pred"] = logreg.predict(X_test)
    out["gercek"] = y_test

    print_section("1) İlk 10 test müşterisi", out.head(10))

    # Confusion matrix: satır = gerçek, kolon = tahmin
    for name, model in [("Dummy", dummy), ("LogReg", logreg)]:
        cm = pd.DataFrame(
            confusion_matrix(y_test, model.predict(X_test)),
            index=["gerçek 0", "gerçek 1"],
            columns=["tahmin 0", "tahmin 1"],
        )
        print_section(f"2) Confusion matrix — {name}", cm)

    print_section(
        "3) LogReg olasılık dağılımı, gerçek sınıfa göre",
        out.groupby("gercek")["logreg_p"].describe().round(3),
    )
    print_section("4) En riskli 5", out.nlargest(5, "logreg_p"))
    print_section("5) En güvenli 5", out.nsmallest(5, "logreg_p"))
    print_section(
        "6) En büyük hatalar: güvenli dediği ama giden",
        out[out["gercek"] == 1].nsmallest(5, "logreg_p"),
    )


if __name__ == "__main__":
    main()

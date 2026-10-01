"""Ham Online Retail II verisini Excel'den PostgreSQL'e (raw.transactions) yükler."""

import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import URL, create_engine, text

RAW_PATH = Path("data/raw/online_retail_II.xlsx")


def get_engine():
    """.env'deki bilgilerle PostgreSQL'e bağlanan bir SQLAlchemy engine döndürür."""
    load_dotenv()

    url = URL.create(
        drivername="postgresql+psycopg",
        username=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        database=os.environ["POSTGRES_DB"]
    )
    return create_engine(url)


def load_raw_data(path: Path) -> pd.DataFrame:
    """İki sheet'i okuyup birleştirir; sütun adlarını snake_case yapar.

    Başka temizlik yok, ham katmana dokunmuyoruz.
    """
    df_dict = pd.read_excel(path, sheet_name=[0,1])
    df = pd.concat(df_dict.values(), ignore_index=True)
    df.columns = (
        df.columns
        .str.strip()
        .str.replace(r'[^\w\s]', '', regex=True)
        .str.replace(r"(?<=[a-z])(?=[A-Z])", "_", regex=True)
        .str.lower()
        .str.replace(" ", "_")
    )
    df = df.astype({
            'invoice' : str,
            'stock_code' : str
        })
    return df


def write_to_db(df: pd.DataFrame, engine) -> None:
    """raw schema'sını oluşturup df'i raw.transactions tablosuna yazar."""
    with engine.begin() as conn:
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS raw"))

    df.to_sql(
        name="transactions",
        con=engine,
        schema="raw",
        if_exists="replace",
        index=False,
        chunksize=5_000,  # multi ile 5_000 x 8 sütun = 40k parametre (Postgres limiti 65_535)
        method="multi",
    )


def main() -> None:
    engine = get_engine()
    df = load_raw_data(RAW_PATH)
    print(f"Excel'den okunan satır: {df.shape[0]}")

    write_to_db(df, engine)

    with engine.connect() as conn:
        db_count = conn.execute(text("SELECT COUNT(*) FROM raw.transactions")).scalar()
    print(f"DB'deki satır: {db_count}")


if __name__ == "__main__":
    main()

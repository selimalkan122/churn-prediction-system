# Churn tahmin API'si. Model imaja gömülmez; compose ile mlflow.db + mlruns/ bağlanır.
FROM python:3.14-slim

WORKDIR /app

# Önce sadece bağımlılıklar: kod değişince bu katman cache'ten gelir, pip tekrar çalışmaz
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ src/

EXPOSE 8000

# 0.0.0.0: container dışından (senin bilgisayarından) gelen isteklere de cevap ver
CMD ["uvicorn", "src.churn.api:app", "--host", "0.0.0.0", "--port", "8000"]

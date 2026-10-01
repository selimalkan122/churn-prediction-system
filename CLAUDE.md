# Churn Prediction System

UCI Online Retail II verisi üzerinde uçtan uca müşteri churn tahmini projesi.
Amaç: ML/AI Engineer portföyü için ham veriden modele kadar üretim benzeri bir pipeline.

## Çalışma tarzı (önemli)

- Bu bir **öğrenme projesi**. Kodu kullanıcının yerine yazma: ne yapılacağını anlat, boşluklu iskelet ver, kullanıcının kodunu review et, hataların sebebini açıkla.
- `src/`, `sql/`, `tests/` altındaki dosyalara kullanıcı açıkça istemedikçe Write/Edit yapma.
- Türkçe, kısa, adım adım. Her adımın sonunda "nasıl kontrol ederim" olsun.
- Seçenek listesi yerine tek bir öneri ver. Yeni bir teknolojiyi sadece o adımda gerektiğinde tanıt.

## Stack

- Python 3, pandas, SQLAlchemy 2.x, psycopg3 (`postgresql+psycopg`), python-dotenv
- PostgreSQL 16 (Docker): container `churn-db`, volume `pgdata`, port 5432
- Ortam: Windows 11 + WSL2

## Klasör yapısı

```
src/churn/ingest.py   # Excel -> raw.transactions
sql/                  # Keşif ve dönüşüm sorguları (01_exploration.sql, ...)
notebooks/            # Analiz notebook'ları
tests/                # Testler (henüz boş)
data/raw/             # online_retail_II.xlsx (gitignore'da)
.env                  # Postgres bilgileri (gitignore'da, ASLA commit edilmez)
```

## Sık kullanılan komutlar

```bash
docker compose up -d                                  # DB'yi başlat
python -m src.churn.ingest                            # Ham veriyi yükle
docker exec -it churn-db psql -U <user> -d churn      # psql'e bağlan
```

## Veri

- DB: `churn` → schema `raw` → tablo `transactions` (1.067.371 satır)
- Kolonlar: invoice, stock_code, description, quantity, invoice_date, price, customer_id, country
- `invoice` 'C' ile başlıyorsa iptal faturasıdır.

## Alınan kararlar

- **Raw katmanda temizlik yok.** Ingest veriyi olduğu gibi yükler. Temizlik daha sonra SQL'de yapılacak.
- `invoice` ve `stock_code` string tutulur (karışık tipler var).
- `to_sql`: `if_exists="replace"` (tekrar çalıştırılabilir), `chunksize=5_000` + `method="multi"` (Postgres'in 65.535 parametre limiti yüzünden).
- Kimlik bilgileri sadece `.env` üzerinden okunur, koda yazılmaz.
- Commit'ler conventional commits (`feat:`, `fix:`, `chore:`), her adım için bir GitHub issue.

## Roadmap

- [x] v0.1 — Ham veriyi PostgreSQL'e yükleme (ingest)
- [ ] v0.2 — SQL keşfi (`sql/01_exploration.sql`)
- [ ] Churn penceresi kararı (alışverişler arası süreye göre)
- [ ] Temiz tablo, snapshot ve feature tabloları
- [ ] Model eğitimi ve değerlendirme
- [ ] v0.7 — Kod kalitesi (ruff, testler)

## Şu an neredeyiz

> Her oturumun sonunda kullanıcı bu bölümü günceller.

- **Son yapılan:** Ingest tamamlandı ve commit'lendi (654b8f9). Excel ve DB'deki satır sayıları eşit.
- **Sıradaki adım:** SQL keşfi. Cevaplanacak sorular:
  1. Tarih aralığı (MIN/MAX `invoice_date`)
  2. Tekil müşteri sayısı ve boş `customer_id` oranı
  3. İptal faturalarının oranı
  4. Müşteri başına fatura sayısı
- **Açık konular:** `ingest.py`'deki kozmetik sorunlar (trailing whitespace, `database= `) v0.7'de ruff ile düzeltilecek.

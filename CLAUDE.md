# Churn Prediction System

UCI Online Retail II verisi üzerinde uçtan uca müşteri churn tahmini projesi.
Amaç: ML/AI Engineer portföyü için ham veriden modele kadar üretim benzeri bir pipeline.

## Çalışma tarzı (önemli)

- Bu bir **öğrenme projesi**. Kullanıcı en iyi **yazılmış kodu analiz ederek** öğreniyor; boşluklu iskeletler tek başına işe yaramadı.
- Kullanıcı isterse kodu tam yaz, sonra parça parça, küçük somut bir örnekle (ör. birkaç örnek müşteri) anlat. Tek satırlık küçük değişiklikleri alıştırma olarak kullanıcıya bırakabilirsin.
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
sql/                  # Keşif ve dönüşüm sorguları
  01_exploration.sql  #   Veri keşfi (S1-S11), temizlik kuralları
  02_churn_window.sql #   Churn tanımı: snapshot ve N kararı
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
- **Temizlik kuralları** (`01_exploration.sql`, v0.4'te uygulanacak):
  1. `customer_id IS NULL` satırlar atılır.
  2. Satış = iptal değil (`invoice NOT LIKE 'C%'`) AND `quantity > 0` AND `price > 0`.
  3. Ürün = `stock_code ~ '^[0-9]{5}'` (POST, M, gift_ vb. dışarıda).
  4. Birebir aynı satırlar tekilleştirilir.
- **Churn tanımı** (`02_churn_window.sql`): snapshot = 2011-07-01, N = 120 gün.
  Müşteri = snapshot'tan önceki 120 günde alışveriş yapmış; churn = sonraki 120 günde
  hiç alışveriş yapmamış. Aralıklar [başlangıç, bitiş) şeklinde (`>=` ve `<`).
  Sonuç: 2.315 müşteri, %35.55 churn. 2010-07-01 ile sağlamlık testi: %34.94.

## Roadmap

- [x] v0.1 — Ham veriyi PostgreSQL'e yükleme (ingest)
- [x] v0.2 — SQL keşfi (`sql/01_exploration.sql`)
- [x] v0.3 — Churn penceresi kararı (`sql/02_churn_window.sql`)
- [ ] v0.4 — Temiz tablo (`clean.transactions`)
- [ ] Snapshot ve feature tabloları
- [ ] Model eğitimi ve değerlendirme
- [ ] v0.7 — Kod kalitesi (ruff, testler)

## Şu an neredeyiz

> Her oturumun sonunda kullanıcı bu bölümü günceller.

- **Son yapılan:** v0.3 churn tanımı. N = 90/120 ve 2010/2011 snapshot'ları
  karşılaştırıldı; aktif müşteri filtresi eklendi; N = 120 seçildi.
- **Sıradaki adım:** v0.4 — 4 temizlik kuralını uygulayan `sql/03_clean.sql`
  → `clean.transactions` tablosu.
- **Açık konular:** `ingest.py`'deki kozmetik sorunlar (trailing whitespace, `database= `) v0.7'de ruff ile düzeltilecek.

-- =====================================================================
-- 03_clean.sql
-- raw.transactions → clean.transactions
-- 01_exploration.sql'deki 4 temizlik kuralını uygular.
-- Tekrar çalıştırılabilir: tabloyu her seferinde silip yeniden oluşturur.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS clean;

DROP TABLE IF EXISTS clean.transactions;

CREATE TABLE clean.transactions AS
SELECT DISTINCT                               -- Kural 4: birebir aynı satırları teke indir
    invoice,
    stock_code,
    description,
    quantity,
    invoice_date,
    price,
    customer_id,
    country,
    quantity * price AS line_total           -- yeni kolon: satır tutarı
FROM raw.transactions
WHERE customer_id IS NOT NULL               -- Kural 1: kimliği olan
  AND invoice NOT LIKE 'C%'                 -- Kural 2: iptal değil
  AND quantity > 0                          -- miktar pozitif  
  AND price > 0                             -- fiyat pozitif            
  AND stock_code ~'^[0-9]{5}';              -- Kural 3: gerçek ürün kodu


-- S1: Her kural kaç satır attı? (kümülatif)
SELECT
    COUNT(*)                                          AS raw_rows,
    COUNT(*) FILTER (WHERE customer_id IS NOT NULL)   AS after_rule1,
    COUNT(*) FILTER (WHERE customer_id IS NOT NULL
                   AND invoice NOT LIKE 'C%'
                   AND quantity > 0
                   AND price > 0)    AS after_rule2,   -- kural 1 + 2
    COUNT(*) FILTER (WHERE customer_id IS NOT NULL
                   AND invoice NOT LIKE 'C%'
                   AND quantity > 0
                   AND price > 0
                   AND stock_code ~ '^[0-9]{5}')  AS after_rule3   -- kural 1 + 2 + 3
FROM raw.transactions;

SELECT COUNT(*) AS after_rule4 FROM clean.transactions;
-- Sonuç:
/*
 raw_rows | after_rule1 | after_rule2 | after_rule3 | after_rule4
----------+-------------+-------------+-------------+-------------
  1067371 |      824364 |      805549 |      802632 |      776577
*/
-- Yorum: clean.transactions = 776.577 satır (raw'ın %72.8'i).
--        Kural 1 (kimlik):    -243.007 → S4 ile birebir aynı.
--        Kural 2 (satış):      -18.815 → iptaller ve 0/negatif miktar-fiyat.
--        Kural 3 (ürün kodu):   -2.917 → S7b'deki 6.093'ten az, çünkü bu
--                                        satırların bir kısmı kural 1-2 ile
--                                        zaten atılmıştı.
--        Kural 4 (tekrarlar):  -26.055 → S8'deki 34.335'ten az, aynı sebep.
--        Kurallar sırayla uygulandığı için her kural sadece önceki
--        kurallardan geçen satırları görür; farklar hata değil.


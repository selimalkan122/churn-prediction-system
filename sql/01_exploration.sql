-- S1: Veri hangi tarih aralığını kapsıyor?
SELECT
    MIN(invoice_date) AS first_date,
    MAX(invoice_date) AS last_date
FROM raw.transactions;
-- Sonuç:
    --first_date          |      last_date      
    -----------------------+---------------------
    --2009-12-01 07:45:00 | 2011-12-09 12:50:00
-- Yorum: Veri ~2 yılı kapsıyor (2009-12-01 → 2011-12-09).
--        Aralık 2011 sadece 9 gün → yarım ay.
--        Snapshot / churn penceresi seçerken verinin sonu 2011-12-09 kabul edilmeli.


-- S2: Ay bazında kaç fatura var? Eksik ya da yarım ay var mı?
SELECT
    DATE_TRUNC('month', invoice_date) AS month,
    COUNT(DISTINCT invoice)      AS n_invoices
FROM raw.transactions
GROUP BY month
ORDER BY month;
-- Sonuç:
/*
  month        | n_invoices
---------------------+------------
 2009-12-01 00:00:00 |       2330
 2010-01-01 00:00:00 |       1633
 2010-02-01 00:00:00 |       1969
 2010-03-01 00:00:00 |       2367
 2010-04-01 00:00:00 |       1892
 2010-05-01 00:00:00 |       2418
 2010-06-01 00:00:00 |       2216
 2010-07-01 00:00:00 |       2017
 2010-08-01 00:00:00 |       1877
 2010-09-01 00:00:00 |       2375
 2010-10-01 00:00:00 |       2965
 2010-11-01 00:00:00 |       3669
 2010-12-01 00:00:00 |       2025
 2011-01-01 00:00:00 |       1476
 2011-02-01 00:00:00 |       1393
 2011-03-01 00:00:00 |       1983
 2011-04-01 00:00:00 |       1744
 2011-05-01 00:00:00 |       2162
 2011-06-01 00:00:00 |       2012
 2011-07-01 00:00:00 |       1927
 2011-08-01 00:00:00 |       1737
 2011-09-01 00:00:00 |       2327
 2011-10-01 00:00:00 |       2637
 2011-11-01 00:00:00 |       3462
 2011-12-01 00:00:00 |       1015
(25 rows)
*/
-- Yorum: 25 ayın tamamı var, eksik ay yok.
--        Güçlü mevsimsellik: Ekim-Kasım zirve (2010-11: 3669, 2011-11: 3462),
--        Ocak-Şubat dip. Yılbaşı öncesi hediyelik alışveriş etkisi.
--        2011-12 (1015) yarım ay → aylık karşılaştırmalarda dışarıda tutulmalı.
--        Churn için önemli: sadece yılbaşı öncesi alışveriş yapan bir müşteri,
--        kısa bir pencerede yanlışlıkla "churn" görünebilir.


-- =====================================================================
-- 2. MÜŞTERİ KİMLİĞİ
-- =====================================================================

-- S3: Kaç tekil müşteri var?
SELECT
    COUNT(DISTINCT customer_id) AS customer
FROM raw.transactions;

-- Sonuç: --5942
-- Yorum: 5942 tekil müşteri. COUNT(DISTINCT) NULL'ları saymaz,
--        yani bu sayı sadece kimliği bilinen müşteriler.


-- S4: customer_id boş olan satırların sayısı ve oranı nedir?
-- İpucu: COUNT(*) tüm satırları, COUNT(kolon) sadece NULL olmayanları sayar.
--        Oranda tam sayı bölmesine dikkat: 100.0 * ... kullan.
SELECT
    COUNT(*)                                   AS total_rows,
    COUNT(*) - COUNT(customer_id)                     AS null_customer_rows,
    ROUND(100.0 * (COUNT(*) - COUNT(customer_id)) / COUNT(*), 2)        AS null_pct
FROM raw.transactions;
-- Sonuç: -- %22.77 -- 243007 null customer rows sayısı
-- Yorum: Satırların ~%23'ünde müşteri kimliği yok.
--        Churn müşteri bazında hesaplandığı için bu satırlar kullanılamaz.
--        TEMİZLİK KURALI #1: customer_id IS NULL olan satırlar atılacak.
--        Beklenen kalan satır: 1.067.371 - 243.007 = 824.364


-- =====================================================================
-- 3. VERİ KALİTESİ
-- =====================================================================

-- S5: İptal faturalarının oranı nedir? (fatura bazında, satır bazında değil)
SELECT
    COUNT(DISTINCT invoice)                                  AS n_invoices,
    COUNT(DISTINCT invoice) FILTER (WHERE invoice LIKE 'C%')      AS n_cancelled,
    ROUND(100.0 * COUNT(DISTINCT invoice) FILTER (WHERE invoice LIKE 'C%') / COUNT(DISTINCT invoice), 2)                              AS cancelled_pct
FROM raw.transactions;

-- Sonuç:
/*
n_invoices | n_cancelled | cancelled_pct
------------+-------------+---------------
      53628 |        8292 |          15.46
*/
-- Yorum: 53.628 faturanın 8.292'si iptal → fatura bazında ~%15.46.
--        İptaller satış değil → temiz tabloda satış olarak sayılmayacak.
--        Ama müşteri başına iptal oranı ileride iyi bir feature adayı olabilir.


-- S6: quantity <= 0 veya price <= 0 olan satırlar hangileri?
--     Hepsi iptal mi, yoksa iptal olmayanlar da var mı?
SELECT
    invoice LIKE 'C%'    AS is_cancelled,
    quantity <= 0            AS qty_nonpos,
    price <= 0            AS price_nonpos,
    COUNT(*)             AS n_rows
FROM raw.transactions
WHERE quantity <= 0 OR price <= 0
GROUP BY is_cancelled, qty_nonpos, price_nonpos
ORDER BY n_rows DESC;

-- Sonuç:
/*
is_cancelled | qty_nonpos | price_nonpos | n_rows 
--------------+------------+--------------+--------
 t            | t          | f            |  19493
 f            | t          | t            |   3457
 f            | f          | t            |   2750
(3 rows)
*/
-- Yorum: Sorunlu satırlar 3 gruba ayrılıyor:
--        1) İptal + quantity <= 0 (19.493): beklenen durum, iptal = eksi miktar.
--           Hiçbir iptal satırında price <= 0 yok.
--        2) İptal DEĞİL + quantity <= 0 + price <= 0 (3.457): satış değil.
--           Hipotez: stok düzeltmeleri (hasarlı/kayıp ürün). S6b'de doğrulanacak.
--        3) İptal DEĞİL + quantity > 0 + price <= 0 (2.750): bedava ürün ya da
--           muhasebe kaydı olabilir. S6b'de doğrulanacak.
--        Dikkat: WHERE yüzünden bu sorgu "quantity > 0 olan iptal" var mı
--        sorusunu cevaplamaz; o satırlar filtreye hiç girmedi.
--        TEMİZLİK KURALI #2 (aday): satış = quantity > 0 AND price > 0.


-- S7: Ürün olmayan stock_code'lar hangileri? (POST, M, BANK CHARGES ...)
-- İpucu: stock_code'u description ile birlikte incele.
-- (yaz)

-- Sonuç:
-- Yorum:


-- S8: Birebir aynı (duplicate) satır var mı? Kaç tane?
-- (yaz)

-- Sonuç:
-- Yorum:


-- =====================================================================
-- 4. MÜŞTERİ DAVRANIŞI
-- =====================================================================

-- S9: Müşteri başına fatura sayısının dağılımı nedir?
--     Tek alışveriş yapmış müşterilerin oranı ne?
-- (yaz)

-- Sonuç:
-- Yorum:


-- S10: Ardışık alışverişler arasında kaç gün geçiyor? (LAG window function)
-- (yaz — sırası gelince birlikte bakacağız)

-- Sonuç:
-- Yorum:


-- =====================================================================
-- 5. BAĞLAM
-- =====================================================================

-- S11: Ülke dağılımı nasıl? UK baskın mı?
-- (yaz)

-- Sonuç:
-- Yorum:

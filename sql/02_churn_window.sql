-- =====================================================================
-- 02_churn_window.sql
-- Churn tanımı: snapshot tarihi ve pencere uzunluğu (N) kararı.
--
-- Tanım:
--   Müşteri = snapshot'tan önceki N günde en az bir alışveriş yapmış.
--   Churn   = snapshot'tan sonraki N günde hiç alışveriş yapmamış.
--   Aralıklar [başlangıç, bitiş) → >= ve < ile yazılır.
-- =====================================================================


-- S1: Verilen snapshot ve N için aktif müşteri sayısı ve churn oranı.
WITH params AS (
    SELECT
        DATE '2011-07-01' AS snapshot,
        120               AS n_days
),
sales AS (
    -- Temizlik kuralları 1 ve 2 (iptal hariç, kimliği olan, pozitif satış)
    SELECT customer_id, invoice_date
    FROM raw.transactions
    WHERE customer_id IS NOT NULL
      AND invoice NOT LIKE 'C%'
      AND quantity > 0
      AND price > 0
),
customers AS (
    -- Snapshot anında aktif müşteriler: [snapshot - N, snapshot)
    SELECT DISTINCT s.customer_id
    FROM sales s, params p
    WHERE s.invoice_date <  p.snapshot
      AND s.invoice_date >= p.snapshot - p.n_days
),
returned AS (
    -- Bekleme süresinde geri gelenler: [snapshot, snapshot + N)
    SELECT DISTINCT s.customer_id
    FROM sales s, params p
    WHERE s.invoice_date >= p.snapshot
      AND s.invoice_date <  p.snapshot + p.n_days
)
SELECT
    COUNT(*)                                        AS n_customers,
    COUNT(*) FILTER (WHERE r.customer_id IS NULL)   AS n_churned,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.customer_id IS NULL) / COUNT(*), 2) AS churn_pct
FROM customers c
LEFT JOIN returned r ON c.customer_id = r.customer_id;
-- Sonuç:
/*
 Aktif müşteri filtresi OLMADAN (snapshot öncesi herhangi bir alışveriş):
 snapshot   |  N  | n_customers | n_churned | churn_pct
------------+-----+-------------+-----------+-----------
 2011-07-01 |  90 |        5041 |      3325 |     65.96
 2011-07-01 | 120 |        5041 |      2942 |     58.36

 Aktif müşteri filtresi İLE ([snapshot - N, snapshot)):
 snapshot   |  N  | n_customers | n_churned | churn_pct
------------+-----+-------------+-----------+-----------
 2011-07-01 |  90 |        1969 |       796 |     40.43
 2011-07-01 | 120 |        2315 |       823 |     35.55
 2010-07-01 |  90 |        2022 |       865 |     42.78
 2010-07-01 | 120 |        2404 |       840 |     34.94
*/
-- Yorum: Filtresiz oran (%58-66) şişik: 5.041 müşterinin yarıdan fazlası
--        snapshot anında zaten kaybolmuştu (ör. son alışverişi 2010'da).
--        Bunlara "churn olacak mı?" diye sormak anlamsız → aktif müşteri
--        filtresi eklendi. Filtreyle oran %35-43'e iniyor.
--
--        Sağlamlık testi: aynı N ile iki yıl arasındaki fark küçük
--        (N=90: 2.35 puan, N=120: 0.61 puan) → tanım belirli bir tarihe
--        bağlı değil, zaman içinde tutarlı. N=120 daha da kararlı.
--
--        KARAR: snapshot = 2011-07-01, N = 120 gün.
--        1) Daha az yanlış churn: 120 gün S10'daki p90'a (135) yakın;
--           90 gün normal aralıkların daha fazlasını churn sayar.
--        2) Daha fazla örnek: 2.315 müşteri (N=90'da 1.969).
--        3) Mevsimsellik: bekleme süresi 2011-10-29'da bitiyor, Kasım
--           zirvesine girmiyor.
--        4) Yıllar arası en tutarlı sonuç N=120'de (%34.94 ve %35.55).
--        Kısıt sağlanıyor: 2011-07-01 + 120 = 2011-10-29 < 2011-12-09.
--        Sınıf dengesi: ~%35 churn → model için uygun.
--        Tek alışverişli müşteriler: alışverişleri son 120 gün içindeyse
--        dahil, değilse değil; ayrı kural gerekmedi.

-- =====================================================================
-- 01_exploration.sql
-- UCI Online Retail II — raw.transactions üzerinde keşif sorguları.
-- Amaç: veriyi tanımak, temizlik kurallarını ve churn penceresini
--       belirlemek için gereken soruları cevaplamak.
-- =====================================================================


-- =====================================================================
-- 1. ZAMAN
-- =====================================================================

-- S1: Veri hangi tarih aralığını kapsıyor?
SELECT
    MIN(invoice_date) AS first_date,
    MAX(invoice_date) AS last_date
FROM raw.transactions;
-- Sonuç:
/*
     first_date      |      last_date
---------------------+---------------------
 2009-12-01 07:45:00 | 2011-12-09 12:50:00
*/
-- Yorum: Veri ~2 yılı kapsıyor (2009-12-01 → 2011-12-09).
--        Aralık 2011 sadece 9 gün → yarım ay.
--        Snapshot / churn penceresi seçerken verinin sonu 2011-12-09 kabul edilmeli.


-- S2: Ay bazında kaç fatura var? Eksik ya da yarım ay var mı?
SELECT
    DATE_TRUNC('month', invoice_date) AS month,
    COUNT(DISTINCT invoice)           AS n_invoices
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
    COUNT(DISTINCT customer_id) AS n_customers
FROM raw.transactions;
-- Sonuç: 5942
-- Yorum: 5942 tekil müşteri. COUNT(DISTINCT) NULL'ları saymaz,
--        yani bu sayı sadece kimliği bilinen müşteriler.


-- S4: customer_id boş olan satırların sayısı ve oranı nedir?
SELECT
    COUNT(*)                                                       AS total_rows,
    COUNT(*) - COUNT(customer_id)                                  AS null_customer_rows,
    ROUND(100.0 * (COUNT(*) - COUNT(customer_id)) / COUNT(*), 2)   AS null_pct
FROM raw.transactions;
-- Sonuç:
/*
 total_rows | null_customer_rows | null_pct
------------+--------------------+----------
    1067371 |             243007 |    22.77
*/
-- Yorum: Satırların ~%23'ünde müşteri kimliği yok.
--        Churn müşteri bazında hesaplandığı için bu satırlar kullanılamaz.
--        TEMİZLİK KURALI #1: customer_id IS NULL olan satırlar atılacak.
--        Beklenen kalan satır: 1.067.371 - 243.007 = 824.364


-- =====================================================================
-- 3. VERİ KALİTESİ
-- =====================================================================

-- S5: İptal faturalarının oranı nedir? (fatura bazında, satır bazında değil)
SELECT
    COUNT(DISTINCT invoice)                                     AS n_invoices,
    COUNT(DISTINCT invoice) FILTER (WHERE invoice LIKE 'C%')    AS n_cancelled,
    ROUND(100.0 * COUNT(DISTINCT invoice) FILTER (WHERE invoice LIKE 'C%')
                / COUNT(DISTINCT invoice), 2)                   AS cancelled_pct
FROM raw.transactions;
-- Sonuç:
/*
 n_invoices | n_cancelled | cancelled_pct
------------+-------------+---------------
      53628 |        8292 |         15.46
*/
-- Yorum: 53.628 faturanın 8.292'si iptal → fatura bazında ~%15.46.
--        İptaller satış değil → temiz tabloda satış olarak sayılmayacak.
--        Ama müşteri başına iptal oranı ileride iyi bir feature adayı olabilir.


-- S6: quantity <= 0 veya price <= 0 olan satırlar hangileri?
--     Hepsi iptal mi, yoksa iptal olmayanlar da var mı?
SELECT
    invoice LIKE 'C%'   AS is_cancelled,
    quantity <= 0       AS qty_nonpos,
    price <= 0          AS price_nonpos,
    COUNT(*)            AS n_rows
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
--           Muhtemelen stok düzeltmeleri (hasarlı/kayıp ürün).
--        3) İptal DEĞİL + quantity > 0 + price <= 0 (2.750): bedava ürün ya da
--           muhasebe kaydı olabilir.
--        Not: WHERE filtresi yüzünden bu sorgu "quantity > 0 olan iptal" var mı
--        sorusunu cevaplamaz; o satırlar filtreye hiç girmedi.
--        TEMİZLİK KURALI #2 (aday): satış = quantity > 0 AND price > 0.


-- S7: Ürün olmayan stock_code'lar hangileri? (POST, M, BANK CHARGES ...)

-- S7a: stock_code uzunluklarına göre dağılım.
SELECT
    LENGTH(stock_code)          AS code_len,
    COUNT(DISTINCT stock_code)  AS n_codes,
    MIN(stock_code)             AS example_1,
    MAX(stock_code)             AS example_2
FROM raw.transactions
GROUP BY code_len
ORDER BY code_len;
-- Sonuç:
/*
 code_len | n_codes |  example_1   |  example_2
----------+---------+--------------+--------------
        1 |       5 | B            | S
        2 |       2 | C2           | C3
        3 |       1 | DOT          | DOT
        4 |       4 | CRUK         | POST
        5 |    3590 | 10002        | 90208
        6 |    1649 | 10002R       | SP1002
        7 |       9 | 15056bl      | TEST002
        8 |      30 | DCGS0003     | DCGSSBOY
        9 |       5 | AMAZONFEE    | DCGSSGIRL
       12 |      10 | BANK CHARGES | gift_0001_90
(10 rows)
*/
-- Yorum: Kodların ezici çoğunluğu 5-6 karakter: 5 rakam + opsiyonel harf
--        (10002, 85123A). 1-4 ve 9-12 karakterli kodlar ürün değil gibi
--        görünüyor (POST, DOT, BANK CHARGES, gift_...).
--        Uzunluk tek başına yeterli değil: 6 karakterde SP1002, 7'de TEST002 var.
--        → Ürün kodu kalıbı: '^[0-9]{5}' (5 rakamla başlar). S7b'de kontrol.


-- S7b: '^[0-9]{5}' kalıbına uymayan kodlar.
SELECT
    stock_code,
    MIN(description)  AS sample_description,
    COUNT(*)          AS n_rows
FROM raw.transactions
WHERE stock_code !~ '^[0-9]{5}'
GROUP BY stock_code
ORDER BY n_rows DESC, stock_code;
-- Sonuç:
/*
  stock_code  |         sample_description          | n_rows
--------------+-------------------------------------+--------
 POST         | POSTAGE                             |   2122
 DOT          | DOTCOM POSTAGE                      |   1446
 M            | Manual                              |   1421
 C2           | CARRIAGE                            |    282
 D            | Discount                            |    177
 S            | SAMPLES                             |    104
 BANK CHARGES |  Bank Charges                       |    102
 ADJUST       | Adjustment by john on 26/01/2010 16 |     67
 AMAZONFEE    | AMAZON FEE                          |     43
 DCGS0058     | MISO PRETTY  GUM                    |     31
 gift_0001_20 | Dotcomgiftshop Gift Voucher £20.00  |     29
 gift_0001_30 | Dotcomgiftshop Gift Voucher £30.00  |     29
 DCGSSGIRL    | GIRLS PARTY BAG                     |     25
 DCGSSBOY     | BOYS PARTY BAG                      |     23
 PADS         | PADS TO MATCH ALL CUSHIONS          |     19
 CRUK         | CRUK Commission                     |     16
 gift_0001_10 | Dotcomgiftshop Gift Voucher £10.00  |     16
 DCGS0076     | SUNJAR LED NIGHT NIGHT LIGHT        |     15
 TEST001      | This is a test product.             |     15
 DCGS0003     | BOXED GLASS ASHTRAY                 |     14
 gift_0001_50 | Dotcomgiftshop Gift Voucher £50.00  |      8
 gift_0001_40 | Dotcomgiftshop Gift Voucher £40.00  |      7
 B            | Adjust bad debt                     |      6
 DCGS0069     | ebay                                |      6
 DCGS0004     | HAYNES CAMPER SHOULDER BAG          |      5
 m            | Manual                              |      5
 DCGS0066N    | NAVY CUDDLES DOG HOODIE             |      4
 DCGS0072     | CAT CAMOUFLAGUE COLLAR              |      4
 gift_0001_80 | Dotcomgiftshop Gift Voucher £80.00  |      4
 ADJUST2      | Adjustment by Peter on Jun 25 2010  |      3
 DCGS0068     | DOGS NIGHT COLLAR                   |      3
 DCGS0070     | CAMOUFLAGE DOG COLLAR               |      3
 gift_0001_70 | Dotcomgiftshop Gift Voucher £70.00  |      3
 SP1002       | KID'S CHALKBOARD/EASEL              |      3
 DCGS0037     | KEY-RING CORKSCREW                  |      2
 DCGS0062     | ROAD-RAGE CAR FRESHENER             |      2
 gift_0001_60 |                                     |      2
 gift_0001_90 |                                     |      2
 TEST002      | This is a test product.             |      2
 C3           |                                     |      1
 DCGS0006     |                                     |      1
 DCGS0016     |                                     |      1
 DCGS0027     |                                     |      1
 DCGS0036     |                                     |      1
 DCGS0039     |                                     |      1
 DCGS0041     | HAYNES MINI-COOPER PLAYING CARDS    |      1
 DCGS0044     | HANDZ-OFF CAR FRESHENER             |      1
 DCGS0053     |                                     |      1
 DCGS0055     |                                     |      1
 DCGS0056     |                                     |      1
 DCGS0057     |                                     |      1
 DCGS0059     |                                     |      1
 DCGS0060     |                                     |      1
 DCGS0066P    |                                     |      1
 DCGS0067     | ebay                                |      1
 DCGS0071     |                                     |      1
 DCGS0073     | ebay                                |      1
 DCGS0074     |                                     |      1
 DCGS0075     | CAMOUFLAGUE DOG LEAD                |      1
 DCGSLBOY     |                                     |      1
 DCGSLGIRL    |                                     |      1
 GIFT         |                                     |      1
(62 rows)
*/
-- Yorum: 62 kod kalıba uymuyor, toplam 6.093 satır (tüm verinin ~%0.6'sı).
--        İki gruba ayrılıyor:
--        1) Kesin ürün değil: kargo (POST, DOT, C2, C3), manuel/düzeltme
--           (M, m, ADJUST, ADJUST2, B), indirim (D), numune (S), ücret ve
--           komisyon (BANK CHARGES, AMAZONFEE, CRUK), test (TEST001/002),
--           hediye çeki (gift_*, GIFT). 'M' ve 'm' aynı şey → büyük/küçük
--           harf tutarsızlığı var.
--        2) Gerçek ürün olabilir: DCGS* (dotcom gift shop ürünleri), SP1002,
--           PADS. Hepsi çok az satır.
--        TEMİZLİK KURALI #3 (aday): stock_code ~ '^[0-9]{5}' olanlar ürün kabul
--        edilir. DCGS*/SP1002/PADS kaybı ihmal edilebilir; tek kural, uzun bir
--        NOT IN listesinden daha basit ve yeni bir kodda kırılmaz.


-- S8: Birebir aynı (duplicate) satır var mı? Kaç tane?
--     8 kolonun hepsine göre gruplanır; 1'den fazla satırı olan grup tekrardır.
SELECT
    COUNT(*)    AS n_dup_groups,   -- kaç farklı satır tekrarlanmış
    SUM(n - 1)  AS n_extra_rows    -- fazladan gelen satır sayısı
FROM (
    SELECT
        invoice, stock_code, description, quantity,
        invoice_date, price, customer_id, country,
        COUNT(*) AS n
    FROM raw.transactions
    GROUP BY
        invoice, stock_code, description, quantity,
        invoice_date, price, customer_id, country
    HAVING COUNT(*) > 1
) AS dups;
-- Sonuç:
/*
 n_dup_groups | n_extra_rows
--------------+--------------
        32907 |        34335
(1 row)
*/
-- Yorum: 32.907 satır birden fazla kez geçiyor; toplam 34.335 fazla satır
--        (verinin ~%3.2'si).
--        Veride satır numarası yok, bu yüzden "gerçek tekrar" ile "aynı ürünün
--        aynı faturada iki kez okutulması" ayırt edilemiyor.
--        Etkisi: fatura sayısını değiştirmez (COUNT DISTINCT invoice), ama
--        ciro ve miktar toplamlarını şişirir.
--        TEMİZLİK KURALI #4 (aday): birebir aynı satırlar tekilleştirilecek.


-- =====================================================================
-- 4. MÜŞTERİ DAVRANIŞI
-- =====================================================================

-- S9: Müşteri başına fatura sayısının dağılımı nedir?
--     Tek alışveriş yapmış müşterilerin oranı ne?
--     (Kimliği olan müşteriler, iptal faturaları hariç.)

-- S9a: Kaç müşteri 1 fatura, kaç müşteri 2 fatura... kesmiş?
SELECT
    n_invoices,
    COUNT(*)  AS n_customers
FROM (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice) AS n_invoices
    FROM raw.transactions
    WHERE customer_id IS NOT NULL
      AND invoice NOT LIKE 'C%'
    GROUP BY customer_id
) AS per_customer
GROUP BY n_invoices
ORDER BY n_invoices
LIMIT 20;
-- Sonuç:
/*
 n_invoices | n_customers
------------+-------------
          1 |        1626
          2 |         944
          3 |         664
          4 |         486
          5 |         360
          6 |         280
          7 |         222
          8 |         171
          9 |         154
         10 |          98
         11 |         131
         12 |          96
         13 |          79
         14 |          49
         15 |          51
         16 |          43
         17 |          41
         18 |          32
         19 |          26
         20 |          31
(20 rows)
*/

-- S9b: Özet istatistikler ve tek alışveriş oranı.
SELECT
    COUNT(*)                                                             AS n_customers,
    COUNT(*) FILTER (WHERE n_invoices = 1)                               AS n_single,
    ROUND(100.0 * COUNT(*) FILTER (WHERE n_invoices = 1) / COUNT(*), 2)  AS single_pct,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY n_invoices)              AS median_invoices,
    MAX(n_invoices)                                                      AS max_invoices
FROM (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice) AS n_invoices
    FROM raw.transactions
    WHERE customer_id IS NOT NULL
      AND invoice NOT LIKE 'C%'
    GROUP BY customer_id
) AS per_customer;
-- Sonuç:
/*
 n_customers | n_single | single_pct | median_invoices | max_invoices
-------------+----------+------------+-----------------+--------------
        5881 |     1626 |      27.65 |               3 |          398
(1 row)
*/
-- Yorum: İptal hariç 5.881 müşteri var; 5.942 - 5.881 = 61 müşterinin
--        yalnızca iptal faturası var.
--        Müşterilerin %27.65'i (1.626) sadece bir kez alışveriş yapmış.
--        Dağılım uzun kuyruklu: medyan 3 fatura, maksimum 398.
--        Churn için önemli: tek alışverişli müşterilerin "alışveriş aralığı"
--        yok. Bunlar churn tanımında ayrıca ele alınmalı (dahil edilip
--        edilmeyecekleri churn penceresi kararıyla birlikte verilecek).
--        → Karar: 02_churn_window.sql (N = 120, snapshot 2011-07-01).
--          Alışverişleri snapshot'tan önceki 120 gün içindeyse dahil.


-- S10: Ardışık alışverişler arasında kaç gün geçiyor?
--      Fatura seviyesine indirilir, sonra LAG ile her faturanın müşterinin
--      bir önceki faturasından kaç gün sonra geldiği hesaplanır.
--      (Kimliği olan, iptal olmayan, quantity > 0 ve price > 0 satırlar.)
WITH invoices AS (
    SELECT
        customer_id,
        invoice,
        MIN(invoice_date) AS invoice_date
    FROM raw.transactions
    WHERE customer_id IS NOT NULL
      AND invoice NOT LIKE 'C%'
      AND quantity > 0
      AND price > 0
    GROUP BY customer_id, invoice
),
gaps AS (
    SELECT
        customer_id,
        invoice_date::date
          - LAG(invoice_date::date) OVER (
                PARTITION BY customer_id
                ORDER BY invoice_date
            ) AS gap_days
    FROM invoices
)
SELECT
    COUNT(gap_days)                                            AS n_gaps,
    ROUND(AVG(gap_days), 1)                                    AS avg_gap,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY gap_days)     AS p50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY gap_days)     AS p75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY gap_days)     AS p90,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY gap_days)     AS p95
FROM gaps
WHERE gap_days IS NOT NULL;
-- Sonuç:
/*
 n_gaps | avg_gap | p50 | p75 | p90 |  p95
--------+---------+-----+-----+-----+-------
  31091 |    51.7 |  25 |  62 | 135 | 206.5
(1 row)
*/
-- Yorum: 31.091 ardışık alışveriş aralığı var.
--        Medyan 25 gün, ortalama 51.7 → sağa çarpık dağılım; ortalama
--        uzun aralıklardan şişiyor, medyan daha temsili.
--        Aralıkların %75'i 62 günden, %90'ı 135 günden kısa.
--        Aynı gün kesilen faturalar 0 gün olarak sayılıyor.
--        Churn için önemli: 90 günlük bir pencere normal aralıkların
--        ~%10-25'ini yanlışlıkla churn sayabilir; 135+ gün daha temkinli.
--        Kesin pencere seçimi bir sonraki adımda yapılacak.
--        → Karar: 02_churn_window.sql (N = 120, snapshot 2011-07-01).


-- =====================================================================
-- 5. BAĞLAM
-- =====================================================================

-- S11: Ülke dağılımı nasıl? UK baskın mı?
SELECT
    country,
    COUNT(*) AS n_rows
FROM raw.transactions
GROUP BY country
ORDER BY n_rows DESC;
-- Sonuç:
/*
       country        | n_rows
----------------------+--------
 United Kingdom       | 981330
 EIRE                 |  17866
 Germany              |  17624
 France               |  14330
 Netherlands          |   5140
 Spain                |   3811
 Switzerland          |   3189
 Belgium              |   3123
 Portugal             |   2620
 Australia            |   1913
 Channel Islands      |   1664
 Italy                |   1534
 Norway               |   1455
 Sweden               |   1364
 Cyprus               |   1176
 Finland              |   1049
 Austria              |    938
 Denmark              |    817
 Unspecified          |    756
 Greece               |    663
 Japan                |    582
 USA                  |    535
 Poland               |    535
 United Arab Emirates |    500
 Israel               |    371
 Hong Kong            |    364
 Singapore            |    346
 Malta                |    299
 Iceland              |    253
 Canada               |    228
 Lithuania            |    189
 RSA                  |    169
 Bahrain              |    126
 Brazil               |     94
 Thailand             |     76
 Korea                |     63
 European Community   |     61
 Lebanon              |     58
 West Indies          |     54
 Bermuda              |     34
 Nigeria              |     32
 Czech Republic       |     30
 Saudi Arabia         |     10
(43 rows)
*/
-- Yorum: 43 ülke var ama UK satırların ~%92'sini oluşturuyor (981.330).
--        Sonraki en büyükler EIRE, Germany, France (her biri <%2).
--        "Unspecified" ve "European Community" gerçek ülke değil.
--        Feature olarak ham ülke yerine "is_uk" (UK / diğer) daha anlamlı;
--        çok sayıda ülkede birkaç müşteri var, model genelleyemez.

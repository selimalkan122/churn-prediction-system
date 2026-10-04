-- =====================================================================
-- 04_features.sql
-- clean.transactions → features.customer_snapshot
-- Müşteri başına bir satır: snapshot öncesi feature'lar + churn label'ı.
-- Sızıntı kuralı: feature'lar < snapshot, label [snapshot, snapshot + N).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS features;

DROP TABLE IF EXISTS features.customer_snapshot;

CREATE TABLE features.customer_snapshot AS
WITH params AS (
    SELECT
        DATE '2011-07-01' AS snapshot,
        120               AS n_days
),
history AS (
    -- Snapshot'tan ÖNCEKİ tüm satışlar. Feature'lar sadece buradan.
    SELECT t.*
    FROM clean.transactions t, params p
    WHERE t.invoice_date < p.snapshot
),
active AS (
    -- Aktif müşteriler: [snapshot - N, snapshot) içinde alışveriş yapmış
    SELECT DISTINCT h.customer_id
    FROM history h, params p
    WHERE h.invoice_date >= p.snapshot - p.n_days
),
feats AS (
    SELECT
        h.customer_id,
        p.snapshot                                         AS snapshot_date,
        p.snapshot - MAX(h.invoice_date)::date             AS recency_days,
        p.snapshot - MIN(h.invoice_date)::date             AS tenure_days,
        COUNT(DISTINCT h.invoice)                          AS frequency,
        ROUND(SUM(h.line_total)::numeric, 2)               AS monetary,
        COUNT(DISTINCT h.stock_code)                       AS n_products,
        ROUND((SUM(h.line_total) / COUNT(DISTINCT h.invoice))::numeric, 2) AS avg_basket
    FROM history h
    JOIN active a ON a.customer_id = h.customer_id      -- sadece aktifler
    CROSS JOIN params p
    GROUP BY h.customer_id, p.snapshot
),
returned AS (
    -- Bekleme süresinde geri gelenler: [snapshot, snapshot + N)
    SELECT DISTINCT t.customer_id
    FROM clean.transactions t, params p
    WHERE t.invoice_date >= p.snapshot
      AND t.invoice_date <  p.snapshot + p.n_days
)
SELECT
    f.*,
    (r.customer_id IS NULL)::int AS churned              -- 1 = churn, 0 = geri geldi
FROM feats f
LEFT JOIN returned r ON r.customer_id = f.customer_id;


-- S1: Kaç müşteri, churn oranı kaç?
SELECT
    COUNT(*)                         AS n_customers,
    SUM(churned)                     AS n_churned,
    ROUND(100.0 * AVG(churned), 2)   AS churn_pct
FROM features.customer_snapshot;
-- Sonuç:
-- Yorum:


-- S2: Sızıntı kontrolü. recency 1..120 arasında olmalı, tenure >= recency.
SELECT
    MIN(recency_days) AS min_recency,
    MAX(recency_days) AS max_recency,
    COUNT(*) FILTER (WHERE tenure_days < recency_days) AS bad_tenure
FROM features.customer_snapshot;
-- Sonuç:
-- Yorum:


-- S3: Churn edenlerle etmeyenler feature'larda farklı mı?
SELECT
    churned,
    COUNT(*)                          AS n,
    ROUND(AVG(recency_days), 1)       AS avg_recency,
    ROUND(AVG(frequency), 1)          AS avg_frequency,
    ROUND(AVG(monetary), 1)           AS avg_monetary,
    ROUND(AVG(tenure_days), 1)        AS avg_tenure
FROM features.customer_snapshot
GROUP BY churned;
-- Sonuç:
-- Yorum:

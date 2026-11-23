-- =====================================================================
-- SUPPLIER PERFORMANCE ANALYSIS - SQL (SQLite / MySQL friendly)
-- Data: supplier_po_data.csv (300 synthetic purchase orders, 2025)
-- Import the CSV into a table named po_data (columns below).
-- =====================================================================

CREATE TABLE po_data (
    po_id          VARCHAR(10),
    supplier       VARCHAR(60),
    category       VARCHAR(30),
    order_date     DATE,
    promised_date  DATE,
    delivery_date  DATE,
    qty_ordered    INT,
    qty_received   INT,
    qty_rejected   INT,
    unit_price     DECIMAL(10,2),
    order_value    DECIMAL(14,2),
    delay_days     INT          -- 0 if delivered on/before promised date
);

-- Q1. Total spend and PO count by supplier
SELECT supplier,
       COUNT(*)                    AS total_pos,
       ROUND(SUM(order_value), 0)  AS total_spend
FROM po_data
GROUP BY supplier
ORDER BY total_spend DESC;

-- Q2. On-time delivery % by supplier
SELECT supplier,
       COUNT(*) AS total_pos,
       SUM(CASE WHEN delay_days = 0 THEN 1 ELSE 0 END) AS on_time_pos,
       ROUND(100.0 * SUM(CASE WHEN delay_days = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS on_time_pct
FROM po_data
GROUP BY supplier
ORDER BY on_time_pct DESC;

-- Q3. Rejection % and average delay by supplier
SELECT supplier,
       ROUND(100.0 * SUM(qty_rejected) / SUM(qty_received), 2) AS reject_pct,
       ROUND(AVG(delay_days), 1)                                AS avg_delay_days
FROM po_data
GROUP BY supplier
ORDER BY reject_pct DESC;

-- Q4. Supplier scorecard (CTE + RANK) - same weights as the Excel Assumptions sheet
--     score = 100 * (0.5*on_time + 0.3*quality + 0.2*delay_score)
WITH base AS (
    SELECT supplier,
           COUNT(*) AS total_pos,
           SUM(order_value) AS total_spend,
           1.0 * SUM(CASE WHEN delay_days = 0 THEN 1 ELSE 0 END) / COUNT(*) AS on_time,
           AVG(delay_days) AS avg_delay,
           1.0 * SUM(qty_rejected) / SUM(qty_received) AS reject_rate
    FROM po_data
    GROUP BY supplier
),
scored AS (
    SELECT *,
           100 * (0.5 * on_time
                + 0.3 * MAX(0, 1 - reject_rate / 0.10)
                + 0.2 * MAX(0, 1 - avg_delay / 10.0)) AS score
    FROM base
)
SELECT supplier,
       ROUND(total_spend, 0)   AS total_spend,
       ROUND(100 * on_time, 1) AS on_time_pct,
       ROUND(avg_delay, 1)     AS avg_delay_days,
       ROUND(100 * reject_rate, 2) AS reject_pct,
       ROUND(score, 1)         AS score,
       RANK() OVER (ORDER BY score DESC) AS supplier_rank,
       CASE WHEN score >= 85 THEN 'A - Preferred'
            WHEN score >= 70 THEN 'B - Approved'
            ELSE 'C - Review' END AS grade
FROM scored
ORDER BY supplier_rank;
-- NOTE: MAX(a,b) with two arguments is SQLite. In MySQL use GREATEST(a,b).

-- Q5. Category-wise spend share
SELECT category,
       ROUND(SUM(order_value), 0) AS spend,
       ROUND(100.0 * SUM(order_value) / (SELECT SUM(order_value) FROM po_data), 1) AS spend_share_pct
FROM po_data
GROUP BY category
ORDER BY spend DESC;

-- Q6. Monthly spend trend (SQLite). MySQL: DATE_FORMAT(order_date, '%Y-%m')
SELECT SUBSTR(order_date, 1, 7) AS month,
       COUNT(*) AS pos,
       ROUND(SUM(order_value), 0) AS spend
FROM po_data
GROUP BY SUBSTR(order_date, 1, 7)
ORDER BY month;

-- Q7. Worst 10 late deliveries
SELECT po_id, supplier, category, promised_date, delivery_date, delay_days
FROM po_data
ORDER BY delay_days DESC
LIMIT 10;

-- Q8. Suppliers with on-time % below the overall average (risk list)
WITH s AS (
    SELECT supplier, 1.0 * SUM(CASE WHEN delay_days = 0 THEN 1 ELSE 0 END) / COUNT(*) AS otd
    FROM po_data GROUP BY supplier
)
SELECT supplier, ROUND(100 * otd, 1) AS on_time_pct
FROM s
WHERE otd < (SELECT 1.0 * SUM(CASE WHEN delay_days = 0 THEN 1 ELSE 0 END) / COUNT(*) FROM po_data)
ORDER BY otd;

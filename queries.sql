-- ============================================================
-- Olist E-Commerce Sales Analysis (SQL)
-- Database: olist_ecommerce (MySQL 8.x)
-- Tables: customers, orders, order_items, products, payments,
--         sellers, category_translation
-- All revenue is in Brazilian reais (R$) and counts DELIVERED orders only.
-- ============================================================

-- ----------------------------------------------------------
-- Setup: indexes on join keys (IDs were loaded as TEXT, so a
-- prefix length is required)
-- ----------------------------------------------------------
USE olist_ecommerce;
CREATE INDEX idx_orders_order_id ON orders (order_id(32));
CREATE INDEX idx_orders_customer_id ON orders (customer_id(32));
CREATE INDEX idx_customers_customer_id ON customers (customer_id(32));
CREATE INDEX idx_customers_unique_id ON customers (customer_unique_id(32));
CREATE INDEX idx_items_order_id ON order_items (order_id(32));
CREATE INDEX idx_items_product_id ON order_items (product_id(32));
CREATE INDEX idx_products_product_id ON products (product_id(32));
CREATE INDEX idx_products_category ON products (product_category_name(64));
CREATE INDEX idx_payments_order_id ON payments (order_id(32));
CREATE INDEX idx_translation_name ON category_translation (product_category_name(64));


-- ----------------------------------------------------------
-- Data check: order status breakdown
-- Purpose: decide which orders count as real sales.
-- Note: the status is spelled 'canceled' (one L) in this dataset.
-- ----------------------------------------------------------
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;


-- ----------------------------------------------------------
-- Data check: revenue with no English category name
-- Purpose: measure what an inner join would silently drop.
-- ----------------------------------------------------------
SELECT COALESCE(p.product_category_name, '(no category)') AS category,
       ROUND(SUM(oi.price), 2) AS revenue,
       COUNT(*) AS items
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL
GROUP BY category
ORDER BY revenue DESC;


-- ----------------------------------------------------------
-- Query 1: Revenue by product category (multi-table join)
-- Purpose: top categories by delivered revenue, plus revenue per order.
-- Techniques: 4-table JOIN, LEFT JOIN, COALESCE, aggregation
-- ----------------------------------------------------------
SELECT COALESCE(t.product_category_name_english, 'uncategorised') AS category,
       ROUND(SUM(oi.price), 2) AS revenue,
       COUNT(DISTINCT oi.order_id) AS orders,
       ROUND(SUM(oi.price) / COUNT(DISTINCT oi.order_id), 2) AS revenue_per_order
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;


-- ----------------------------------------------------------
-- Query 2: Monthly revenue and month-over-month growth
-- Purpose: show the revenue trend.
-- Techniques: CTE, DATE_FORMAT, LAG window function
-- Note: starts at 2017-01 because 2016 has very few orders per month
-- and a missing month (Nov 2016), which would make LAG compare
-- non-adjacent months and give meaningless growth percentages.
-- ----------------------------------------------------------
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
           ROUND(SUM(oi.price), 2) AS revenue,
           COUNT(DISTINCT oi.order_id) AS orders
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
    GROUP BY order_month
)
SELECT order_month,
       revenue,
       orders,
       LAG(revenue) OVER (ORDER BY order_month) AS prev_month_revenue,
       ROUND((revenue - LAG(revenue) OVER (ORDER BY order_month))
             / LAG(revenue) OVER (ORDER BY order_month) * 100, 1) AS mom_growth_pct
FROM monthly
ORDER BY order_month;


-- ----------------------------------------------------------
-- Query 3: Top 3 categories by revenue in each state
-- Purpose: compare what sells best across Brazilian states.
-- Techniques: chained CTEs, RANK() OVER (PARTITION BY ...)
-- ----------------------------------------------------------
WITH state_category AS (
    SELECT c.customer_state AS state,
           COALESCE(t.product_category_name_english, 'uncategorised') AS category,
           ROUND(SUM(oi.price), 2) AS revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state, category
),
ranked AS (
    SELECT state, category, revenue,
           RANK() OVER (PARTITION BY state ORDER BY revenue DESC) AS rnk
    FROM state_category
)
SELECT state, category, revenue, rnk
FROM ranked
WHERE rnk <= 3
ORDER BY state, rnk;


-- ----------------------------------------------------------
-- Query 4: Late deliveries by state
-- Purpose: find where deliveries miss Olist's own estimated date.
-- Techniques: date comparison, DATEDIFF, HAVING
-- Note: 'late' means delivered after the estimated delivery date.
-- States with fewer than 100 delivered orders are excluded (HAVING).
-- ----------------------------------------------------------
SELECT c.customer_state AS state,
       COUNT(*) AS delivered_orders,
       SUM(o.order_delivered_customer_date > o.order_estimated_delivery_date) AS late_orders,
       ROUND(SUM(o.order_delivered_customer_date > o.order_estimated_delivery_date)
             / COUNT(*) * 100, 1) AS late_pct,
       ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                          o.order_purchase_timestamp)), 1) AS avg_days_to_deliver
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(*) >= 100
ORDER BY late_pct DESC;


-- ----------------------------------------------------------
-- Query 5: Repeat-customer rate
-- Purpose: how many customers order more than once.
-- Techniques: CTE, conditional aggregation
-- Note: customer_id is generated per ORDER in this dataset, so the
-- real customer identifier customer_unique_id must be used.
-- ----------------------------------------------------------
WITH customer_orders AS (
    SELECT c.customer_unique_id,
           COUNT(DISTINCT o.order_id) AS order_count
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT COUNT(*) AS total_customers,
       SUM(order_count > 1) AS repeat_customers,
       ROUND(SUM(order_count > 1) / COUNT(*) * 100, 2) AS repeat_rate_pct,
       MAX(order_count) AS most_orders_by_one_customer
FROM customer_orders;

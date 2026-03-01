-- ============================================================
-- E-COMMERCE FUNNEL ANALYSIS - SQL QUERIES (PostgreSQL)
-- By Mark Daniel Muyo
-- FIXED FOR POSTGRESQL COMPATIBILITY
-- ============================================================

-- First, let's create the table and import data
-- Run this FIRST to set up your database:

CREATE TABLE IF NOT EXISTS user_events (
    event_id INTEGER,
    user_id INTEGER,
    event_type VARCHAR(50),
    event_date TIMESTAMP,
    product_id INTEGER,
    amount DECIMAL(10,2),
    traffic_source VARCHAR(50)
);

-- Then import your CSV using:
-- COPY user_events FROM '/path/to/user_events.csv' DELIMITER ',' CSV HEADER;

-- ============================================================
-- 1. CONVERSION FUNNEL ANALYSIS
-- ============================================================

-- Q1.1: Overall conversion rate at each funnel stage
WITH funnel_counts AS (
    SELECT 
        COUNT(CASE WHEN event_type = 'page_view' THEN 1 END) as page_views,
        COUNT(CASE WHEN event_type = 'add_to_cart' THEN 1 END) as add_to_carts,
        COUNT(CASE WHEN event_type = 'checkout_start' THEN 1 END) as checkouts,
        COUNT(CASE WHEN event_type = 'payment_info' THEN 1 END) as payment_info,
        COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as purchases
    FROM user_events
)
SELECT 
    page_views,
    add_to_carts,
    ROUND((100.0 * add_to_carts / NULLIF(page_views, 0))::numeric, 2) as add_to_cart_rate,
    checkouts,
    ROUND((100.0 * checkouts / NULLIF(add_to_carts, 0))::numeric, 2) as checkout_rate,
    payment_info,
    ROUND((100.0 * payment_info / NULLIF(checkouts, 0))::numeric, 2) as payment_info_rate,
    purchases,
    ROUND((100.0 * purchases / NULLIF(payment_info, 0))::numeric, 2) as purchase_rate,
    ROUND((100.0 * purchases / NULLIF(page_views, 0))::numeric, 2) as overall_conversion_rate
FROM funnel_counts;

-- Q1.2: Biggest drop-off points
WITH funnel_steps AS (
    SELECT 
        COUNT(CASE WHEN event_type = 'page_view' THEN 1 END) as step1,
        COUNT(CASE WHEN event_type = 'add_to_cart' THEN 1 END) as step2,
        COUNT(CASE WHEN event_type = 'checkout_start' THEN 1 END) as step3,
        COUNT(CASE WHEN event_type = 'payment_info' THEN 1 END) as step4,
        COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as step5
    FROM user_events
)
SELECT 
    'Page View → Add to Cart' as funnel_stage,
    step1 - step2 as users_dropped,
    ROUND((100.0 * (step1 - step2) / NULLIF(step1, 0))::numeric, 2) as drop_off_rate
FROM funnel_steps
UNION ALL
SELECT 
    'Add to Cart → Checkout',
    step2 - step3,
    ROUND((100.0 * (step2 - step3) / NULLIF(step2, 0))::numeric, 2)
FROM funnel_steps
UNION ALL
SELECT 
    'Checkout → Payment Info',
    step3 - step4,
    ROUND((100.0 * (step3 - step4) / NULLIF(step3, 0))::numeric, 2)
FROM funnel_steps
UNION ALL
SELECT 
    'Payment Info → Purchase',
    step4 - step5,
    ROUND((100.0 * (step4 - step5) / NULLIF(step4, 0))::numeric, 2)
FROM funnel_steps
ORDER BY drop_off_rate DESC;

-- ============================================================
-- 2. REVENUE ANALYSIS
-- ============================================================

-- Q2.1: Total revenue by traffic source
SELECT 
    traffic_source,
    COUNT(*) as total_purchases,
    ROUND(SUM(amount)::numeric, 2) as total_revenue,
    ROUND(AVG(amount)::numeric, 2) as avg_order_value,
    ROUND((100.0 * COUNT(*) / SUM(COUNT(*)) OVER())::numeric, 2) as pct_of_purchases
FROM user_events
WHERE event_type = 'purchase'
GROUP BY traffic_source
ORDER BY total_revenue DESC;

-- Q2.2: Revenue trend over time (daily)
SELECT 
    event_date::date as purchase_date,
    COUNT(*) as daily_purchases,
    ROUND(SUM(amount)::numeric, 2) as daily_revenue,
    ROUND(AVG(amount)::numeric, 2) as avg_order_value
FROM user_events
WHERE event_type = 'purchase'
GROUP BY event_date::date
ORDER BY purchase_date;

-- ============================================================
-- 3. PRODUCT PERFORMANCE
-- ============================================================

-- Q3.1: Products by revenue
SELECT 
    product_id,
    COUNT(*) as times_purchased,
    ROUND(SUM(amount)::numeric, 2) as total_revenue,
    ROUND(AVG(amount)::numeric, 2) as avg_price,
    ROUND((100.0 * SUM(amount) / SUM(SUM(amount)) OVER())::numeric, 2) as revenue_share_pct
FROM user_events
WHERE event_type = 'purchase'
GROUP BY product_id
ORDER BY total_revenue DESC;

-- Q3.2: Product conversion rates
WITH product_funnel AS (
    SELECT 
        product_id,
        COUNT(CASE WHEN event_type = 'page_view' THEN 1 END) as views,
        COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as purchases
    FROM user_events
    GROUP BY product_id
)
SELECT 
    product_id,
    views,
    purchases,
    ROUND((100.0 * purchases / NULLIF(views, 0))::numeric, 2) as conversion_rate
FROM product_funnel
ORDER BY conversion_rate DESC;

-- Q3.3: Cart abandonment by product
WITH cart_stats AS (
    SELECT 
        product_id,
        COUNT(CASE WHEN event_type = 'add_to_cart' THEN 1 END) as carts,
        COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as purchases
    FROM user_events
    GROUP BY product_id
)
SELECT 
    product_id,
    carts as added_to_cart,
    purchases,
    carts - purchases as abandoned_carts,
    ROUND((100.0 * (carts - purchases) / NULLIF(carts, 0))::numeric, 2) as abandonment_rate
FROM cart_stats
WHERE carts > 0
ORDER BY abandonment_rate DESC;

-- ============================================================
-- 4. USER BEHAVIOR ANALYSIS
-- ============================================================

-- Q4.1: User purchase rate
WITH user_activity AS (
    SELECT 
        COUNT(DISTINCT user_id) as total_users,
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) as purchasing_users
    FROM user_events
)
SELECT 
    total_users,
    purchasing_users,
    total_users - purchasing_users as non_purchasers,
    ROUND((100.0 * purchasing_users / NULLIF(total_users, 0))::numeric, 2) as purchase_rate
FROM user_activity;

-- Q4.2: Repeat customer analysis
WITH user_purchases AS (
    SELECT 
        user_id,
        COUNT(*) as purchase_count,
        SUM(amount) as lifetime_value
    FROM user_events
    WHERE event_type = 'purchase'
    GROUP BY user_id
)
SELECT 
    CASE 
        WHEN purchase_count = 1 THEN '1 purchase'
        WHEN purchase_count = 2 THEN '2 purchases'
        WHEN purchase_count >= 3 THEN '3+ purchases'
    END as customer_segment,
    COUNT(*) as num_customers,
    ROUND(AVG(lifetime_value)::numeric, 2) as avg_ltv,
    ROUND(SUM(lifetime_value)::numeric, 2) as total_revenue
FROM user_purchases
GROUP BY 
    CASE 
        WHEN purchase_count = 1 THEN '1 purchase'
        WHEN purchase_count = 2 THEN '2 purchases'
        WHEN purchase_count >= 3 THEN '3+ purchases'
    END
ORDER BY 
    CASE 
        WHEN customer_segment = '1 purchase' THEN 1
        WHEN customer_segment = '2 purchases' THEN 2
        ELSE 3
    END;

-- Q4.3: Top 20 customers by revenue
SELECT 
    user_id,
    COUNT(*) as num_purchases,
    ROUND(SUM(amount)::numeric, 2) as total_spent,
    ROUND(AVG(amount)::numeric, 2) as avg_order_value
FROM user_events
WHERE event_type = 'purchase'
GROUP BY user_id
ORDER BY total_spent DESC
LIMIT 20;

-- ============================================================
-- 5. ADVANCED ANALYTICS
-- ============================================================

-- Q5.1: Cohort analysis by first traffic source
WITH first_touch AS (
    SELECT DISTINCT ON (user_id)
        user_id,
        traffic_source as first_source
    FROM user_events
    ORDER BY user_id, event_date
),
cohort_metrics AS (
    SELECT 
        ft.first_source,
        COUNT(DISTINCT ue.user_id) as total_users,
        COUNT(DISTINCT CASE WHEN ue.event_type = 'purchase' THEN ue.user_id END) as purchasers,
        SUM(CASE WHEN ue.event_type = 'purchase' THEN ue.amount ELSE 0 END) as revenue
    FROM first_touch ft
    JOIN user_events ue ON ft.user_id = ue.user_id
    GROUP BY ft.first_source
)
SELECT 
    first_source,
    total_users,
    purchasers,
    ROUND((100.0 * purchasers / NULLIF(total_users, 0))::numeric, 2) as conversion_rate,
    ROUND(revenue::numeric, 2) as total_revenue,
    ROUND((revenue / NULLIF(total_users, 0))::numeric, 2) as revenue_per_user
FROM cohort_metrics
ORDER BY revenue_per_user DESC;

-- Q5.2: Daily active users and purchases
SELECT 
    event_date::date as date,
    COUNT(DISTINCT user_id) as daily_active_users,
    COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) as daily_purchasers,
    ROUND((100.0 * COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) / NULLIF(COUNT(DISTINCT user_id), 0))::numeric, 2) as daily_conversion_rate
FROM user_events
GROUP BY event_date::date
ORDER BY date;

-- Q5.3: Hour of day analysis
SELECT 
    EXTRACT(HOUR FROM event_date)::integer as hour_of_day,
    COUNT(*) as total_events,
    COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as purchases,
    ROUND(SUM(CASE WHEN event_type = 'purchase' THEN amount ELSE 0 END)::numeric, 2) as revenue
FROM user_events
GROUP BY EXTRACT(HOUR FROM event_date)::integer
ORDER BY hour_of_day;

-- ============================================================
-- 6. BUSINESS RECOMMENDATIONS
-- ============================================================

-- Q6.1: Traffic source performance & recommendations
WITH source_performance AS (
    SELECT 
        traffic_source,
        COUNT(DISTINCT user_id) as users,
        COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) as buyers,
        SUM(CASE WHEN event_type = 'purchase' THEN amount ELSE 0 END) as revenue
    FROM user_events
    GROUP BY traffic_source
)
SELECT 
    traffic_source,
    users,
    buyers,
    ROUND((100.0 * buyers / NULLIF(users, 0))::numeric, 2) as conversion_rate,
    ROUND(revenue::numeric, 2) as revenue,
    ROUND((revenue / NULLIF(users, 0))::numeric, 2) as revenue_per_user,
    CASE 
        WHEN revenue / NULLIF(users, 0) > 20 THEN 'High Priority - Increase Budget'
        WHEN revenue / NULLIF(users, 0) > 15 THEN 'Medium Priority - Maintain'
        ELSE 'Low Priority - Optimize'
    END as recommendation
FROM source_performance
ORDER BY revenue_per_user DESC;

-- Q6.2: Products needing attention
WITH product_metrics AS (
    SELECT 
        product_id,
        COUNT(CASE WHEN event_type = 'page_view' THEN 1 END) as views,
        COUNT(CASE WHEN event_type = 'add_to_cart' THEN 1 END) as carts,
        COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as purchases,
        SUM(CASE WHEN event_type = 'purchase' THEN amount ELSE 0 END) as revenue
    FROM user_events
    GROUP BY product_id
)
SELECT 
    product_id,
    views,
    carts,
    purchases,
    ROUND((100.0 * purchases / NULLIF(views, 0))::numeric, 2) as conversion_rate,
    ROUND((100.0 * (carts - purchases) / NULLIF(carts, 0))::numeric, 2) as cart_abandonment_rate,
    ROUND(revenue::numeric, 2) as revenue,
    CASE 
        WHEN purchases::float / NULLIF(views, 0) < 0.10 THEN 'Review product page & pricing'
        WHEN (carts - purchases)::float / NULLIF(carts, 0) > 0.50 THEN 'High cart abandonment - check checkout flow'
        ELSE 'Performing well'
    END as action_needed
FROM product_metrics
ORDER BY conversion_rate;

-- ============================================================
-- VERIFICATION QUERIES
-- ============================================================

-- Check data import
SELECT 
    'Total Records' as metric,
    COUNT(*) as value
FROM user_events
UNION ALL
SELECT 
    'Date Range',
    COUNT(DISTINCT event_date::date)
FROM user_events
UNION ALL
SELECT 
    'Unique Users',
    COUNT(DISTINCT user_id)
FROM user_events
UNION ALL
SELECT 
    'Total Revenue',
    ROUND(SUM(amount)::numeric, 2)
FROM user_events
WHERE event_type = 'purchase';

-- ============================================================
-- END OF SQL PROJECT
-- ============================================================

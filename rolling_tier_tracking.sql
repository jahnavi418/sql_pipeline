-- =========================================================
-- Rolling 12-Month Customer Tier Tracking (with Downgrades)
-- =========================================================
-- Goal: For each customer, detect every month where their tier
-- (based on TRAILING 12-MONTH spend) changed -- whether that's
-- an upgrade OR a downgrade -- and output customer_id, month,
-- previous_tier, new_tier.
--
-- Tiers:
--   Platinum : rolling 12-month spend >= 50,000
--   Gold     : rolling 12-month spend >= 25,000
--   Silver   : rolling 12-month spend >= 10,000
--   None     : below 10,000
--
-- Key idea: unlike an all-time cumulative total, a rolling
-- 12-month total can DROP as old high-spend months "roll out"
-- of the trailing window -- so tier can downgrade even in a
-- month with zero new orders. That means we need a continuous,
-- gap-free monthly calendar per customer before we can safely
-- use a ROWS BETWEEN frame for the rolling sum.
-- =========================================================

with

-- Step 0: Get each customer's active date range (first to last order month)
cte as (
    select
        customer_id,
        date_trunc('month', min(order_date)) as start_month,
        date_trunc('month', max(order_date)) as end_month
    from orders
    group by customer_id
),

-- Step 1: Build a full monthly calendar per customer (no gaps),
-- from their first order month through their last order month.
cte2 as (
    select
        customer_id,
        generate_series(start_month, end_month, interval '1 month') as month
    from cte
),

-- Step 2: Actual monthly totals -- only exists for months with orders.
cte3 as (
    select
        customer_id,
        date_trunc('month', order_date) as month,
        sum(order_amount) as monthly_total
    from orders
    group by customer_id, date_trunc('month', order_date)
),

-- Step 3: Left join calendar (cte2) with actual totals (cte3),
-- so every month appears, with 0 spend where there were no orders.
cte4 as (
    select
        cte2.customer_id,
        cte2.month,
        coalesce(cte3.monthly_total, 0) as monthly_total
    from cte2
    left join cte3
        on cte2.customer_id = cte3.customer_id
        and cte2.month = cte3.month
),

-- Step 4: Rolling 12-month spend per customer per month.
-- ROWS BETWEEN 11 PRECEDING AND CURRENT ROW = trailing 12 rows
-- (11 before + current). This is only valid because cte4 has
-- zero gaps -- each row reliably represents exactly one month.
cte5 as (
    select
        customer_id,
        month,
        sum(monthly_total) over (
            partition by customer_id
            order by month
            rows between 11 preceding and current row
        ) as rolling_spend
    from cte4
),

-- Step 5: Map rolling spend to a tier label.
-- Order matters: check the highest threshold first, since CASE
-- stops at the first matching WHEN.
cte6 as (
    select
        customer_id,
        month,
        case
            when rolling_spend >= 50000 then 'platinum'
            when rolling_spend >= 25000 then 'gold'
            when rolling_spend >= 10000 then 'silver'
            else 'none'
        end as tier
    from cte5
),

-- Step 6: Get each customer's previous month's tier via LAG.
-- COALESCE defaults the very first month's "previous tier" to
-- 'none', so a customer who jumps straight to Silver in month 1
-- correctly shows up as a None -> Silver change.
cte7 as (
    select
        customer_id,
        month,
        tier as new_tier,
        coalesce(
            lag(tier) over (partition by customer_id order by month),
            'none'
        ) as previous_tier
    from cte6
)

-- Final: keep only the months where tier actually changed
-- (upgrade or downgrade).
select
    customer_id,
    month,
    previous_tier,
    new_tier
from cte7
where new_tier <> previous_tier
order by customer_id, month;

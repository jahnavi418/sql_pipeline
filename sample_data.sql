-- =========================================================
-- Sample data for rolling_tier_tracking.sql
-- Two customers, chosen to demonstrate both upgrades AND
-- downgrades in the rolling 12-month tier logic.
-- =========================================================

create table if not exists orders (
    order_id      int primary key,
    customer_id   int not null,
    order_date    date not null,
    order_amount  numeric not null
);

-- Customer 202: worked example from practice session.
-- Expected tier changes:
--   2023-03  none    -> silver    (12,000 rolling spend)
--   2023-08  silver  -> gold      (27,000 rolling spend)
--   2024-03  gold    -> silver    (2023-03's 12,000 rolls out of the 12mo window)
--   2024-08  silver  -> none      (2023-08's 15,000 rolls out of the 12mo window)
--   2024-09  none    -> gold      (30,000 new order pushes rolling spend to 38,000)
insert into orders (order_id, customer_id, order_date, order_amount) values
    (1, 202, '2023-03-10', 12000),
    (2, 202, '2023-08-05', 15000),
    (3, 202, '2024-02-20', 8000),
    (4, 202, '2024-09-15', 30000);

-- Customer 305: simple case, single tier jump straight to Gold
-- in their very first order month -- tests the COALESCE(..., 'none')
-- handling for a customer's first month.
insert into orders (order_id, customer_id, order_date, order_amount) values
    (5, 305, '2024-01-10', 28000),
    (6, 305, '2024-05-10', 5000);

-- Customer 410: stays flat under every threshold -- should
-- produce ZERO rows in the final output (no tier change ever).
insert into orders (order_id, customer_id, order_date, order_amount) values
    (7, 410, '2024-01-15', 2000),
    (8, 410, '2024-06-15', 1500);

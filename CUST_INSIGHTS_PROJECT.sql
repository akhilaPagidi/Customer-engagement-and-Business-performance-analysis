use customer_insights1;
select * from campaign_marketing;
select * from customer_reviews;
select * from customers;
select * from interactions;
select * from support_ticket;
select * from transactions;

SET SQL_SAFE_UPDATES = 0;
#-----------------------------------------------------------------------------------

-- changing data types of transactions table
describe transactions;
UPDATE transactions
SET transaction_date = DATE_FORMAT(
    STR_TO_DATE(transaction_date, '%d-%m-%Y'),
    '%Y-%m-%d'
);
ALTER TABLE transactions
MODIFY COLUMN transaction_date DATE;
ALTER TABLE transactions
MODIFY COLUMN quantity int;

#---------------------------------------------------------------------------------------------

-- changing datatypes of support_ticket
alter table support_ticket
modify column resolution_time_hours int,
modify column customer_satisfaction_score int;
describe support_ticket;

#---------------------------------------------------------------------------------------------

-- changing datatypes of customers
describe customers;
alter table customers
modify column age int;

#------------------------------------------------------------------------

-- customer reviews
describe customer_reviews;
alter table customer_reviews
modify column transaction_date date,
modify column review_date date,
modify column rating int;

#------------------------------------------------------------------------

-- campaign marketing
describe campaign_marketing;
alter table campaign_marketing
modify column start_date date,
modify column end_date date;

#----------------------------------------------------------------------
# 1. what are the most sold product categories??
select product_category,sum(quantity) as total_quantity_sold
from transactions
group by product_category
order by total_quantity_sold desc
limit 10;

# 2.stores and their highest sold product category?
WITH store_revenue_category AS (
    SELECT store_location,product_category,ROUND(SUM(quantity * price), 2) AS revenue
    FROM transactions
    GROUP BY store_location, product_category
),
ranked_categories AS (
    SELECT store_location,product_category,revenue,RANK() OVER (PARTITION BY store_location ORDER BY revenue DESC) AS ranking
    FROM store_revenue_category
)
SELECT
    store_location,
    product_category,
    revenue AS high_revenue
FROM ranked_categories
WHERE ranking = 1
ORDER BY high_revenue DESC;


# 3.which customers interact frequently but never purchased?

SELECT
    c.full_name,
    COUNT(i.interaction_id) AS total_interactions
FROM customers c
JOIN interactions i
    ON c.customer_id = i.customer_id
LEFT JOIN transactions t
    ON c.customer_id = t.customer_id
WHERE t.customer_id IS NULL
GROUP BY c.customer_id, c.full_name
HAVING COUNT(i.interaction_id) >= 5
ORDER BY total_interactions DESC;

#4. which issue raises the support ticket most

select issue_category,count(issue_category) as number_of_issues
from support_ticket
group by issue_category
order by number_of_issues desc;

# 5.average days taken to resolve a ticket

SELECT
    ROUND(AVG(DATEDIFF(resolution_date, submission_date)), 2)
        AS avg_resolution_days
FROM support_ticket
WHERE resolution_status = 'Resolved';

select * from support_ticket;

# 6.which issues have lowest customer satisfaction?

SELECT
    issue_category,
    ROUND(AVG(customer_satisfaction_score), 2)
        AS avg_satisfaction,
    COUNT(*) AS total_tickets
FROM support_ticket
WHERE customer_satisfaction_score IS NOT NULL
GROUP BY issue_category
HAVING COUNT(customer_satisfaction_score) >= 5
ORDER BY avg_satisfaction ASC;

select * from campaign_marketing;

# 7.which campaigns have above average of all the roi's?
select campaign_name,budget,roi
from campaign_marketing
where roi >(select avg(roi)
from campaign_marketing);

SELECT campaign_name, roi
FROM campaign_marketing
ORDER BY roi DESC
LIMIT 10;

# 8which month generates how much revenue?
select * from transactions;
SELECT YEAR(transaction_date) AS year,
    MONTHNAME(transaction_date) AS month,
    ROUND(SUM(quantity * price), 2) AS revenue
FROM transactions
GROUP BY
    YEAR(transaction_date),
    MONTHNAME(transaction_date)
ORDER BY revenue desc;

# 9.who are top 3 customers by each city
with customer_transaction_value as (
select customer_id,round(sum(quantity*price),2) as total_spent
from transactions
group by customer_id
),
ranking as (
select v.customer_id,c.full_name,v.total_spent,c.city,dense_rank() over(partition by city order by total_spent desc) as ranking1
from customer_transaction_value v
join customers c
on c.customer_id=v.customer_id)
select *
from ranking
where ranking1 < 4
order by city;

#10.monthly revenue and month-over-month percentage change.

WITH monthly_revenue AS (
    SELECT YEAR(transaction_date) AS sales_year,
        MONTH(transaction_date) AS sales_month,
        ROUND(SUM(quantity * price), 2) AS revenue
    FROM transactions
    GROUP BY
        YEAR(transaction_date),
        MONTH(transaction_date)
),
revenue_comparison AS (
    SELECT
        sales_year,
        sales_month,
        revenue,
        LAG(revenue) OVER (
            ORDER BY sales_year, sales_month
        ) AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    sales_year,sales_month,revenue,previous_month_revenue,
    ROUND(
        (revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0) * 100,
        2
    ) AS revenue_growth_pct
FROM revenue_comparison
ORDER BY sales_year, sales_month;

# 11.Which stores are losing revenue, and which product categories are responsible?

WITH monthly_store_category AS (
    SELECT YEAR(transaction_date) AS sales_year,MONTH(transaction_date) AS sales_month,
        store_location,
        product_category,
        SUM(quantity * price) AS revenue
    FROM transactions
    GROUP BY
        YEAR(transaction_date),
        MONTH(transaction_date),
        store_location,
        product_category
),
revenue_comparison AS (
    SELECT sales_year,sales_month,store_location,product_category,revenue,
        LAG(revenue) OVER (
            PARTITION BY store_location, product_category
            ORDER BY sales_year, sales_month
        ) AS previous_revenue
    FROM monthly_store_category
)
SELECT sales_year,sales_month,store_location,product_category,
    ROUND(previous_revenue, 2) AS previous_revenue,
    ROUND(revenue, 2) AS current_revenue,
    ROUND(revenue - previous_revenue, 2) AS revenue_change
FROM revenue_comparison
WHERE previous_revenue IS NOT NULL
  AND revenue < previous_revenue
ORDER BY revenue_change ASC;

# sales summary
CREATE VIEW sales_summary AS
SELECT
    store_location,
    product_category,
    COUNT(DISTINCT transaction_id) AS total_transactions,
    SUM(quantity) AS total_units_sold,
    ROUND(SUM(quantity * price), 2) AS total_revenue
FROM transactions
GROUP BY store_location, product_category;

SELECT *
FROM sales_summary
ORDER BY total_revenue DESC
LIMIT 5;

DELIMITER //

CREATE PROCEDURE GetHighValueCustomers(IN min_revenue DECIMAL(12,2))
BEGIN
    SELECT
        customer_id,
        SUM(quantity * price) AS total_revenue,
        COUNT(DISTINCT transaction_id) AS total_transactions
    FROM transactions
    GROUP BY customer_id
    HAVING SUM(quantity * price) > min_revenue
    ORDER BY total_revenue DESC;
END //

DELIMITER ;
CALL GetHighValueCustomers(10000);

# trigger after every transaction

CREATE TABLE transaction_audit (
    audit_id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100),
    action_type VARCHAR(20),
    audit_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DELIMITER //

CREATE TRIGGER after_transaction_insert
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    INSERT INTO transaction_audit (
        transaction_id,
        action_type
    )
    VALUES (
        NEW.transaction_id,
        'INSERT'
    );
END //

DELIMITER ;

INSERT INTO transactions (transaction_id,customer_id,product_name,product_category,quantity,price,transaction_date,
    store_location,payment_method,discount_applied
)
VALUES ('TXN99999','CUST1001','Wireless Mouse','Electronics',2,750.00,NOW(),'Hyderabad','UPI',0
);

SELECT *
FROM transaction_audit
WHERE transaction_id = 'TXN99999';

# high value customers who are dissapointed
WITH revenue AS (
    SELECT customer_id,SUM(quantity * price) AS total_revenue
    FROM transactions
    GROUP BY customer_id
),
support AS (
    SELECT
        customer_id,COUNT(*) AS ticket_count,
        AVG(customer_satisfaction_score) AS avg_satisfaction
    FROM support_ticket
    GROUP BY customer_id
)
SELECT
    r.customer_id,
    ROUND(r.total_revenue, 2) AS total_revenue,
    s.ticket_count,
    ROUND(s.avg_satisfaction, 2) AS avg_satisfaction
FROM revenue r
JOIN support s
    ON r.customer_id = s.customer_id
WHERE s.ticket_count >= 2
  AND s.avg_satisfaction < 3
ORDER BY r.total_revenue DESC;

#issues that are taking longest to resolve
SELECT
    issue_category,
    COUNT(*) AS total_tickets,
    AVG(resolution_time_hours) AS avg_resolution_hours,
    ROUND(AVG(customer_satisfaction_score), 2) AS avg_satisfaction
FROM support_ticket
GROUP BY issue_category
ORDER BY avg_resolution_hours DESC;

# customers whose orders are decreasing

WITH monthly_orders AS (
    SELECT
        customer_id,
        YEAR(transaction_date) AS sales_year,
        MONTH(transaction_date) AS sales_month,
        COUNT(DISTINCT transaction_id) AS total_orders
    FROM transactions
    GROUP BY customer_id, YEAR(transaction_date), MONTH(transaction_date)
),
comparison AS (
    SELECT *,
        LAG(total_orders) OVER (
            PARTITION BY customer_id
            ORDER BY sales_year, sales_month
        ) AS previous_orders
    FROM monthly_orders
)
SELECT
    customer_id,
    sales_year,
    sales_month,
    previous_orders,
    total_orders AS current_orders
FROM comparison
WHERE previous_orders IS NOT NULL
  AND total_orders < previous_orders
ORDER BY previous_orders - total_orders DESC;
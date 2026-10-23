# Olist E-Commerce Sales Analysis (SQL)

SQL analysis of the public Brazilian e-commerce dataset from Olist (about 100,000 orders, 2016 to 2018), using MySQL. The goal is to practise multi-table joins, window functions and CTEs on a realistic, relational dataset, and to document the data-quality decisions behind each result.

## Data and setup

- **Source:** *Brazilian E-Commerce Public Dataset by Olist* (Kaggle), 7 of the 9 CSV files used.
- **Database:** MySQL 8.x, schema `olist_ecommerce`.
- **Loading:** CSVs read with pandas and written to MySQL with `DataFrame.to_sql` (SQLAlchemy). Date columns in `orders` were converted to real datetimes before loading so date logic works in SQL.
- **Indexes** were added on the join keys (see `queries.sql`).
- **Currency:** all amounts are Brazilian reais (R$).

| Table | Rows |
|---|---|
| customers | 99,441 |
| orders | 99,441 |
| order_items | 112,650 |
| products | 32,951 |
| payments | 103,886 |
| sellers | 3,095 |
| category_translation | 71 |

## Decisions made on purpose

1. **Revenue counts delivered orders only.** 96,478 of 99,441 orders (97.0%) are delivered. The rest are shipped, canceled, unavailable or still in progress. Counting all of them overstated revenue and changed the category ranking.
2. **Missing categories are labelled, not dropped.** R$185,049.76 of item revenue had no English category name. R$179,535.28 (1,603 items) belongs to products with no category at all, and about R$5.5K belongs to two categories missing from the translation table. A `LEFT JOIN` with `COALESCE` keeps this revenue under "uncategorised" so totals still reconcile.
3. **2016 is excluded from the monthly trend.** Those months have very few orders and November 2016 is missing entirely. `LAG` compares the previous row, not the previous calendar month, so growth percentages there were misleading.
4. **`customer_unique_id` is used for repeat customers.** In this dataset `customer_id` is created fresh for every order, so counting it would always show zero repeat buyers.
5. **Small groups are filtered.** States with fewer than 100 delivered orders are excluded from the late-delivery analysis.

## Queries and findings

### 1. Revenue by product category
Joins four tables (`order_items`, `orders`, `products`, `category_translation`).

| Category | Revenue (R$) | Orders | Revenue per order (R$) |
|---|---|---|---|
| health_beauty | 1,233,132 | 8,647 | 142.61 |
| watches_gifts | 1,166,177 | 5,495 | 212.23 |
| bed_bath_table | 1,023,435 | 9,272 | 110.38 |
| sports_leisure | 954,853 | 7,530 | 126.81 |
| computers_accessories | 888,725 | 6,530 | 136.10 |

**Finding:** revenue depends on both volume and price. `bed_bath_table` has the most orders but ranks third, while `watches_gifts` ranks second with far fewer orders because each order is worth about R$212. Filtering to delivered orders also reshuffled the lower ranks (positions 7 to 10) compared with an unfiltered query.

### 2. Monthly revenue and growth (`LAG`)
Delivered revenue grew from about R$112K (750 orders) in January 2017 to R$648K (4,478 orders) by October 2017, roughly 5.8x in nine months. The peak came in **November 2017: R$987,765 from 7,289 orders (+52.4% on October)**, followed by a drop of 26.5% in December. From March 2018 onwards, growth flattened out: monthly revenue stayed between about R$830K and R$980K (+15.4% in March, then +2.1% and +0.4% in April and May, then -12.4% in June). August 2018 closed at R$838,577, still about 7.5x January 2017 but below the November 2017 peak.

**Finding:** the business scaled quickly through 2017, then plateaued in 2018 rather than continuing to grow.

### 3. Top 3 categories per state (`RANK` + chained CTEs)
Returns 81 rows (27 states x 3). The leading category changes by state:

| State | #1 | #2 | #3 |
|---|---|---|---|
| SP (largest) | bed_bath_table (R$472K) | health_beauty (R$454K) | watches_gifts (R$422K) |
| RJ | watches_gifts (R$175K) | bed_bath_table (R$144K) | health_beauty (R$140K) |
| RR (smallest shown) | sports_leisure (R$1.4K) | home_appliances (R$954) | baby (R$950) |

**Finding:** the national #1 category, `health_beauty`, is not #1 in either of the two biggest states (it is #2 in SP and #3 in RJ), and `watches_gifts` leads in RJ. In SP the top three are within about 11% of each other. In RR, the top three categories total only about R$3.3K, so the ranking there rests on a handful of orders and shouldn't be over-read.

### 4. Late deliveries by state
24 states have at least 100 delivered orders. Late deliveries are highest in the northeast, for example AL (23.9% late), MA (19.7%), PI (16.0%) and CE (15.3%). Slow is not the same as late: PA averages 23.7 days to deliver but 12.4% of orders are late, while RJ, with 12,350 delivered orders, is late 13.5% of the time.

### 5. Repeat-customer rate
Of 93,358 customers with a delivered order, 2,801 (3.00%) ordered more than once, and the most orders from one customer was 15.

## Techniques demonstrated
- Multi-table `JOIN` and `LEFT JOIN`
- Aggregation with `GROUP BY` and `HAVING`
- Window functions: `LAG`, `RANK() OVER (PARTITION BY ...)`
- Common table expressions, including chained CTEs
- Date handling: `DATE_FORMAT`, `DATEDIFF`, date comparisons
- Data-quality checks: status breakdown, missing-category audit
- Index creation for join performance

## Limitations
- "Late" is measured against Olist's own estimated delivery date, not against customer expectations.
- The dataset covers roughly 2016 to 2018 and is from a single marketplace.
- Rankings in small states rest on few orders.

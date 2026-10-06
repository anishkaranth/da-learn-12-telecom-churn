-- 04_analysis.sql  Business KPIs (Spark SQL dialect).
-- Churn = customers who left within the last month (Churn = 'Yes'); churn rate = churned / customers.
-- MRR = sum of current MonthlyCharges; revenue at risk ("mrr_lost") = MonthlyCharges of churned customers (x12 = annualised).
-- Lifetime revenue = TotalCharges billed to date (a CLV-to-date proxy; the file has no costs or margins).
-- The file is a single snapshot, so "tenure cohorts" compare customers by how long they have stayed, not by join date.
-- Every segment table shares the same columns: customers, churned, churn_rate_pct, customer_share_pct, churner_share_pct,
-- mrr, mrr_lost, mrr_lost_share_pct, avg_monthly_charges, avg_tenure_months, lifetime_revenue.

-- One wide view over the star (fact + all dims); every a_* table below reads the star through it.
CREATE OR REPLACE TEMPORARY VIEW v_sub AS
SELECT f.*, k.contract, k.contract_term_months, p.payment_method, p.is_auto_pay, p.payment_channel,
       d.gender, d.senior_citizen, d.partner, d.dependents, d.is_senior, d.has_partner, d.has_dependents, d.household,
       s.has_phone, s.has_multiple_lines, s.internet_service, s.has_internet, s.service_profile,
       s.has_online_security, s.has_online_backup, s.has_device_protection, s.has_tech_support,
       s.has_streaming_tv, s.has_streaming_movies, s.protection_addons, s.streaming_addons,
       t.min_tenure_months AS tenure_band_min,
       CASE WHEN f.tenure_months <= 12 THEN 'Y1 0-12' WHEN f.tenure_months <= 24 THEN 'Y2 13-24'
            WHEN f.tenure_months <= 36 THEN 'Y3 25-36' WHEN f.tenure_months <= 48 THEN 'Y4 37-48'
            WHEN f.tenure_months <= 60 THEN 'Y5 49-60' ELSE 'Y6 61-72' END AS tenure_year
FROM fact_subscription f
JOIN dim_contract k ON k.contract_key = f.contract_key
JOIN dim_payment p ON p.payment_key = f.payment_key
JOIN dim_demographics d ON d.demographics_key = f.demographics_key
JOIN dim_services s ON s.services_key = f.services_key
JOIN dim_tenure_band t ON t.tenure_band = f.tenure_band;

CREATE OR REPLACE TABLE a_kpi_headline AS
SELECT COUNT(*) AS customers,
       SUM(churned) AS churned_customers,
       COUNT(*) - SUM(churned) AS retained_customers,
       ROUND(100.0 * SUM(churned) / COUNT(*), 2) AS churn_rate_pct,
       SUM(monthly_charges) AS mrr_total,
       SUM(mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(mrr_lost) / SUM(monthly_charges), 2) AS mrr_lost_pct,
       SUM(annualised_revenue_lost) AS annualised_revenue_lost,
       ROUND(AVG(monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(CASE WHEN churned = 1 THEN monthly_charges END), 2) AS avg_monthly_churned,
       ROUND(AVG(CASE WHEN churned = 0 THEN monthly_charges END), 2) AS avg_monthly_retained,
       ROUND(AVG(tenure_months), 1) AS avg_tenure_months,
       ROUND(percentile_approx(CASE WHEN churned = 1 THEN tenure_months END, 0.5), 1) AS median_tenure_churned,
       ROUND(percentile_approx(CASE WHEN churned = 0 THEN tenure_months END, 0.5), 1) AS median_tenure_retained,
       SUM(total_charges) AS lifetime_revenue_total,
       SUM(CASE WHEN churned = 1 THEN total_charges ELSE 0 END) AS lifetime_revenue_churned,
       ROUND(AVG(total_charges), 2) AS avg_lifetime_revenue,
       ROUND(AVG(CASE WHEN churned = 1 THEN total_charges END), 2) AS avg_lifetime_revenue_churned,
       ROUND(AVG(CASE WHEN churned = 0 THEN total_charges END), 2) AS avg_lifetime_revenue_retained,
       ROUND(100.0 * SUM(CASE WHEN contract = 'Month-to-month' THEN 1 ELSE 0 END) / COUNT(*), 2) AS month_to_month_pct,
       ROUND(100.0 * SUM(CASE WHEN contract = 'Month-to-month' THEN churned ELSE 0 END) / SUM(churned), 2) AS churners_on_month_to_month_pct,
       ROUND(100.0 * SUM(CASE WHEN tenure_months <= 12 THEN churned ELSE 0 END) / SUM(churned), 2) AS churners_in_first_year_pct,
       ROUND(100.0 * SUM(CASE WHEN internet_service = 'Fiber optic' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fiber_pct,
       ROUND(100.0 * AVG(is_senior), 2) AS senior_pct,
       SUM(CASE WHEN tenure_months = 0 THEN 1 ELSE 0 END) AS new_customers_tenure0,
       SUM(dq_charges_mismatch) AS charges_mismatch_customers
FROM v_sub;

-- Q: churn and revenue at risk by contract type
CREATE OR REPLACE TABLE a_churn_by_contract AS
SELECT v.contract, v.contract_term_months,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.contract, v.contract_term_months;

-- Q: churn by tenure band (how long the customer has stayed)
CREATE OR REPLACE TABLE a_churn_by_tenure_band AS
SELECT v.tenure_band,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.tenure_band;

-- Q: churn curve by tenure month (0-72), cross-sectional
CREATE OR REPLACE TABLE a_churn_by_tenure_month AS
SELECT tenure_months, COUNT(*) AS customers, SUM(churned) AS churned,
       ROUND(100.0 * SUM(churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * SUM(CASE WHEN contract = 'Month-to-month' THEN 1 ELSE 0 END) / COUNT(*), 2) AS month_to_month_pct,
       SUM(mrr_lost) AS mrr_lost
FROM v_sub GROUP BY tenure_months;

-- Q: tenure-year cohorts x contract (is the tenure effect just the contract mix?)
CREATE OR REPLACE TABLE a_cohort_tenure_contract AS
SELECT v.tenure_year, v.contract,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.tenure_year, v.contract;

-- Q: churn by payment method
CREATE OR REPLACE TABLE a_churn_by_payment AS
SELECT v.payment_method, v.is_auto_pay,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.payment_method, v.is_auto_pay;

-- Q: churn by internet service
CREATE OR REPLACE TABLE a_churn_by_internet AS
SELECT v.internet_service,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.internet_service;

-- Q: churn by paperless billing
CREATE OR REPLACE TABLE a_churn_by_paperless AS
SELECT v.is_paperless,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.is_paperless;

-- Q: churn by monthly charge band
CREATE OR REPLACE TABLE a_churn_by_charge_band AS
SELECT v.charge_band,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.charge_band;

-- Q: churn by service bundle (phone / internet)
CREATE OR REPLACE TABLE a_churn_by_service_profile AS
SELECT v.service_profile,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.service_profile;

-- Q: churn by number of add-ons (internet customers only; add-ons need internet)
CREATE OR REPLACE TABLE a_churn_by_addon_count AS
SELECT v.addon_count,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
WHERE v.has_internet = 1
GROUP BY v.addon_count;

-- Q: churn by household (partner / dependents)
CREATE OR REPLACE TABLE a_churn_by_household AS
SELECT v.household,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.household;

-- Q: contract x internet service matrix
CREATE OR REPLACE TABLE a_contract_internet_matrix AS
SELECT v.contract, v.internet_service,
       COUNT(*) AS customers, SUM(v.churned) AS churned,
       ROUND(100.0 * SUM(v.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS customer_share_pct,
       ROUND(100.0 * SUM(v.churned) / (SELECT SUM(churned) FROM fact_subscription), 2) AS churner_share_pct,
       SUM(v.monthly_charges) AS mrr, SUM(v.mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(v.mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(v.monthly_charges), 2) AS avg_monthly_charges,
       ROUND(AVG(v.tenure_months), 1) AS avg_tenure_months,
       SUM(v.total_charges) AS lifetime_revenue
FROM v_sub v
GROUP BY v.contract, v.internet_service;

-- Q: churn by add-on, internet customers only (with vs without each add-on)
CREATE OR REPLACE TABLE a_churn_by_addon AS
WITH l AS (
  SELECT 'Online security' AS addon, has_online_security AS has_addon, churned, monthly_charges, mrr_lost FROM v_sub WHERE has_internet = 1
  UNION ALL SELECT 'Online backup', has_online_backup, churned, monthly_charges, mrr_lost FROM v_sub WHERE has_internet = 1
  UNION ALL SELECT 'Device protection', has_device_protection, churned, monthly_charges, mrr_lost FROM v_sub WHERE has_internet = 1
  UNION ALL SELECT 'Tech support', has_tech_support, churned, monthly_charges, mrr_lost FROM v_sub WHERE has_internet = 1
  UNION ALL SELECT 'Streaming TV', has_streaming_tv, churned, monthly_charges, mrr_lost FROM v_sub WHERE has_internet = 1
  UNION ALL SELECT 'Streaming movies', has_streaming_movies, churned, monthly_charges, mrr_lost FROM v_sub WHERE has_internet = 1
)
SELECT addon,
       SUM(has_addon) AS customers_with, SUM(1 - has_addon) AS customers_without,
       ROUND(100.0 * SUM(has_addon) / COUNT(*), 2) AS adoption_pct,
       ROUND(100.0 * SUM(CASE WHEN has_addon = 1 THEN churned ELSE 0 END) / SUM(has_addon), 2) AS churn_rate_with_pct,
       ROUND(100.0 * SUM(CASE WHEN has_addon = 0 THEN churned ELSE 0 END) / SUM(1 - has_addon), 2) AS churn_rate_without_pct,
       ROUND(100.0 * SUM(CASE WHEN has_addon = 1 THEN churned ELSE 0 END) / SUM(has_addon)
           - 100.0 * SUM(CASE WHEN has_addon = 0 THEN churned ELSE 0 END) / SUM(1 - has_addon), 2) AS churn_diff_pp,
       SUM(CASE WHEN has_addon = 0 THEN mrr_lost ELSE 0 END) AS mrr_lost_without
FROM l GROUP BY addon;

-- Q: churn by demographic attribute (long format: dimension, value)
CREATE OR REPLACE TABLE a_churn_by_demographics AS
WITH l AS (
  SELECT 'Gender' AS dimension, gender AS value, churned, monthly_charges, mrr_lost, tenure_months FROM v_sub
  UNION ALL SELECT 'Senior citizen', senior_citizen, churned, monthly_charges, mrr_lost, tenure_months FROM v_sub
  UNION ALL SELECT 'Partner', partner, churned, monthly_charges, mrr_lost, tenure_months FROM v_sub
  UNION ALL SELECT 'Dependents', dependents, churned, monthly_charges, mrr_lost, tenure_months FROM v_sub
)
SELECT dimension, value, COUNT(*) AS customers, SUM(churned) AS churned,
       ROUND(100.0 * SUM(churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2) AS avg_monthly_charges, ROUND(AVG(tenure_months), 1) AS avg_tenure_months,
       SUM(mrr_lost) AS mrr_lost
FROM l GROUP BY dimension, value;

-- Q: single-factor churn drivers - churn rate when the attribute is true vs false (all customers), in points and as a ratio
CREATE OR REPLACE TABLE a_churn_drivers AS
WITH l AS (
  SELECT 'Month-to-month contract' AS factor, CASE WHEN contract = 'Month-to-month' THEN 1 ELSE 0 END AS x, churned FROM v_sub
  UNION ALL SELECT 'Two-year contract', CASE WHEN contract = 'Two year' THEN 1 ELSE 0 END, churned FROM v_sub
  UNION ALL SELECT 'Tenure <= 12 months', CASE WHEN tenure_months <= 12 THEN 1 ELSE 0 END, churned FROM v_sub
  UNION ALL SELECT 'Fiber optic internet', CASE WHEN internet_service = 'Fiber optic' THEN 1 ELSE 0 END, churned FROM v_sub
  UNION ALL SELECT 'No internet service', 1 - has_internet, churned FROM v_sub
  UNION ALL SELECT 'Electronic check', CASE WHEN payment_method = 'Electronic check' THEN 1 ELSE 0 END, churned FROM v_sub
  UNION ALL SELECT 'Automatic payment', is_auto_pay, churned FROM v_sub
  UNION ALL SELECT 'Paperless billing', is_paperless, churned FROM v_sub
  UNION ALL SELECT 'Senior citizen', is_senior, churned FROM v_sub
  UNION ALL SELECT 'Has partner', has_partner, churned FROM v_sub
  UNION ALL SELECT 'Has dependents', has_dependents, churned FROM v_sub
  UNION ALL SELECT 'Online security', has_online_security, churned FROM v_sub
  UNION ALL SELECT 'Tech support', has_tech_support, churned FROM v_sub
  UNION ALL SELECT 'Streaming TV', has_streaming_tv, churned FROM v_sub
  UNION ALL SELECT 'Monthly charge >= $70', CASE WHEN monthly_charges >= 70 THEN 1 ELSE 0 END, churned FROM v_sub
  UNION ALL SELECT 'Male', CASE WHEN gender = 'Male' THEN 1 ELSE 0 END, churned FROM v_sub
)
SELECT factor, SUM(x) AS customers_true, ROUND(100.0 * SUM(x) / COUNT(*), 2) AS prevalence_pct,
       ROUND(100.0 * SUM(x * churned) / SUM(x), 2) AS churn_rate_true_pct,
       ROUND(100.0 * SUM((1 - x) * churned) / SUM(1 - x), 2) AS churn_rate_false_pct,
       ROUND(100.0 * SUM(x * churned) / SUM(x) - 100.0 * SUM((1 - x) * churned) / SUM(1 - x), 2) AS churn_diff_pp,
       ROUND((1.0 * SUM(x * churned) / SUM(x)) / (1.0 * SUM((1 - x) * churned) / SUM(1 - x)), 2) AS churn_ratio
FROM l GROUP BY factor;

-- Q: highest-risk segments (contract x internet x payment, >= 100 customers), ranked by churn rate
CREATE OR REPLACE TABLE a_risk_segments AS
SELECT contract, internet_service, payment_method, COUNT(*) AS customers, SUM(churned) AS churned,
       ROUND(100.0 * SUM(churned) / COUNT(*), 2) AS churn_rate_pct, SUM(mrr_lost) AS mrr_lost,
       ROUND(100.0 * SUM(mrr_lost) / (SELECT SUM(mrr_lost) FROM fact_subscription), 2) AS mrr_lost_share_pct,
       ROUND(AVG(tenure_months), 1) AS avg_tenure_months,
       DENSE_RANK() OVER (ORDER BY 1.0 * SUM(churned) / COUNT(*) DESC) AS risk_rank
FROM v_sub GROUP BY contract, internet_service, payment_method HAVING COUNT(*) >= 100;

-- Q: what churned vs retained customers looked like (revenue, tenure, lifetime value to date)
CREATE OR REPLACE TABLE a_revenue_summary AS
SELECT CASE WHEN churned = 1 THEN 'Churned' ELSE 'Retained' END AS status, COUNT(*) AS customers,
       SUM(monthly_charges) AS mrr, ROUND(100.0 * SUM(monthly_charges) / (SELECT SUM(monthly_charges) FROM fact_subscription), 2) AS mrr_share_pct,
       ROUND(AVG(monthly_charges), 2) AS avg_monthly_charges,
       ROUND(percentile_approx(monthly_charges, 0.5), 2) AS median_monthly_charges,
       ROUND(AVG(tenure_months), 1) AS avg_tenure_months,
       ROUND(percentile_approx(tenure_months, 0.5), 1) AS median_tenure_months,
       SUM(total_charges) AS lifetime_revenue,
       ROUND(AVG(total_charges), 2) AS avg_lifetime_revenue,
       ROUND(percentile_approx(total_charges, 0.5), 2) AS median_lifetime_revenue,
       ROUND(AVG(addon_count), 2) AS avg_addons,
       SUM(12 * monthly_charges) AS annualised_mrr
FROM v_sub GROUP BY churned;

-- Q: service adoption and churn per service line (from fact_service)
CREATE OR REPLACE TABLE a_service_adoption AS
SELECT d.service_group, f.service_name, COUNT(*) AS subscribers,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_subscription), 2) AS adoption_pct,
       SUM(f.churned) AS churned, ROUND(100.0 * SUM(f.churned) / COUNT(*), 2) AS churn_rate_pct
FROM fact_service f JOIN dim_service d ON d.service_name = f.service_name
GROUP BY d.service_group, f.service_name;

-- Integrity view: TotalCharges / (MonthlyCharges x tenure) for billed customers
CREATE OR REPLACE TABLE a_charges_integrity AS
SELECT CASE WHEN c.tenure_months = 0 THEN 'a not billed yet (tenure 0)'
            WHEN c.charges_ratio < 0.75 THEN 'b < 0.75 (flag)' WHEN c.charges_ratio < 0.95 THEN 'c 0.75-0.95'
            WHEN c.charges_ratio <= 1.05 THEN 'd 0.95-1.05' WHEN c.charges_ratio <= 1.25 THEN 'e 1.05-1.25'
            ELSE 'f > 1.25 (flag)' END AS ratio_band,
       COUNT(*) AS customers, SUM(c.churned) AS churned, ROUND(100.0 * SUM(c.churned) / COUNT(*), 2) AS churn_rate_pct,
       ROUND(AVG(c.tenure_months), 1) AS avg_tenure_months
FROM cln_customers c GROUP BY 1;

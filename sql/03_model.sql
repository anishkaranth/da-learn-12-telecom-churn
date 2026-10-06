-- 03_model.sql  Star schema (Spark SQL dialect)
-- Facts: fact_subscription (grain = one customer's current subscription snapshot, 7,043 rows)
--        fact_service      (grain = customer x subscribed service line: phone, extra lines, internet, 6 add-ons)
-- Dims : dim_customer, dim_contract, dim_payment, dim_services (junk dim of service bundles), dim_demographics,
--        dim_tenure_band, dim_service (service catalogue for fact_service).

CREATE OR REPLACE TABLE dim_contract AS
SELECT DENSE_RANK() OVER (ORDER BY contract_term_months) AS contract_key, contract, contract_term_months,
       CASE WHEN contract_term_months = 1 THEN 0 ELSE 1 END AS is_term_contract
FROM (SELECT DISTINCT contract, contract_term_months FROM cln_customers) x;

CREATE OR REPLACE TABLE dim_payment AS
SELECT DENSE_RANK() OVER (ORDER BY payment_method) AS payment_key, payment_method, is_auto_pay,
       CASE WHEN payment_method LIKE '%check%' THEN 'Check' WHEN payment_method LIKE 'Bank%' THEN 'Bank' ELSE 'Card' END AS payment_channel
FROM (SELECT DISTINCT payment_method, is_auto_pay FROM cln_customers) x;

CREATE OR REPLACE TABLE dim_demographics AS
SELECT DENSE_RANK() OVER (ORDER BY gender, is_senior, has_partner, has_dependents) AS demographics_key,
       gender, is_senior, senior_citizen, has_partner, partner, has_dependents, dependents,
       CASE WHEN has_partner = 1 AND has_dependents = 1 THEN 'Partner + dependents' WHEN has_partner = 1 THEN 'Partner, no dependents'
            WHEN has_dependents = 1 THEN 'Dependents, no partner' ELSE 'Single, no dependents' END AS household
FROM (SELECT DISTINCT gender, is_senior, senior_citizen, has_partner, partner, has_dependents, dependents FROM cln_customers) x;

CREATE OR REPLACE TABLE dim_tenure_band AS
SELECT tenure_band, MIN(tenure_months) AS min_tenure_months, MAX(tenure_months) AS max_tenure_months, MIN(tenure_year) AS first_tenure_year
FROM cln_customers GROUP BY tenure_band;

-- Junk dimension: every distinct service bundle that occurs
CREATE OR REPLACE TABLE dim_services AS
SELECT DENSE_RANK() OVER (ORDER BY has_phone, has_multiple_lines, internet_service, has_online_security, has_online_backup,
                          has_device_protection, has_tech_support, has_streaming_tv, has_streaming_movies) AS services_key,
       has_phone, has_multiple_lines, multiple_lines_label, internet_service, has_internet, service_profile,
       has_online_security, has_online_backup, has_device_protection, has_tech_support, has_streaming_tv, has_streaming_movies,
       protection_addons, streaming_addons, addon_count
FROM (SELECT DISTINCT has_phone, has_multiple_lines, multiple_lines_label, internet_service, has_internet, service_profile,
             has_online_security, has_online_backup, has_device_protection, has_tech_support, has_streaming_tv, has_streaming_movies,
             protection_addons, streaming_addons, addon_count FROM cln_customers) x;

CREATE OR REPLACE TABLE dim_customer AS
SELECT customer_id, gender, senior_citizen, partner, dependents, tenure_months, tenure_band, tenure_year,
       contract, payment_method, internet_service, service_profile, is_paperless, churn_label
FROM cln_customers;

CREATE OR REPLACE TABLE fact_subscription AS
SELECT c.customer_id, k.contract_key, p.payment_key, d.demographics_key, s.services_key, c.tenure_band,
       c.tenure_months, c.is_paperless, c.monthly_charges, c.total_charges, c.expected_total_charges, c.avg_billed_per_month,
       c.charge_band, c.addon_count, c.churned, c.mrr_lost, c.mrr_retained,
       CAST(12 * c.mrr_lost AS DECIMAL(12, 2)) AS annualised_revenue_lost,
       c.is_monthly_outlier, c.is_total_outlier, c.dq_total_charges_blank, c.dq_charges_mismatch, c.dq_duplicate_profile
FROM cln_customers c
JOIN dim_contract k ON k.contract = c.contract
JOIN dim_payment p ON p.payment_method = c.payment_method
JOIN dim_demographics d ON d.gender = c.gender AND d.is_senior = c.is_senior AND d.has_partner = c.has_partner AND d.has_dependents = c.has_dependents
JOIN dim_services s ON s.has_phone = c.has_phone AND s.has_multiple_lines = c.has_multiple_lines AND s.internet_service = c.internet_service
 AND s.has_online_security = c.has_online_security AND s.has_online_backup = c.has_online_backup
 AND s.has_device_protection = c.has_device_protection AND s.has_tech_support = c.has_tech_support
 AND s.has_streaming_tv = c.has_streaming_tv AND s.has_streaming_movies = c.has_streaming_movies;

-- Service catalogue + long fact (one row per customer and subscribed service)
CREATE OR REPLACE TABLE fact_service AS
SELECT customer_id, service_name, churned FROM (
  SELECT customer_id, 'Phone' AS service_name, has_phone AS flag, churned FROM cln_customers
  UNION ALL SELECT customer_id, 'Multiple lines', has_multiple_lines, churned FROM cln_customers
  UNION ALL SELECT customer_id, concat('Internet: ', internet_service), has_internet, churned FROM cln_customers
  UNION ALL SELECT customer_id, 'Online security', has_online_security, churned FROM cln_customers
  UNION ALL SELECT customer_id, 'Online backup', has_online_backup, churned FROM cln_customers
  UNION ALL SELECT customer_id, 'Device protection', has_device_protection, churned FROM cln_customers
  UNION ALL SELECT customer_id, 'Tech support', has_tech_support, churned FROM cln_customers
  UNION ALL SELECT customer_id, 'Streaming TV', has_streaming_tv, churned FROM cln_customers
  UNION ALL SELECT customer_id, 'Streaming movies', has_streaming_movies, churned FROM cln_customers
) x WHERE flag = 1;

CREATE OR REPLACE TABLE dim_service AS
SELECT service_name,
       CASE WHEN service_name IN ('Phone', 'Multiple lines') THEN 'Phone'
            WHEN service_name LIKE 'Internet:%' THEN 'Internet access'
            WHEN service_name IN ('Streaming TV', 'Streaming movies') THEN 'Streaming add-on'
            ELSE 'Protection / support add-on' END AS service_group,
       COUNT(*) AS subscribers
FROM fact_service GROUP BY service_name;

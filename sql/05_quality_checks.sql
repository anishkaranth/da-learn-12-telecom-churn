-- 05_quality_checks.sql  Data-quality evidence (Spark SQL dialect): before/after counts, missing values, issues, assertions

CREATE OR REPLACE TABLE dq_row_counts AS
SELECT 'customers' AS entity, (SELECT COUNT(*) FROM stg_telco) AS raw_rows,
       (SELECT COUNT(DISTINCT customer_id_raw) FROM stg_telco) AS distinct_keys,
       (SELECT COUNT(*) FROM cln_customers) AS clean_rows, 'customer_id' AS grain
UNION ALL SELECT 'fact_subscription', NULL, NULL, (SELECT COUNT(*) FROM fact_subscription), 'customer (current subscription snapshot)'
UNION ALL SELECT 'fact_service', NULL, NULL, (SELECT COUNT(*) FROM fact_service), 'customer x subscribed service line'
UNION ALL SELECT 'dim_customer', NULL, NULL, (SELECT COUNT(*) FROM dim_customer), 'customer_id'
UNION ALL SELECT 'dim_contract', NULL, (SELECT COUNT(DISTINCT contract) FROM stg_telco), (SELECT COUNT(*) FROM dim_contract), 'contract type'
UNION ALL SELECT 'dim_payment', NULL, (SELECT COUNT(DISTINCT payment_method) FROM stg_telco), (SELECT COUNT(*) FROM dim_payment), 'payment method'
UNION ALL SELECT 'dim_demographics', NULL, NULL, (SELECT COUNT(*) FROM dim_demographics), 'gender x senior x partner x dependents'
UNION ALL SELECT 'dim_services', NULL, NULL, (SELECT COUNT(*) FROM dim_services), 'distinct service bundle'
UNION ALL SELECT 'dim_tenure_band', NULL, NULL, (SELECT COUNT(*) FROM dim_tenure_band), 'tenure band'
UNION ALL SELECT 'dim_service', NULL, NULL, (SELECT COUNT(*) FROM dim_service), 'service line';

CREATE OR REPLACE TABLE dq_null_rates AS
SELECT 'stg_telco' AS entity, 'TotalCharges (blank string)' AS column_name,
  (SELECT ROUND(100.0 * SUM(CASE WHEN total_charges_raw IS NULL OR trim(total_charges_raw) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_telco) AS raw_missing_pct,
  (SELECT ROUND(100.0 * SUM(CASE WHEN total_charges IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_customers) AS clean_null_pct,
  'all blanks have tenure 0 (never billed) -> 0.00, raw blank kept as dq_total_charges_blank' AS treatment
UNION ALL SELECT 'stg_telco', 'add-ons = ''No internet service''',
  (SELECT ROUND(100.0 * SUM(CASE WHEN trim(online_security) = 'No internet service' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_telco),
  (SELECT ROUND(100.0 * SUM(CASE WHEN has_online_security IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_customers),
  'not missing: a third category; -> flag 0 (has_internet = 0 carries the meaning)'
UNION ALL SELECT 'stg_telco', 'MultipleLines = ''No phone service''',
  (SELECT ROUND(100.0 * SUM(CASE WHEN trim(multiple_lines) = 'No phone service' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_telco),
  (SELECT ROUND(100.0 * SUM(CASE WHEN has_multiple_lines IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_customers),
  'not missing: -> has_multiple_lines 0 (label kept in multiple_lines_label)'
UNION ALL SELECT 'stg_telco', 'any other column',
  (SELECT ROUND(100.0 * SUM(CASE WHEN customer_id_raw IS NULL OR gender IS NULL OR senior_citizen_raw IS NULL OR partner IS NULL
          OR dependents IS NULL OR tenure_raw IS NULL OR phone_service IS NULL OR internet_service IS NULL OR contract IS NULL
          OR paperless_billing IS NULL OR payment_method IS NULL OR monthly_charges_raw IS NULL OR churn_raw IS NULL
          OR trim(monthly_charges_raw) = '' OR trim(tenure_raw) = '' THEN 1 ELSE 0 END) / COUNT(*), 3) FROM stg_telco),
  (SELECT ROUND(100.0 * SUM(CASE WHEN tenure_months IS NULL OR monthly_charges IS NULL OR churned IS NULL OR has_partner IS NULL
          OR has_dependents IS NULL OR has_phone IS NULL OR has_internet IS NULL OR is_paperless IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) FROM cln_customers),
  'no other missing values in the source';

CREATE OR REPLACE TABLE dq_issues AS
SELECT 'exact duplicate rows in raw file' AS check_name,
       (SELECT COUNT(*) FROM stg_telco) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg_telco) x) AS affected_rows
UNION ALL SELECT 'duplicate customer_id dropped', (SELECT COUNT(*) FROM stg_telco) - (SELECT COUNT(*) FROM cln_customers)
UNION ALL SELECT 'TotalCharges blank string (all tenure = 0) -> 0.00', (SELECT SUM(dq_total_charges_blank) FROM cln_customers)
UNION ALL SELECT 'SeniorCitizen 0/1 standardised to is_senior + Yes/No label', (SELECT COUNT(*) FROM stg_telco)
UNION ALL SELECT 'customers with ''No internet service'' in the 6 add-on columns -> flags 0', (SELECT SUM(addon_says_no_internet) FROM cln_customers)
UNION ALL SELECT 'MultipleLines ''No phone service'' -> has_multiple_lines 0', (SELECT COUNT(*) FROM cln_customers WHERE multiple_lines_label = 'No phone service')
UNION ALL SELECT 'InternetService ''No'' renamed ''None''', (SELECT COUNT(*) FROM cln_customers WHERE internet_service = 'None')
UNION ALL SELECT 'TotalCharges off MonthlyCharges x tenure by > 25% (flagged, kept)', (SELECT SUM(dq_charges_mismatch) FROM cln_customers)
UNION ALL SELECT 'TotalCharges below one MonthlyCharges with tenure >= 1 (flagged, kept)', (SELECT SUM(dq_total_below_monthly) FROM cln_customers)
UNION ALL SELECT 'identical 19-attribute profile under different customer ids (synthetic data; kept)', (SELECT SUM(dq_duplicate_profile) FROM cln_customers)
UNION ALL SELECT 'MonthlyCharges outside Q1/Q3 -/+ 1.5*IQR (flagged, kept)', (SELECT SUM(is_monthly_outlier) FROM cln_customers)
UNION ALL SELECT 'TotalCharges outside Q1/Q3 -/+ 1.5*IQR (flagged, kept)', (SELECT SUM(is_total_outlier) FROM cln_customers);

CREATE OR REPLACE TABLE dq_assertions AS
WITH c AS (
  SELECT 'customer_id unique in cln_customers' AS check_name, (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM cln_customers) AS failed_rows
  UNION ALL SELECT 'clean rows = distinct raw customer ids (nothing lost)', (SELECT ABS((SELECT COUNT(*) FROM cln_customers) - (SELECT COUNT(DISTINCT customer_id_raw) FROM stg_telco)))
  UNION ALL SELECT 'fact_subscription rows = cln_customers rows (every dim join matched)', (SELECT ABS((SELECT COUNT(*) FROM fact_subscription) - (SELECT COUNT(*) FROM cln_customers)))
  UNION ALL SELECT 'customer_id format NNNN-XXXXX', (SELECT COUNT(*) FROM cln_customers WHERE NOT regexp_like(customer_id, '^[0-9]{4}-[A-Z]{5}$'))
  UNION ALL SELECT 'every Yes/No column mapped to 0/1 (no NULL flags)',
         (SELECT COUNT(*) FROM cln_customers WHERE has_partner IS NULL OR has_dependents IS NULL OR has_phone IS NULL OR has_multiple_lines IS NULL
            OR has_internet IS NULL OR has_online_security IS NULL OR has_online_backup IS NULL OR has_device_protection IS NULL
            OR has_tech_support IS NULL OR has_streaming_tv IS NULL OR has_streaming_movies IS NULL OR is_paperless IS NULL OR churned IS NULL)
  UNION ALL SELECT 'SeniorCitizen is 0/1 and gender Female/Male', (SELECT COUNT(*) FROM cln_customers WHERE is_senior NOT IN (0, 1) OR gender NOT IN ('Female', 'Male'))
  UNION ALL SELECT 'tenure 0-72 months, MonthlyCharges 18-120', (SELECT COUNT(*) FROM cln_customers WHERE tenure_months NOT BETWEEN 0 AND 72 OR monthly_charges NOT BETWEEN 18 AND 120)
  UNION ALL SELECT 'blank TotalCharges only where tenure = 0', (SELECT COUNT(*) FROM cln_customers WHERE dq_total_charges_blank = 1 AND tenure_months <> 0)
  UNION ALL SELECT 'every tenure-0 customer had a blank TotalCharges', (SELECT COUNT(*) FROM cln_customers WHERE tenure_months = 0 AND dq_total_charges_blank = 0)
  UNION ALL SELECT 'no NULL total_charges after cleaning', (SELECT COUNT(*) FROM cln_customers WHERE total_charges IS NULL)
  UNION ALL SELECT 'tenure 1: TotalCharges = MonthlyCharges', (SELECT COUNT(*) FROM cln_customers WHERE tenure_months = 1 AND total_charges <> monthly_charges)
  UNION ALL SELECT 'TotalCharges within 8 x MonthlyCharges of MonthlyCharges x tenure (price-drift tolerance)',
         (SELECT COUNT(*) FROM cln_customers WHERE tenure_months > 0 AND abs(total_charges - expected_total_charges) > 8 * monthly_charges)
  UNION ALL SELECT '>25% charge gaps (dq_charges_mismatch) only in the first year (tenure <= 12)',
         (SELECT COUNT(*) FROM cln_customers WHERE dq_charges_mismatch = 1 AND tenure_months > 12)
  UNION ALL SELECT 'no internet => all 6 add-on flags 0 and raw add-ons say ''No internet service''',
         (SELECT COUNT(*) FROM cln_customers WHERE (has_internet = 0 AND (addon_count > 0 OR addon_says_no_internet = 0)) OR (has_internet = 1 AND addon_says_no_internet = 1))
  UNION ALL SELECT 'no phone => MultipleLines ''No phone service'' and has_multiple_lines 0',
         (SELECT COUNT(*) FROM cln_customers WHERE (has_phone = 0 AND (has_multiple_lines = 1 OR multiple_lines_label <> 'No phone service')) OR (has_phone = 1 AND multiple_lines_label = 'No phone service'))
  UNION ALL SELECT 'every customer has phone or internet', (SELECT COUNT(*) FROM cln_customers WHERE has_phone = 0 AND has_internet = 0)
  UNION ALL SELECT 'contract / payment / internet values in the expected sets',
         (SELECT COUNT(*) FROM cln_customers WHERE contract NOT IN ('Month-to-month', 'One year', 'Two year')
            OR payment_method NOT IN ('Electronic check', 'Mailed check', 'Bank transfer (automatic)', 'Credit card (automatic)')
            OR internet_service NOT IN ('DSL', 'Fiber optic', 'None'))
  UNION ALL SELECT 'addon_count = sum of the 6 add-on flags (0-6)',
         (SELECT COUNT(*) FROM cln_customers WHERE addon_count <> has_online_security + has_online_backup + has_device_protection + has_tech_support
            + has_streaming_tv + has_streaming_movies OR addon_count NOT BETWEEN 0 AND 6)
  UNION ALL SELECT 'tenure bands cover 0-72 without overlap',
         (SELECT COUNT(*) FROM (SELECT tenure_months FROM cln_customers GROUP BY tenure_months HAVING COUNT(DISTINCT tenure_band) > 1) x)
  UNION ALL SELECT 'MRR reconciles raw -> fact (abs diff < 0.01)',
         (SELECT CASE WHEN abs((SELECT SUM(CAST(monthly_charges_raw AS DOUBLE)) FROM stg_telco) - (SELECT SUM(monthly_charges) FROM fact_subscription)) < 0.01 THEN 0 ELSE 1 END)
  UNION ALL SELECT 'lifetime revenue reconciles raw -> fact (abs diff < 0.01)',
         (SELECT CASE WHEN abs((SELECT SUM(CAST(total_charges_raw AS DOUBLE)) FROM stg_telco WHERE trim(total_charges_raw) <> '') - (SELECT SUM(total_charges) FROM fact_subscription)) < 0.01 THEN 0 ELSE 1 END)
  UNION ALL SELECT 'churned count reconciles raw Churn = Yes', (SELECT ABS((SELECT COUNT(*) FROM stg_telco WHERE trim(churn_raw) = 'Yes') - (SELECT SUM(churned) FROM fact_subscription)))
  UNION ALL SELECT 'mrr_lost + mrr_retained = monthly_charges', (SELECT COUNT(*) FROM fact_subscription WHERE mrr_lost + mrr_retained <> monthly_charges)
  UNION ALL SELECT 'fact_subscription keys -> dims (contract, payment, demographics, services, tenure band)',
         (SELECT COUNT(*) FROM fact_subscription WHERE contract_key NOT IN (SELECT contract_key FROM dim_contract)
            OR payment_key NOT IN (SELECT payment_key FROM dim_payment) OR demographics_key NOT IN (SELECT demographics_key FROM dim_demographics)
            OR services_key NOT IN (SELECT services_key FROM dim_services) OR tenure_band NOT IN (SELECT tenure_band FROM dim_tenure_band))
  UNION ALL SELECT 'fact_service.customer_id -> dim_customer, service -> dim_service',
         (SELECT COUNT(*) FROM fact_service WHERE customer_id NOT IN (SELECT customer_id FROM dim_customer) OR service_name NOT IN (SELECT service_name FROM dim_service))
  UNION ALL SELECT 'fact_service rows = sum of subscribed flags',
         (SELECT ABS((SELECT COUNT(*) FROM fact_service) - (SELECT SUM(has_phone + has_multiple_lines + has_internet + addon_count) FROM cln_customers)))
  UNION ALL SELECT 'segment totals reconcile (contract, tenure band, payment, internet)',
         (SELECT ABS((SELECT SUM(customers) FROM a_churn_by_contract) - (SELECT COUNT(*) FROM fact_subscription))
               + ABS((SELECT SUM(churned) FROM a_churn_by_tenure_band) - (SELECT SUM(churned) FROM fact_subscription))
               + ABS((SELECT SUM(customers) FROM a_churn_by_payment) - (SELECT COUNT(*) FROM fact_subscription))
               + ABS((SELECT SUM(mrr_lost) FROM a_churn_by_internet) - (SELECT SUM(mrr_lost) FROM fact_subscription)))
)
SELECT check_name, failed_rows, CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status FROM c;

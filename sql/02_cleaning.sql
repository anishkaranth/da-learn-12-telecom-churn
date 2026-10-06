-- 02_cleaning.sql  Cleaning (Spark SQL dialect; runs unchanged on DuckDB after sql/00)
-- Steps: trim, dedupe on customer_id, cast types, blank TotalCharges -> 0.00 for never-billed (tenure 0) customers,
--        SeniorCitizen 0/1 -> flag + 'Yes'/'No', every Yes/No column -> 0/1 flag, 'No internet service' /
--        'No phone service' -> 0 flag (label kept), InternetService 'No' -> 'None', derived bands (tenure, tenure year,
--        monthly charge), add-on counts, service profile, revenue fields, IQR outlier flags and integrity flags
--        (TotalCharges vs MonthlyCharges x tenure tolerance, identical attribute profiles under different ids).

-- 1) Typed, standardised customer rows (grain: customer_id). A repeated customer id would be dropped by the QUALIFY
--    (the full file has none; 05 records the count).
CREATE OR REPLACE TABLE cln_customers_base AS
SELECT upper(trim(customer_id_raw)) AS customer_id,
       CASE lower(trim(gender)) WHEN 'female' THEN 'Female' WHEN 'male' THEN 'Male' ELSE 'Unknown' END AS gender,
       CAST(trim(senior_citizen_raw) AS INT) AS is_senior,
       CASE WHEN trim(partner) = 'Yes' THEN 1 WHEN trim(partner) = 'No' THEN 0 END AS has_partner,
       CASE WHEN trim(dependents) = 'Yes' THEN 1 WHEN trim(dependents) = 'No' THEN 0 END AS has_dependents,
       CAST(trim(tenure_raw) AS INT) AS tenure_months,
       CASE WHEN trim(phone_service) = 'Yes' THEN 1 WHEN trim(phone_service) = 'No' THEN 0 END AS has_phone,
       trim(multiple_lines) AS multiple_lines_label,
       CASE WHEN trim(multiple_lines) = 'Yes' THEN 1 WHEN trim(multiple_lines) IN ('No', 'No phone service') THEN 0 END AS has_multiple_lines,
       CASE WHEN trim(internet_service) = 'No' THEN 'None' ELSE trim(internet_service) END AS internet_service,
       CASE WHEN trim(internet_service) IN ('DSL', 'Fiber optic') THEN 1 WHEN trim(internet_service) = 'No' THEN 0 END AS has_internet,
       CASE WHEN trim(online_security) = 'Yes' THEN 1 WHEN trim(online_security) IN ('No', 'No internet service') THEN 0 END AS has_online_security,
       CASE WHEN trim(online_backup) = 'Yes' THEN 1 WHEN trim(online_backup) IN ('No', 'No internet service') THEN 0 END AS has_online_backup,
       CASE WHEN trim(device_protection) = 'Yes' THEN 1 WHEN trim(device_protection) IN ('No', 'No internet service') THEN 0 END AS has_device_protection,
       CASE WHEN trim(tech_support) = 'Yes' THEN 1 WHEN trim(tech_support) IN ('No', 'No internet service') THEN 0 END AS has_tech_support,
       CASE WHEN trim(streaming_tv) = 'Yes' THEN 1 WHEN trim(streaming_tv) IN ('No', 'No internet service') THEN 0 END AS has_streaming_tv,
       CASE WHEN trim(streaming_movies) = 'Yes' THEN 1 WHEN trim(streaming_movies) IN ('No', 'No internet service') THEN 0 END AS has_streaming_movies,
       CASE WHEN trim(online_security) = 'No internet service' OR trim(online_backup) = 'No internet service'
              OR trim(device_protection) = 'No internet service' OR trim(tech_support) = 'No internet service'
              OR trim(streaming_tv) = 'No internet service' OR trim(streaming_movies) = 'No internet service' THEN 1 ELSE 0 END AS addon_says_no_internet,
       trim(contract) AS contract,
       CASE WHEN trim(paperless_billing) = 'Yes' THEN 1 WHEN trim(paperless_billing) = 'No' THEN 0 END AS is_paperless,
       trim(payment_method) AS payment_method,
       CAST(trim(monthly_charges_raw) AS DECIMAL(10, 2)) AS monthly_charges,
       CASE WHEN total_charges_raw IS NULL OR trim(total_charges_raw) = '' THEN 1 ELSE 0 END AS dq_total_charges_blank,
       CAST(CASE WHEN total_charges_raw IS NULL OR trim(total_charges_raw) = '' THEN NULL ELSE trim(total_charges_raw) END AS DECIMAL(12, 2)) AS total_charges_parsed,
       CASE WHEN trim(churn_raw) = 'Yes' THEN 1 WHEN trim(churn_raw) = 'No' THEN 0 END AS churned
FROM stg_telco
WHERE customer_id_raw IS NOT NULL AND trim(customer_id_raw) <> ''
QUALIFY ROW_NUMBER() OVER (PARTITION BY upper(trim(customer_id_raw)) ORDER BY CAST(trim(tenure_raw) AS INT) DESC) = 1;

-- 2) Derived fields, bands, revenue and flags (still customer grain)
CREATE OR REPLACE TABLE cln_customers AS
WITH b AS (
  SELECT c.*,
         -- tenure 0 = joined this month, no bill yet: blank TotalCharges -> 0.00 (raw blank flagged in dq_total_charges_blank)
         CASE WHEN c.dq_total_charges_blank = 1 AND c.tenure_months = 0 THEN CAST(0 AS DECIMAL(12, 2)) ELSE c.total_charges_parsed END AS total_charges,
         c.has_online_security + c.has_online_backup + c.has_device_protection + c.has_tech_support AS protection_addons,
         c.has_streaming_tv + c.has_streaming_movies AS streaming_addons,
         CAST(c.monthly_charges * c.tenure_months AS DECIMAL(12, 2)) AS expected_total_charges
  FROM cln_customers_base c
), q AS (
  SELECT percentile_approx(monthly_charges, 0.25) AS m1, percentile_approx(monthly_charges, 0.75) AS m3,
         percentile_approx(total_charges, 0.25) AS t1, percentile_approx(total_charges, 0.75) AS t3 FROM b
), prof AS (
  -- customers whose 19 non-id attributes are identical to another customer's (synthetic sample data; kept, flagged)
  SELECT customer_id, COUNT(*) OVER (PARTITION BY gender, is_senior, has_partner, has_dependents, tenure_months, has_phone,
           multiple_lines_label, internet_service, has_online_security, has_online_backup, has_device_protection, has_tech_support,
           has_streaming_tv, has_streaming_movies, contract, is_paperless, payment_method, monthly_charges, total_charges, churned) AS profile_copies
  FROM b
)
SELECT b.customer_id, b.gender, b.is_senior,
       CASE WHEN b.is_senior = 1 THEN 'Yes' ELSE 'No' END AS senior_citizen,
       b.has_partner, CASE WHEN b.has_partner = 1 THEN 'Yes' ELSE 'No' END AS partner,
       b.has_dependents, CASE WHEN b.has_dependents = 1 THEN 'Yes' ELSE 'No' END AS dependents,
       b.tenure_months,
       CASE WHEN b.tenure_months <= 6 THEN 'a 0-6 m' WHEN b.tenure_months <= 12 THEN 'b 7-12 m'
            WHEN b.tenure_months <= 24 THEN 'c 13-24 m' WHEN b.tenure_months <= 36 THEN 'd 25-36 m'
            WHEN b.tenure_months <= 48 THEN 'e 37-48 m' WHEN b.tenure_months <= 60 THEN 'f 49-60 m'
            ELSE 'g 61-72 m' END AS tenure_band,
       CASE WHEN b.tenure_months <= 12 THEN 'Y1 0-12' WHEN b.tenure_months <= 24 THEN 'Y2 13-24'
            WHEN b.tenure_months <= 36 THEN 'Y3 25-36' WHEN b.tenure_months <= 48 THEN 'Y4 37-48'
            WHEN b.tenure_months <= 60 THEN 'Y5 49-60' ELSE 'Y6 61-72' END AS tenure_year,
       b.has_phone, b.multiple_lines_label, b.has_multiple_lines,
       b.internet_service, b.has_internet,
       b.has_online_security, b.has_online_backup, b.has_device_protection, b.has_tech_support,
       b.has_streaming_tv, b.has_streaming_movies,
       b.protection_addons, b.streaming_addons, b.protection_addons + b.streaming_addons AS addon_count,
       CASE WHEN b.has_phone = 1 AND b.has_internet = 1 THEN 'Phone + Internet' WHEN b.has_internet = 1 THEN 'Internet only'
            ELSE 'Phone only' END AS service_profile,
       b.contract,
       CASE b.contract WHEN 'Month-to-month' THEN 1 WHEN 'One year' THEN 12 WHEN 'Two year' THEN 24 END AS contract_term_months,
       b.is_paperless, b.payment_method,
       CASE WHEN b.payment_method LIKE '%(automatic)%' THEN 1 ELSE 0 END AS is_auto_pay,
       b.monthly_charges,
       CASE WHEN b.monthly_charges < 30 THEN 'a <$30' WHEN b.monthly_charges < 50 THEN 'b $30-49'
            WHEN b.monthly_charges < 70 THEN 'c $50-69' WHEN b.monthly_charges < 90 THEN 'd $70-89'
            ELSE 'e $90+' END AS charge_band,
       b.total_charges, b.expected_total_charges,
       CASE WHEN b.tenure_months > 0 THEN ROUND(b.total_charges / b.tenure_months, 2) END AS avg_billed_per_month,
       CASE WHEN b.tenure_months > 0 THEN ROUND(b.total_charges / b.expected_total_charges, 4) END AS charges_ratio,
       b.churned, CASE WHEN b.churned = 1 THEN 'Yes' ELSE 'No' END AS churn_label,
       CASE WHEN b.churned = 1 THEN b.monthly_charges ELSE CAST(0 AS DECIMAL(10, 2)) END AS mrr_lost,
       CASE WHEN b.churned = 0 THEN b.monthly_charges ELSE CAST(0 AS DECIMAL(10, 2)) END AS mrr_retained,
       CASE WHEN b.monthly_charges < q.m1 - 1.5 * (q.m3 - q.m1) OR b.monthly_charges > q.m3 + 1.5 * (q.m3 - q.m1) THEN 1 ELSE 0 END AS is_monthly_outlier,
       CASE WHEN b.total_charges < q.t1 - 1.5 * (q.t3 - q.t1) OR b.total_charges > q.t3 + 1.5 * (q.t3 - q.t1) THEN 1 ELSE 0 END AS is_total_outlier,
       b.dq_total_charges_blank,
       -- integrity: lifetime billing should be close to the current monthly price x tenure (prices drift, add-ons change)
       CASE WHEN b.tenure_months > 0 AND abs(b.total_charges - b.expected_total_charges) > 0.25 * b.expected_total_charges THEN 1 ELSE 0 END AS dq_charges_mismatch,
       CASE WHEN b.tenure_months > 0 AND b.total_charges < b.monthly_charges THEN 1 ELSE 0 END AS dq_total_below_monthly,
       CASE WHEN p.profile_copies > 1 THEN 1 ELSE 0 END AS dq_duplicate_profile,
       b.addon_says_no_internet
FROM b
JOIN prof p ON p.customer_id = b.customer_id
CROSS JOIN q;

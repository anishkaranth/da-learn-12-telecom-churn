-- 01_staging.sql
-- Land the raw CSV as an all-STRING staging table (no type inference), one row per CUSTOMER, snake_case names.
-- {{RAW_DIR}} is substituted by run_pipeline.py.
-- DuckDB : read_csv(path, header = true, all_varchar = true)
-- Spark  : read_files('<path>/WA_Fn-UseC_-Telco-Customer-Churn.csv', format => 'csv', header => true, inferColumnTypes => false)
-- WA_Fn-UseC_-Telco-Customer-Churn.csv: 7,043 rows x 21 columns (CRLF line endings). Quirks kept verbatim here and fixed in 02:
--   TotalCharges is text and holds a single blank ' ' for the 11 customers with tenure = 0 (never billed yet);
--   SeniorCitizen is 0/1 while every other flag is 'Yes'/'No'; the six internet add-ons say 'No internet service' and
--   MultipleLines says 'No phone service' instead of 'No'; InternetService uses 'No' for "no internet at all".
CREATE OR REPLACE TABLE stg_telco AS
SELECT customerID       AS customer_id_raw,
       gender,
       SeniorCitizen    AS senior_citizen_raw,
       Partner          AS partner,
       Dependents       AS dependents,
       tenure           AS tenure_raw,
       PhoneService     AS phone_service,
       MultipleLines    AS multiple_lines,
       InternetService  AS internet_service,
       OnlineSecurity   AS online_security,
       OnlineBackup     AS online_backup,
       DeviceProtection AS device_protection,
       TechSupport      AS tech_support,
       StreamingTV      AS streaming_tv,
       StreamingMovies  AS streaming_movies,
       Contract         AS contract,
       PaperlessBilling AS paperless_billing,
       PaymentMethod    AS payment_method,
       MonthlyCharges   AS monthly_charges_raw,
       TotalCharges     AS total_charges_raw,
       Churn            AS churn_raw
FROM read_csv('{{RAW_DIR}}/WA_Fn-UseC_-Telco-Customer-Churn.csv', header = true, all_varchar = true);

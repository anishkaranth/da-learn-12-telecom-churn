"""Project-specific settings used by run_pipeline.py (raw files, star / clean tables, JSON.shot content)."""
NAME = "da-learn-12-telecom-churn"
DATASET = ("Telco Customer Churn (IBM Sample Data Sets; Kaggle blastchar/telco-customer-churn, licence listed as "
           "'Data files (c) Original Authors'; WA_Fn-UseC_-Telco-Customer-Churn.csv, 7,043 customers x 21 columns, 977,501 B)")
RAW_FILES = ["WA_Fn-UseC_-Telco-Customer-Churn.csv"]
STAR = ["fact_subscription", "fact_service", "dim_customer", "dim_contract", "dim_payment", "dim_demographics",
        "dim_services", "dim_tenure_band", "dim_service"]
CLEAN = ["cln_customers"]
METRIC_TABLES = ["a_churn_by_contract", "a_churn_by_tenure_band", "a_churn_by_tenure_month", "a_cohort_tenure_contract",
                 "a_churn_by_payment", "a_churn_by_internet", "a_churn_by_paperless", "a_churn_by_charge_band",
                 "a_churn_by_service_profile", "a_churn_by_addon_count", "a_churn_by_household", "a_contract_internet_matrix",
                 "a_churn_by_addon", "a_churn_by_demographics", "a_churn_drivers", "a_risk_segments", "a_revenue_summary",
                 "a_service_adoption", "a_charges_integrity"]


def build_shot(q, kpi):
    """Headline snapshot written to results/JSON.shot."""
    return {
        "config": {"sql_dialect": "Spark SQL style (+ DuckDB shims in sql/00), run on DuckDB",
                   "grain": "fact_subscription = one customer (current subscription snapshot); fact_service = customer x subscribed service",
                   "churn": "Churn = 'Yes' (left within the last month); churn rate = churned / customers",
                   "revenue_at_risk": "sum of MonthlyCharges of churned customers (mrr_lost); x12 = annualised",
                   "lifetime_revenue": "TotalCharges billed to date (CLV-to-date proxy, no margin data)",
                   "cleaning": "TotalCharges ' ' (tenure 0) -> 0.00; SeniorCitizen 0/1 + Yes/No label; Yes/No -> 0/1; "
                               "'No internet service' / 'No phone service' -> 0; InternetService 'No' -> 'None'",
                   "integrity_rule": "|TotalCharges - MonthlyCharges x tenure| > 25% of the expected value -> dq_charges_mismatch (kept)",
                   "outlier_rule": "MonthlyCharges / TotalCharges outside Q1/Q3 -/+ 1.5*IQR (flagged, kept)",
                   "sample_rule": "data/raw: crc32(customerID) % 5 = 0 plus every anomaly row (scripts/make_sample.py)"},
        "headline": kpi,
        "contract": q("SELECT contract, customers, churned, churn_rate_pct, mrr_lost, mrr_lost_share_pct FROM a_churn_by_contract ORDER BY contract_term_months"),
        "tenure_band": q("SELECT tenure_band, customers, churn_rate_pct, mrr_lost FROM a_churn_by_tenure_band ORDER BY tenure_band"),
        "payment": q("SELECT payment_method, customers, churn_rate_pct, mrr_lost FROM a_churn_by_payment ORDER BY churn_rate_pct DESC"),
        "internet": q("SELECT internet_service, customers, churn_rate_pct, avg_monthly_charges, mrr_lost FROM a_churn_by_internet ORDER BY churn_rate_pct DESC"),
        "addons_internet_customers": q("SELECT addon, adoption_pct, churn_rate_with_pct, churn_rate_without_pct, churn_diff_pp FROM a_churn_by_addon ORDER BY churn_diff_pp"),
        "demographics": q("SELECT dimension, value, customers, churn_rate_pct FROM a_churn_by_demographics ORDER BY dimension, value"),
        "top_risk_segments": q("SELECT contract, internet_service, payment_method, customers, churn_rate_pct, mrr_lost FROM a_risk_segments ORDER BY risk_rank, customers DESC LIMIT 5"),
        "churned_vs_retained": q("SELECT * FROM a_revenue_summary ORDER BY status"),
    }

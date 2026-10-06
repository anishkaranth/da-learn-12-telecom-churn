# Data layout

| Path | What | In git |
|---|---|---|
| `raw/WA_Fn-UseC_-Telco-Customer-Churn.csv` | 1,477 raw customers (208,269 B), original 21 columns; header, CRLF line endings and the blank `' '` TotalCharges values copied byte-for-byte from the full file. Rule in `scripts/make_sample.py`: every customer whose `zlib.crc32(customerID) % 5 = 0`, plus every anomaly row (blank TotalCharges / tenure 0, TotalCharges more than 25% away from MonthlyCharges × tenure, identical 19-attribute profiles under different ids), so every cleaning rule is exercised. Anomalies are over-represented, so sample KPIs (in `../results/sample/`) are not population estimates. | yes |
| `raw_full/WA_Fn-UseC_-Telco-Customer-Churn.csv` | the full Kaggle file: 7,043 customers × 21 columns, 977,501 B, SHA-256 `88be4b93fbe0cc83421af1c503794c97c342eca914c1576db7c276e61d61358a`, from `python scripts/download_full_data.py` | no (download) |
| `orig/` | untouched downloaded original (same bytes) | no |
| `clean/customers.csv` | cleaned customers from `python run_pipeline.py --source full`: 7,043 rows, one per customer, typed, standardised, banded and flagged (`cln_customers`, 1.5 MB) | yes (full size) |
| `clean/star/` | star-schema CSVs (identical copies are committed in `../powerbi/data/`) | no |

## Columns of the raw file (Kaggle `WA_Fn-UseC_-Telco-Customer-Churn.csv`)
`customerID` (`7590-VHVEG`), `gender` (Female / Male), `SeniorCitizen` (**0/1**, unlike every other flag), `Partner`, `Dependents` (Yes/No), `tenure` (months with the company, 0-72), `PhoneService` (Yes/No), `MultipleLines` (Yes / No / **No phone service**), `InternetService` (DSL / Fiber optic / **No**), `OnlineSecurity`, `OnlineBackup`, `DeviceProtection`, `TechSupport`, `StreamingTV`, `StreamingMovies` (Yes / No / **No internet service**), `Contract` (Month-to-month / One year / Two year), `PaperlessBilling` (Yes/No), `PaymentMethod` (Electronic check / Mailed check / Bank transfer (automatic) / Credit card (automatic)), `MonthlyCharges` (USD, 18.25-118.75), `TotalCharges` (USD billed to date, **text; `' '` for the 11 tenure-0 customers**), `Churn` (Yes = left within the last month).

It is a fictional telco (IBM sample data): one snapshot of 7,043 customers, no dates, no costs and no reason for leaving.

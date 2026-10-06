# Dashboard spec - "da-learn-12 Telecom churn"

One page, 16:9. Slicers: contract (dim_contract), internet service (dim_services[internet_service]), payment method (dim_payment), tenure band (dim_tenure_band), senior citizen (dim_demographics), churn label (dim_customer). Optional second page for add-ons, demographics and data quality.

| # | Visual | Fields | Expected (full data, no filters) |
|---|---|---|---|
| 1 | KPI cards | Customers, Churned Customers, Churn Rate %, MRR, MRR Lost (+ MRR Lost %), Annualised Revenue Lost, Median Tenure Churned / Retained | 7,043 / 1,869 / 26.54% / $456,116.60 / $139,130.85 (30.50%) / $1,669,570.20 / 10 / 38 |
| 2 | Column: churn by contract | dim_contract[contract], [Churn Rate %], tooltip [Customers], [MRR Lost] | Month-to-month 42.71%, One year 11.27%, Two year 2.83% |
| 3 | Column: churn by tenure band | dim_tenure_band[tenure_band], [Churn Rate %] | 0-6 m 52.94% … 61-72 m 6.61% |
| 4 | Line: churn by tenure month, legend contract | fact_subscription[tenure_months], [Churn Rate %] | month 1 61.99% (613 customers) |
| 5 | Column: churn by internet service | dim_services[internet_service], [Churn Rate %], tooltip [Avg Monthly Charge] | Fiber optic 41.89%, DSL 18.96%, None 7.40% |
| 6 | Bar: churn by payment method | dim_payment[payment_method], [Churn Rate %] | Electronic check 45.29%, Mailed check 19.11%, Bank transfer 16.71%, Credit card 15.24% |
| 7 | Clustered column: add-on effect (filter has_internet = 1) | add-on flag, [Churn Rate %] | Online security 14.61% with vs 41.77% without; Tech support 15.17% vs 41.64% |
| 8 | Bar: MRR lost by contract × internet | dim_contract[contract] + dim_services[internet_service], [MRR Lost] | Month-to-month / Fiber optic $100,482.00 (72.22% of MRR lost) |
| 9 | Matrix: risk segments | contract × internet × payment, [Customers], [Churn Rate %], [MRR Lost Share %] | M2M / Fiber / Electronic check: 1,307 customers, 60.37%, 49.08% |
| 10 | Clustered column: demographics (page 2) | Senior / Partner / Dependents Yes vs No, [Churn Rate %] | Senior 41.68% vs 23.61%; Partner 19.66% vs 32.96%; Dependents 15.45% vs 31.28% |

Reference render of the same visuals (from DuckDB): `results/images/dashboard.png` and the individual PNGs in `results/images/`.

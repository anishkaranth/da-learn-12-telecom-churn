# Build guide (Power BI Desktop, Windows)

No `.pbix` is committed: this repo is built on Linux and Power BI Desktop runs on Windows only.

1. `python scripts/download_full_data.py` then `python run_pipeline.py --source full` (or just use the committed `powerbi/data/*.csv`, which are already full size, ~2.2 MB total).
2. Power BI Desktop > Get data > Text/CSV: load the nine CSVs in `powerbi/data/` (UTF-8). In Power Query set `customer_id`, `tenure_band`, `charge_band`, `service_name` and all label columns to **Text**; `*_key`, `tenure_months`, `addon_count`, counts and all `is_*` / `has_*` / `dq_*` / `churned` columns to Whole number; `monthly_charges`, `total_charges`, `expected_total_charges`, `avg_billed_per_month`, `mrr_lost`, `mrr_retained`, `annualised_revenue_lost` to Fixed decimal (currency).
3. Model view: create the relationships in `model.md` (many-to-one, single direction; customer_id one-to-one to dim_customer).
4. New measures: paste `measures.dax` one measure at a time (subscription measures into fact_subscription, service measures into fact_service).
5. Build the page in `dashboard_spec.md` and check the cards against the "Expected" column; they come from `results/metrics.json` and `results/tables/`.
6. Optional: conditional formatting on [Churn Rate vs Average (pts)] (red above 0) for the bar visuals, as in the reference PNGs.
7. Save as `da-learn-12-telecom-churn.pbix` locally (do not commit the binary unless you want to).

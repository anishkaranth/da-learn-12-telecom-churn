-- 00_duckdb_compat.sql  (DuckDB ONLY)
-- Spark SQL function shims so that 01-05 can be written in Spark SQL dialect and still execute unchanged on DuckDB.
-- On Spark/Databricks these functions are built in.
-- Spark percentile_approx returns an actual value near the percentile; DuckDB quantile_cont is the exact interpolated
-- percentile. For tenure (whole months) and charges (2 dp) on 7,043 customers they agree to within a cent / a month.
CREATE OR REPLACE MACRO percentile_approx(x, p) AS quantile_cont(x, p);
-- Spark: regexp_like(str, pattern) (alias of RLIKE).
CREATE OR REPLACE MACRO regexp_like(s, p) AS regexp_matches(s, p);

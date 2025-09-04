-- quality_checks.sql
SELECT COUNT(*) AS raw_rows FROM ds_jobs_raw;
SELECT COUNT(*) AS staging_rows FROM ds_jobs_staging;
SELECT COUNT(*) AS final_rows FROM ds_jobs_staging2;

/* ---------------------------------------------------------------
   Data Cleaning Script: Glassdoor Data Science Jobs
   Author: Farshid Maleki | GitHub: github.com/Farshid89
   Database: PostgreSQL 12+
   ---------------------------------------------------------------
   Purpose:
   - Clean and standardize the raw Glassdoor job postings dataset
   - Handle duplicates, missing values, inconsistent formats
   - Extract structured fields (salary ranges, location, HQ info)
   - Categorize revenue into labeled buckets for analysis
   ---------------------------------------------------------------
   Workflow:
   1) Create staging table from raw
   2) Remove duplicate rows (keep lowest idx)
   3) Extract min/max salary from "$###K-$###K" (and single "$###K")
   4) Clean company names (remove embedded newlines)
   5) Split location and headquarters into city/state/country
   6) Normalize placeholders ('-1', 'Unknown') to NULL
   7) Categorize revenue into A–L, Z=Unknown
   8) Produce a slimmer, typed final table
   --------------------------------------------------------------- */
-- 0) Staging from raw
DROP TABLE IF EXISTS ds_jobs_staging;
CREATE TABLE ds_jobs_staging AS TABLE ds_jobs_raw;

SELECT * FROM ds_jobs_staging;

BEGIN;

-- 1) Remove exact duplicates (keep lowest idx in each group)
WITH ranked AS (
  SELECT idx,
    ROW_NUMBER() OVER (
      PARTITION BY job_title, salary_estimate, job_description, rating,
                   company_name, location, headquarters, size, founded,
                   type_of_ownership, industry, revenue, competitors
      ORDER BY idx
    ) AS rn
  FROM ds_jobs_staging
),
to_delete AS (
SELECT idx FROM ranked WHERE rn > 1
)
DELETE FROM ds_jobs_staging s
USING to_delete d
WHERE s.idx = d.idx;

-- 2) Add simple job column
ALTER TABLE ds_jobs_staging
ADD COLUMN simple_job TEXT;

SELECT DISTINCT job_title FROM ds_jobs_staging ORDER BY 1;

UPDATE ds_jobs_staging
SET simple_job = CASE
	WHEN job_title ILIKE '%manager%' THEN 'manager'
	WHEN job_title ILIKE '%data analyst%' THEN 'analyst'
	WHEN job_title ILIKE '%data scientist%' THEN 'data scientist'
	WHEN job_title ILIKE '%data science%' THEN 'data scientist'
	WHEN job_title ILIKE '%data engineer%' THEN 'data engineer'
	WHEN job_title ILIKE '%machine learning%' THEN 'ml'
	WHEN job_title ILIKE '%data analysis%' THEN 'analyst'
	WHEN job_title ILIKE '%Scientist%' THEN 'data scientist'
	WHEN job_title ILIKE '%analyst%' THEN 'analyst'
	WHEN job_title ILIKE '%data modeler%' THEN 'data engineer'
	WHEN job_title ILIKE '%engineer%' THEN 'data engineer'
	ELSE null
END;
SELECT DISTINCT job_title, simple_job FROM ds_jobs_staging ORDER BY 1;

-- 3) Salary extraction (min/max) from "$137K-$171K (…)" and single "$60K (…)" and add average salary

ALTER TABLE ds_jobs_staging
	ADD COLUMN min_salary integer,
	ADD COLUMN max_salary integer;
	ADD COLUMN avg_salary integer;
	
SELECT * FROM ds_jobs_staging;

UPDATE ds_jobs_staging
SET
  min_salary = COALESCE(
                 (regexp_match(salary_estimate, '([0-9]+)\s*K\D+([0-9]+)\s*K'))[1]::int,
                 (regexp_match(salary_estimate, '([0-9]+)\s*K'))[1]::int
               ) * 1000,
  max_salary = COALESCE(
                 (regexp_match(salary_estimate, '([0-9]+)\s*K\D+([0-9]+)\s*K'))[2]::int,
                 (regexp_match(salary_estimate, '([0-9]+)\s*K'))[1]::int
               ) * 1000
WHERE salary_estimate ~ '[0-9]';

UPDATE ds_jobs_staging
SET avg_salary = ROUND((min_salary + max_salary)/ 2.0)
WHERE min_salary IS NOT NULL AND max_salary IS NOT NULL;

-- 4) Company name: remove embedded newlines (replace with a space)
UPDATE ds_jobs_staging
SET company_name = replace(replace(company_name, E'\r', ''), E'\n', ' ');

-- 5) Location & headquarters split

ALTER TABLE ds_jobs_staging
  ADD COLUMN location_city  text,
  ADD COLUMN location_state text,
  ADD COLUMN headquarter_city    text,
  ADD COLUMN headquarter_state   text,
  ADD COLUMN headquarter_country text;

-- Normalize a few one-word/US-only locations to "City, ST"
UPDATE ds_jobs_staging SET location = 'California, CA' WHERE location = 'California';
UPDATE ds_jobs_staging SET location = 'New Jersey, NJ' WHERE location = 'New Jersey';
UPDATE ds_jobs_staging SET location = 'Remote, Remote'  WHERE location = 'Remote';
UPDATE ds_jobs_staging SET location = 'Texas City, TX'  WHERE location = 'Texas';
UPDATE ds_jobs_staging SET location = 'Utah, UT'        WHERE location = 'Utah';

-- Split "City, ST" → city/state (skip plain "United States")
UPDATE ds_jobs_staging
SET location_city  = NULLIF(split_part(location, ',', 1), ''),
    location_state = NULLIF(btrim(split_part(location, ',', 2)), '')
WHERE location <> 'United States';

UPDATE ds_jobs_staging
SET location_state = NULL
WHERE location = 'United States';

-- Headquarters: decide if last part is a 2-letter state or a country
UPDATE ds_jobs_staging
SET headquarter_country = CASE
        WHEN length(btrim(split_part(headquarters, ',', 2))) > 2
             THEN btrim(split_part(headquarters, ',', 2))
        ELSE 'United States'
    END,
    headquarter_state = CASE
        WHEN length(btrim(split_part(headquarters, ',', 2))) = 2
             THEN btrim(split_part(headquarters, ',', 2))
        ELSE NULL
    END,
    headquarter_city = NULLIF(btrim(split_part(headquarters, ',', 1)), '');

-- Treat '-1' placeholders as NULLs
UPDATE ds_jobs_staging
SET headquarter_city = NULL,
    headquarter_state = NULL,
    headquarter_country = NULL
WHERE headquarters = '-1';

-- Fix odd code you observed
UPDATE ds_jobs_staging
SET headquarter_country = 'United States'
WHERE headquarter_country = '061';

-- 5) Size normalization
UPDATE ds_jobs_staging
SET size = CASE
    WHEN size IN ('-1','Unknown') THEN NULL
    ELSE replace(size, ' employees', '')
END;

-- 6) Normalize other placeholders to NULL
UPDATE ds_jobs_staging SET founded = NULL WHERE founded = -1;
UPDATE ds_jobs_staging SET type_of_ownership = NULL WHERE type_of_ownership IN ('-1','Unknown');
UPDATE ds_jobs_staging SET industry = NULL WHERE industry = '-1';
UPDATE ds_jobs_staging SET sector   = NULL WHERE sector   = '-1';
UPDATE ds_jobs_staging SET competitors = NULL WHERE competitors = '-1';
UPDATE ds_jobs_staging SET rating = NULL WHERE rating = '-1';

-- 7) Revenue → buckets (A highest … L lowest, Z unknown)
ALTER TABLE ds_jobs_staging ADD COLUMN revenue_category char(1);

UPDATE ds_jobs_staging
SET revenue_category = CASE
  WHEN revenue LIKE '$10+ billion (USD)%'                 THEN 'A'
  WHEN revenue LIKE '$5 to $10 billion (USD)%'            THEN 'B'
  WHEN revenue LIKE '$2 to $5 billion (USD)%'             THEN 'C'
  WHEN revenue LIKE '$1 to $2 billion (USD)%'             THEN 'D'
  WHEN revenue LIKE '$500 million to $1 billion (USD)%'   THEN 'E'
  WHEN revenue LIKE '$100 to $500 million (USD)%'         THEN 'F'
  WHEN revenue LIKE '$50 to $100 million (USD)%'          THEN 'G'
  WHEN revenue LIKE '$25 to $50 million (USD)%'           THEN 'H'
  WHEN revenue LIKE '$10 to $25 million (USD)%'           THEN 'I'
  WHEN revenue LIKE '$5 to $10 million (USD)%'            THEN 'J'
  WHEN revenue LIKE '$1 to $5 million (USD)%'             THEN 'K'
  WHEN revenue LIKE 'Less than $1 million (USD)%'         THEN 'L'
  WHEN revenue LIKE 'Unknown%' OR revenue = '-1'          THEN 'Z'
  ELSE NULL
END;

-- 8) Final slim table with tighter types
DROP TABLE IF EXISTS ds_jobs_staging2;
CREATE TABLE ds_jobs_staging2
AS TABLE ds_jobs_staging;

-- Drop unused wide/raw columns
ALTER TABLE ds_jobs_staging2
  DROP COLUMN salary_estimate,
  DROP COLUMN location,
  DROP COLUMN headquarters;

-- Tighten types (safe USING casts where needed)
ALTER TABLE ds_jobs_staging2
  ALTER COLUMN idx         TYPE integer USING idx::integer,
  ALTER COLUMN rating      TYPE numeric(3,1) USING NULLIF(rating::text,'')::numeric,
  ALTER COLUMN founded     TYPE integer USING founded::integer;

COMMIT;

SELECT * FROM ds_jobs_staging2



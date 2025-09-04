# 🧹 Data Science Jobs — Cleaning Pipeline (PostgreSQL)

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-blue)
![ETL](https://img.shields.io/badge/Process-ETL%20Cleaning-success)
![Regex](https://img.shields.io/badge/Regex-Salary%20Parsing-orange)
![Portfolio](https://img.shields.io/badge/Project-Portfolio-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

This project demonstrates a **full SQL cleaning pipeline** applied to a messy Glassdoor-style Data Science jobs dataset.  
It covers staging, deduplication, regex salary extraction, text normalization, splitting location/HQ fields, placeholder handling, revenue bucketing, and producing a slim typed table for analysis.

---

## ✨ Highlights
- **Staging workflow** → raw data stays untouched  
- **Duplicate removal** using `ROW_NUMBER()`  
- **Regex salary parsing** → `min_salary`, `max_salary`, `avg_salary`  
- **Feature engineering**:
  - Job family classification (`simple_job`)
  - Location split: `location_city`, `location_state`
  - HQ split: `headquarter_city`, `headquarter_state`, `headquarter_country`
  - Revenue categorized into **A–L** (Z = Unknown)
- **Data quality fixes**:
  - Convert `-1` and `Unknown` placeholders to `NULL`
  - Remove embedded newlines in company names
  - Normalize size field

---

## 📊 Before vs After

**Raw data (before cleaning):**

![Before cleaning](images/before.png)

**Cleaned data (after cleaning):**

![After cleaning](images/after.png)

---

## ▶️ How to Run (PostgreSQL 12+)

# 1. Create target database
createdb ds_jobs

# 2. Create raw table
psql -d ds_jobs -c "
CREATE TABLE ds_jobs_raw (
  idx int,
  job_title text,
  salary_estimate text,
  job_description text,
  rating text,
  company_name text,
  location text,
  headquarters text,
  size text,
  founded int,
  type_of_ownership text,
  industry text,
  sector text,
  revenue text,
  competitors text
);"

# 3. Load raw data
\copy ds_jobs_raw FROM 'data/raw/Uncleaned_DS_jobs.csv' CSV HEADER

# 4. Run cleaning pipeline
psql -d ds_jobs -f sql/cleaning.sql

# 5. Run validation
psql -d ds_jobs -f sql/quality_checks.sql

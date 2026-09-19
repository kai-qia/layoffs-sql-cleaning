# World Layoffs — SQL Data Cleaning

Cleaning a dataset of tech layoffs from March 2020 to March 2023 in MySQL. The raw CSV had duplicates, inconsistent spellings, dates stored as text and missing values, so none of it was really queryable as-is.

**Tools:** MySQL 8.0 · MySQL Workbench

---

## The data

Source: [layoffs.csv](https://github.com/AlexTheAnalyst/MySQL-YouTube-Series/blob/main/layoffs.csv)

`company` · `location` · `industry` · `total_laid_off` · `percentage_laid_off` · `date` · `stage` · `country` · `funds_raised_millions`

---

## What I fixed

### Duplicates

No id column, so a duplicate here means a row identical across all nine columns. `ROW_NUMBER()` partitioned by every column numbers the copies inside each group, so anything past 1 is a duplicate:

```sql
ROW_NUMBER() OVER (
    PARTITION BY company, location, industry, total_laid_off,
                 percentage_laid_off, `date`, stage, country,
                 funds_raised_millions
) AS row_num
```

MySQL won't let you `DELETE` out of a CTE, so I wrote those row numbers into a second table and deleted from there.

### Messy text

Company names with leading spaces. `Crypto`, `Crypto Currency` and `CryptoCurrency` sitting there as three separate industries. `United States` and `United States.` as two separate countries. Any of these splits one group into several in a `GROUP BY`.

### Dates stored as text

The `date` column imported as `TEXT`, so it sorted alphabetically and no date functions worked on it.

```sql
UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;
```

### Missing industries

Some rows had `NULL`, some had empty strings — same thing, but only one of them shows up in `IS NULL`. Set the blanks to `NULL` first, then backfilled from the same company's other rows with a self-join on company and location.

### Empty rows

Rows with no value for either `total_laid_off` or `percentage_laid_off` say nothing about the size of the layoff, so I dropped them.

---

## Files

```
├── 01_data_cleaning.sql    the whole pipeline
└── data/
    └── layoffs.csv         raw data
```

Every destructive statement in the script has the `SELECT` I used to check it right above it. The original `layoffs` table never gets touched — everything runs on copies, so the whole thing re-runs from the import.

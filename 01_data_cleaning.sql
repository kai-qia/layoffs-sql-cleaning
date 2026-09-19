/* ============================================================================
   WORLD LAYOFFS - DATA CLEANING
   ----------------------------------------------------------------------------
   Dataset : layoffs.csv  (tech layoffs, Mar 2020 - Mar 2023)
   Engine  : MySQL 8.0 (MySQL Workbench)

   Goal: turn the raw import into a table that can actually be analyzed.

   Pipeline:
     0. Create a working copy of the raw table
     1. Remove duplicate rows
     2. Standardize inconsistent text and fix data types
     3. Handle nulls and blanks
     4. Drop unusable rows and helper columns

   Note: the raw `layoffs` table is never modified. All work happens on copies,
   so the import can be re-run from scratch at any point.
============================================================================ */


/* ============================================================================
   STEP 0 - WORKING COPY
   ----------------------------------------------------------------------------
   CREATE TABLE ... LIKE copies the structure only (columns, types, indexes),
   not the rows. The INSERT then fills it.
============================================================================ */

CREATE TABLE layoffs_staging
LIKE layoffs;

INSERT INTO layoffs_staging
SELECT *
FROM layoffs;

-- Check: row count should match the raw table
SELECT COUNT(*) FROM layoffs;
SELECT COUNT(*) FROM layoffs_staging;


/* ============================================================================
   STEP 1 - REMOVE DUPLICATES
   ----------------------------------------------------------------------------
   There is no primary key or unique id, so a duplicate can only be defined as
   a row identical across every column. ROW_NUMBER() partitioned by all nine
   columns numbers the copies within each identical group: the first copy gets
   1, any extras get 2 or higher.

   Partitioning on all nine columns matters. A narrower partition (company +
   industry + date, say) would flag genuinely different events as duplicates -
   the same company laying off staff in two different countries, for example.
============================================================================ */

-- Diagnostic: which rows are duplicates?
WITH duplicate_cte AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY company, location, industry, total_laid_off,
                            percentage_laid_off, `date`, stage, country,
                            funds_raised_millions
           ) AS row_num
    FROM layoffs_staging
)
SELECT *
FROM duplicate_cte
WHERE row_num > 1;

-- Spot-check one of the flagged companies to confirm the rows really are
-- identical, rather than two separate layoff events being collapsed.
SELECT *
FROM layoffs_staging
WHERE company = 'Casper';

/* MySQL cannot DELETE from a CTE, so the row numbers are written into a real
   table instead. layoffs_staging2 is layoffs_staging plus one extra column,
   row_num - which makes the delete an ordinary delete. */

CREATE TABLE `layoffs_staging2` (
  `company`               TEXT,
  `location`              TEXT,
  `industry`              TEXT,
  `total_laid_off`        INT DEFAULT NULL,
  `percentage_laid_off`   TEXT,
  `date`                  TEXT,
  `stage`                 TEXT,
  `country`               TEXT,
  `funds_raised_millions` INT DEFAULT NULL,
  `row_num`               INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO layoffs_staging2
SELECT *,
       ROW_NUMBER() OVER (
           PARTITION BY company, location, industry, total_laid_off,
                        percentage_laid_off, `date`, stage, country,
                        funds_raised_millions
       ) AS row_num
FROM layoffs_staging;

-- Confirm the delete targets before running it
SELECT * FROM layoffs_staging2 WHERE row_num > 1;

DELETE
FROM layoffs_staging2
WHERE row_num > 1;

-- Should now return zero rows
SELECT * FROM layoffs_staging2 WHERE row_num > 1;


/* ============================================================================
   STEP 2 - STANDARDIZE TEXT AND FIX DATA TYPES
============================================================================ */

-- --- Whitespace ------------------------------------------------------------
-- Several company names carry leading spaces, which would split one company
-- into two groups in any later GROUP BY.

SELECT company, TRIM(company)
FROM layoffs_staging2
WHERE company <> TRIM(company);

UPDATE layoffs_staging2
SET company = TRIM(company);


-- --- Industry --------------------------------------------------------------
-- 'Crypto', 'Crypto Currency' and 'CryptoCurrency' are the same industry
-- recorded three ways. Collapsed to 'Crypto'.

SELECT DISTINCT industry
FROM layoffs_staging2
ORDER BY 1;

UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';


-- --- Country ---------------------------------------------------------------
-- 'United States' and 'United States.' (trailing period) appear as separate
-- countries.

SELECT DISTINCT country
FROM layoffs_staging2
ORDER BY 1;

UPDATE layoffs_staging2
SET country = TRIM(TRAILING '.' FROM country)
WHERE country LIKE 'United States%';


-- --- Date ------------------------------------------------------------------
-- The date column imported as TEXT, so it sorts alphabetically rather than
-- chronologically and no date functions work on it. Converted to a real DATE.

SELECT `date`, STR_TO_DATE(`date`, '%m/%d/%Y')
FROM layoffs_staging2;

UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;


/* ============================================================================
   STEP 3 - NULLS AND BLANKS
============================================================================ */

-- Blank strings and NULLs both mean "missing" here, but only one of them is
-- visible to IS NULL. Standardize on NULL first so the backfill below catches
-- every missing value.

UPDATE layoffs_staging2
SET industry = NULL
WHERE industry = '';

SELECT *
FROM layoffs_staging2
WHERE industry IS NULL;

/* Some companies appear several times, with industry recorded on some rows
   and missing on others - Airbnb is one. The missing values can be filled in
   from the company's own populated rows via a self-join. */

SELECT *
FROM layoffs_staging2
WHERE company = 'Airbnb';

-- Diagnostic: preview what the self-join will match
SELECT t1.company, t1.location, t1.industry AS missing, t2.industry AS fill_from
FROM layoffs_staging2 t1
JOIN layoffs_staging2 t2
     ON  t1.company  = t2.company
     AND t1.location = t2.location
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;

/* The join matches on company AND location. Matching on company alone risks
   pulling an industry from a different office of the same company, which is
   not guaranteed to be the same industry. */

UPDATE layoffs_staging2 t1
JOIN layoffs_staging2 t2
     ON  t1.company  = t2.company
     AND t1.location = t2.location
SET t1.industry = t2.industry
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;

-- Anything still NULL is a company that appears only once with no industry
-- recorded, so there is nothing to backfill from. Left as NULL.
SELECT DISTINCT company
FROM layoffs_staging2
WHERE industry IS NULL;


/* ============================================================================
   STEP 4 - DROP UNUSABLE ROWS AND HELPER COLUMN
============================================================================ */

/* Rows with neither total_laid_off nor percentage_laid_off carry no
   information about the size of the layoff, which is the whole point of the
   dataset. They cannot be imputed from anything else here, so they are
   removed rather than kept as noise. */

SELECT *
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

DELETE
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

-- row_num has done its job; every remaining value is 1.
ALTER TABLE layoffs_staging2
DROP COLUMN row_num;


/* ============================================================================
   FINAL CHECK
============================================================================ */

SELECT COUNT(*) AS final_row_count
FROM layoffs_staging2;

SELECT *
FROM layoffs_staging2
LIMIT 20;

-- layoffs_staging2 is the cleaned table used for the analysis in
-- 02_exploratory_analysis.sql
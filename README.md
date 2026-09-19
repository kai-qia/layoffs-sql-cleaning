# World Layoffs — SQL Data Cleaning

Cleaning a raw dataset of tech layoffs (March 2020 – March 2023) in MySQL, turning a messy CSV import into a table that can actually be queried.

> Built by following along with Alex The Analyst's SQL data cleaning series, then extended with my own checks and notes. <!-- TODO: edit or delete this line depending on how you worked through it -->

## Dataset

- **Source:** <!-- TODO: link to where you got layoffs.csv -->
- **Rows (raw):** <!-- TODO --> · **Rows (cleaned):** <!-- TODO -->
- **Columns:** company, location, industry, total_laid_off, percentage_laid_off, date, stage, country, funds_raised_millions

## Files

| File | What it does |
|---|---|
| `01_data_cleaning.sql` | The full cleaning pipeline, with the diagnostic queries used to make each decision |
| `data/layoffs.csv` | The raw dataset, as imported |

## What was wrong with the data

**Duplicate rows.** No primary key or unique id, so duplicates could only be identified as rows identical across all nine columns. Used `ROW_NUMBER()` partitioned by every column to number copies within each identical group, then deleted anything numbered higher than 1.

**Inconsistent text.** Leading whitespace on company names. `Crypto`, `Crypto Currency` and `CryptoCurrency` recorded as three separate industries. `United States` and `United States.` recorded as two separate countries. All of these would have split a single group into several in any later aggregation.

**Dates stored as text.** The `date` column imported as `TEXT`, so it sorted alphabetically instead of chronologically and no date functions worked on it. Converted with `STR_TO_DATE()` and the column type changed to `DATE`.

**Missing industry values, two ways.** Some rows had `NULL`, others had an empty string — meaning the same thing but behaving differently in queries. Standardized to `NULL`, then backfilled from the same company's other rows using a self-join on company *and* location.

**Rows with no layoff figures.** Rows missing both `total_laid_off` and `percentage_laid_off` say nothing about the size of the layoff and can't be imputed from anything else in the table. Removed.

## Approach

The raw `layoffs` table is never modified. Everything happens on staging copies, so the whole pipeline can be re-run from the original import.

Every destructive statement is preceded by the `SELECT` used to confirm what it would affect. Those diagnostics are left in the script deliberately — they're the reasoning, not clutter.

## Things I'd still change

- `percentage_laid_off` is still stored as `TEXT` and should be a numeric type
- A handful of companies appear once with no industry recorded and nothing to backfill from, so those remain `NULL`
- No unique constraint added, so re-running the import could reintroduce duplicates

## Next

Exploratory analysis on the cleaned table — hardest-hit industries, layoffs over time, and companies that shut down entirely (`percentage_laid_off = 1`).

<!-- TODO: delete the line above and replace with your findings once 02_exploratory_analysis.sql exists -->

-- World Layoffs: Exploratory Analysis
-- Runs against layoffs_staging2, the cleaned table from 01_data_cleaning.sql


-- Date range covered by the data
SELECT MIN(`date`) AS first_layoff,
       MAX(`date`) AS last_layoff
FROM layoffs_staging2;


-- Largest single layoff, and the largest share of a workforce cut
SELECT MAX(total_laid_off)      AS biggest_single_layoff,
       MAX(percentage_laid_off) AS largest_share_cut
FROM layoffs_staging2;


-- Companies that shut down entirely (100% laid off),
-- ordered by how much funding they had raised first
SELECT company, location, industry, total_laid_off, funds_raised_millions
FROM layoffs_staging2
WHERE percentage_laid_off = 1
ORDER BY funds_raised_millions DESC;


-- Total laid off by company
SELECT company, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY company
ORDER BY 2 DESC;


-- Total laid off by industry
SELECT industry, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY industry
ORDER BY 2 DESC;


-- Total laid off by country
SELECT country, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY country
ORDER BY 2 DESC;


-- Total laid off by funding stage
SELECT stage, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY stage
ORDER BY 2 DESC;


-- Total laid off by year
SELECT YEAR(`date`) AS years, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
WHERE `date` IS NOT NULL
GROUP BY years
ORDER BY 1 DESC;


-- Total laid off by month
SELECT DATE_FORMAT(`date`, '%Y-%m') AS month,
       SUM(total_laid_off)          AS total_laid_off
FROM layoffs_staging2
WHERE `date` IS NOT NULL
GROUP BY month
ORDER BY month ASC;


-- Rolling total by month.
-- The CTE collapses to one row per month, then SUM() OVER (ORDER BY month)
-- accumulates down the list, so each row is that month plus every month before it.
WITH Monthly_Totals AS (
    SELECT DATE_FORMAT(`date`, '%Y-%m') AS month,
           SUM(total_laid_off)          AS total_laid_off
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
    GROUP BY month
)
SELECT month,
       total_laid_off,
       SUM(total_laid_off) OVER (ORDER BY month ASC) AS rolling_total
FROM Monthly_Totals
ORDER BY month ASC;


-- Total laid off by company and year
SELECT company,
       YEAR(`date`)        AS years,
       SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY company, years
ORDER BY 3 DESC;


-- Top 5 companies by layoffs in each year.
-- The first CTE aggregates to company/year, the second ranks within each year.
-- The ranking needs its own CTE because WHERE runs before window functions,
-- so it can't be filtered in the same query that computes it.
-- DENSE_RANK so two companies tied at 2 don't push the next one to 4.
WITH Company_Year (company, years, total_laid_off) AS (
    SELECT company, YEAR(`date`), SUM(total_laid_off)
    FROM layoffs_staging2
    GROUP BY company, YEAR(`date`)
),
Company_Year_Rank AS (
    SELECT *,
           DENSE_RANK() OVER (PARTITION BY years ORDER BY total_laid_off DESC) AS ranking
    FROM Company_Year
    WHERE years IS NOT NULL
)
SELECT company, years, total_laid_off, ranking
FROM Company_Year_Rank
WHERE ranking <= 5
ORDER BY years ASC, ranking ASC;
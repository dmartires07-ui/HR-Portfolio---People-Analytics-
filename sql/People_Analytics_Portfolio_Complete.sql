/*
PEOPLE ANALYTICS | SQL PORTFOLIO
PostgreSQL script: database structure, validation and workforce analysis

Dataset: Synthetic People Analytics training dataset
Database used in the project: people_analytics_portfolio
Interface: pgAdmin 4

IMPORTANT:
- This script documents the schema and SQL queries used in the project.
- Import the six source CSV files into the matching tables before running analysis queries.
- Run the script in sections, in the order shown.
- The script does not create or import the database itself.
- Results describe a synthetic training dataset, not a real organisation.
- Employee-level identifiers should be masked in any public screenshots.

Suggested execution order:
1. Schema (run only when creating the tables for the first time)
2. Data-quality validation
3. Workforce analysis
*/

-- =========================================================
-- 1. DATABASE STRUCTURE (DDL)
-- =========================================================
-- The schema separates employee-level records, HR movement
-- events and descriptive lookup dimensions.
-- The original project checked referential integrity with
-- validation queries; foreign-key constraints are not added here.


CREATE TABLE dim_department (
    department_key INT PRIMARY KEY,
    department VARCHAR(100)
);

CREATE TABLE dim_job_role (
    job_role_key INT PRIMARY KEY,
    job_role VARCHAR(100),
    department_key INT
);

CREATE TABLE dim_location (
    location_key INT PRIMARY KEY,
    location VARCHAR(100)
);

CREATE TABLE dim_date (
    date DATE PRIMARY KEY,
    year INT,
    quarter VARCHAR(10),
    month_number INT,
    month_name VARCHAR(20),
    year_month VARCHAR(10),
    month_start DATE
);

CREATE TABLE dim_employee (
    employee_id VARCHAR(20) PRIMARY KEY,
    gender VARCHAR(30),
    birth_date DATE,
    hire_date DATE,
    termination_date DATE,
    department_key INT,
    job_role_key INT,
    location_key INT,
    employment_type VARCHAR(50),
    annual_salary_eur NUMERIC(12,2),
    performance_rating INT,
    satisfaction_score INT,
    age_at_2025_year_end INT,
    tenure_at_2025_year_end_years NUMERIC(6,2)
);

CREATE TABLE fact_hr_movement (
    event_id VARCHAR(20) PRIMARY KEY,
    employee_id VARCHAR(20),
    event_date DATE,
    event_type VARCHAR(30),
    department_key INT,
    job_role_key INT,
    location_key INT
);


-- =========================================================
-- 2. DATA-QUALITY VALIDATION
-- =========================================================


-- 5.1 Employee-to-dimension reference validation
-- Checks whether employee records contain department, job-role or location keys that do not match their lookup tables.
SELECT
    COUNT(*) FILTER (WHERE d.department_key IS NULL) AS invalid_departments,
    COUNT(*) FILTER (WHERE j.job_role_key IS NULL) AS invalid_job_roles,
    COUNT(*) FILTER (WHERE l.location_key IS NULL) AS invalid_locations
FROM dim_employee e
LEFT JOIN dim_department d ON e.department_key = d.department_key
LEFT JOIN dim_job_role j ON e.job_role_key = j.job_role_key
LEFT JOIN dim_location l ON e.location_key = l.location_key;


-- 5.2 Fact-table validation
-- Checks event count, invalid employee references, unexpected event types and missing event dates.
SELECT
    COUNT(*) AS total_events,
    COUNT(*) FILTER (WHERE e.employee_id IS NULL) AS invalid_employee_references,
    COUNT(*) FILTER (
        WHERE event_type NOT IN ('Hire', 'Termination')
    ) AS unexpected_event_types,
    COUNT(*) FILTER (WHERE event_date IS NULL) AS missing_event_dates
FROM fact_hr_movement f
LEFT JOIN dim_employee e ON f.employee_id = e.employee_id;


-- =========================================================
-- 3. WORKFORCE ANALYSIS
-- =========================================================


-- 4.1 Headcount by department
-- Counts employee records by department. Unless filtered for active employees, this includes both current and former employees.
SELECT d.department, COUNT(e.employee_id) AS headcount
FROM dim_employee e
INNER JOIN dim_department d ON e.department_key = d.department_key
GROUP BY d.department
ORDER BY headcount DESC;


-- 4.2 Average salary by department
-- Compares average recorded annual salary across departments. The query includes all employee records unless an employment-status filter is added.
SELECT d.department, ROUND(AVG(e.annual_salary_eur), 2) AS average_salary
FROM dim_employee e
INNER JOIN dim_department d ON e.department_key = d.department_key
GROUP BY d.department
ORDER BY average_salary DESC;


-- 4.3 Terminations by department
-- Counts termination events and groups them by department.
SELECT d.department, COUNT(*) AS total_terminations
FROM fact_hr_movement f
INNER JOIN dim_department d ON f.department_key = d.department_key
WHERE f.event_type = 'Termination'
GROUP BY d.department
ORDER BY total_terminations DESC;


-- 4.4 Hiring trends by year
-- Groups hire events by calendar year.
SELECT EXTRACT(YEAR FROM event_date) AS hiring_year, COUNT(*) AS total_hires
FROM fact_hr_movement
WHERE event_type = 'Hire'
GROUP BY EXTRACT(YEAR FROM event_date)
ORDER BY hiring_year;


-- 4.5 Average satisfaction by department
-- Compares average satisfaction and the number of employee records in each department.
SELECT d.department,
       ROUND(AVG(e.satisfaction_score), 2) AS average_satisfaction,
       COUNT(e.employee_id) AS employees
FROM dim_employee e
INNER JOIN dim_department d ON e.department_key = d.department_key
GROUP BY d.department
ORDER BY average_satisfaction DESC;


-- 4.6 Department salary compared with company average
-- Uses a CTE and CROSS JOIN to compare each department's average salary with the overall company average.
WITH company_average AS (
    SELECT AVG(annual_salary_eur) AS avg_salary
    FROM dim_employee
)
SELECT d.department,
       ROUND(AVG(e.annual_salary_eur), 2) AS department_average,
       ROUND(c.avg_salary, 2) AS company_average,
       ROUND(AVG(e.annual_salary_eur) - c.avg_salary, 2) AS difference
FROM dim_employee e
INNER JOIN dim_department d ON e.department_key = d.department_key
CROSS JOIN company_average c
GROUP BY d.department, c.avg_salary
ORDER BY difference DESC;


-- 4.7 Salary ranking within department
-- Demonstrates the RANK window function and PARTITION BY. Employee identifiers should be handled carefully in a public portfolio; consider masking them in screenshots.
SELECT e.employee_id, d.department, e.annual_salary_eur,
       RANK() OVER (
           PARTITION BY d.department
           ORDER BY e.annual_salary_eur DESC
       ) AS salary_rank
FROM dim_employee e
INNER JOIN dim_department d ON e.department_key = d.department_key
ORDER BY d.department, salary_rank;


-- 4.8 Average tenure by department (dynamic to current date)
-- Calculates elapsed tenure in years. Because CURRENT_DATE is dynamic, results change over time for employees without a termination date. For a fixed reporting snapshot, use a fixed cutoff date instead.
SELECT d.department,
       ROUND(AVG((COALESCE(e.termination_date, CURRENT_DATE) - e.hire_date) / 365.25)::NUMERIC, 2)
           AS average_tenure_years
FROM dim_employee e
INNER JOIN dim_department d ON e.department_key = d.department_key
GROUP BY d.department
ORDER BY average_tenure_years DESC;


-- 4.9 Terminations by department during 2025
-- Filters termination events to the 2025 calendar year using an inclusive start and exclusive end date.
SELECT d.department, COUNT(*) AS terminations_2025
FROM fact_hr_movement f
INNER JOIN dim_department d ON f.department_key = d.department_key
WHERE f.event_type = 'Termination'
  AND f.event_date >= '2025-01-01'
  AND f.event_date < '2026-01-01'
GROUP BY d.department
ORDER BY terminations_2025 DESC;


-- 4.10 Beginning, ending and average headcount for 2025
-- Estimates average headcount as the mean of beginning and ending headcount. This is a simplified approach; monthly average headcount is often preferable when monthly snapshots are available.
WITH headcount AS (
    SELECT
        COUNT(*) FILTER (
            WHERE hire_date < '2025-01-01'
              AND (termination_date IS NULL OR termination_date >= '2025-01-01')
        ) AS beginning_headcount,
        COUNT(*) FILTER (
            WHERE hire_date < '2026-01-01'
              AND (termination_date IS NULL OR termination_date >= '2026-01-01')
        ) AS ending_headcount
    FROM dim_employee
)
SELECT beginning_headcount, ending_headcount,
       ROUND((beginning_headcount + ending_headcount) / 2.0, 2) AS average_headcount
FROM headcount;


-- 4.11 Overall turnover rate for 2025
-- Calculates annual termination events divided by average headcount. The result obtained was 14.08%. Confirm the organisation's turnover definition before comparing this metric with external benchmarks.
WITH terminations AS (
    SELECT COUNT(*) AS total_terminations
    FROM fact_hr_movement
    WHERE event_type = 'Termination'
      AND event_date >= '2025-01-01'
      AND event_date < '2026-01-01'
),
headcount AS (
    SELECT (
        COUNT(*) FILTER (
            WHERE hire_date < '2025-01-01'
              AND (termination_date IS NULL OR termination_date >= '2025-01-01')
        )
        +
        COUNT(*) FILTER (
            WHERE hire_date < '2026-01-01'
              AND (termination_date IS NULL OR termination_date >= '2026-01-01')
        )
    ) / 2.0 AS average_headcount
    FROM dim_employee
)
SELECT t.total_terminations,
       ROUND(h.average_headcount, 2) AS average_headcount,
       ROUND(t.total_terminations * 100.0 /
             NULLIF(h.average_headcount, 0), 2) AS turnover_rate_percentage
FROM terminations t CROSS JOIN headcount h;


-- 4.12 Turnover rate by department for 2025
-- Calculates department-level turnover using department-specific average headcount and termination counts.
WITH department_headcount AS (
    SELECT department_key,
        COUNT(*) FILTER (
            WHERE hire_date < '2025-01-01'
              AND (termination_date IS NULL OR termination_date >= '2025-01-01')
        ) AS beginning_headcount,
        COUNT(*) FILTER (
            WHERE hire_date < '2026-01-01'
              AND (termination_date IS NULL OR termination_date >= '2026-01-01')
        ) AS ending_headcount
    FROM dim_employee
    GROUP BY department_key
),
department_terminations AS (
    SELECT department_key, COUNT(*) AS total_terminations
    FROM fact_hr_movement
    WHERE event_type = 'Termination'
      AND event_date >= '2025-01-01'
      AND event_date < '2026-01-01'
    GROUP BY department_key
)
SELECT d.department,
       COALESCE(t.total_terminations, 0) AS terminations,
       ROUND((h.beginning_headcount + h.ending_headcount) / 2.0, 2) AS average_headcount,
       ROUND(COALESCE(t.total_terminations, 0) * 100.0 /
             NULLIF((h.beginning_headcount + h.ending_headcount) / 2.0, 0), 2)
             AS turnover_rate_percentage
FROM department_headcount h
INNER JOIN dim_department d ON h.department_key = d.department_key
LEFT JOIN department_terminations t ON h.department_key = t.department_key
ORDER BY turnover_rate_percentage DESC NULLS LAST;


-- 4.13 Satisfaction by employment status
-- Compares average satisfaction between active and former employee records. Similar averages do not establish why employees left.
SELECT
    CASE
        WHEN termination_date IS NULL THEN 'Active'
        ELSE 'Former'
    END AS employment_status,
    COUNT(*) AS employees,
    ROUND(AVG(satisfaction_score), 2) AS average_satisfaction
FROM dim_employee
GROUP BY employment_status
ORDER BY employment_status;


-- 4.14 Tenure by employment status using the 2025 snapshot
-- Uses the precomputed year-end-2025 tenure field. The observed averages were 2.43 years for active employees and 1.58 years for former employees.
SELECT
    CASE
        WHEN termination_date IS NULL THEN 'Active'
        ELSE 'Former'
    END AS employment_status,
    COUNT(*) AS employees,
    ROUND(AVG(tenure_at_2025_year_end_years), 2) AS average_tenure_years
FROM dim_employee
GROUP BY employment_status
ORDER BY employment_status;


-- 4.15 Early attrition among former employees
-- The observed result was 97 former employees, 38 with the snapshot tenure measure below one year (39.18%). Caution: the field is tenure at 2025 year-end, not necessarily exact tenure at the employee's exit date. Validate against hire and termination dates before making a definitive early-attrition claim.
SELECT
    COUNT(*) AS former_employees,
    COUNT(*) FILTER (
        WHERE tenure_at_2025_year_end_years < 1
    ) AS left_within_one_year,
    ROUND(
        COUNT(*) FILTER (WHERE tenure_at_2025_year_end_years < 1) * 100.0
        / NULLIF(COUNT(*), 0), 2
    ) AS percentage
FROM dim_employee
WHERE termination_date IS NOT NULL;


-- =========================================================
-- 4. INTERPRETATION AND LIMITATIONS
-- =========================================================
-- - The dataset is synthetic and does not represent a real employer.
-- - Several department headcount and salary queries include all
--   employee records (active and former) unless explicitly filtered.
-- - The 2025 turnover calculation uses the average of beginning
--   and ending headcount; monthly average headcount may be more robust.
-- - The early-attrition query uses tenure at 2025 year-end, not
--   necessarily exact tenure at the employee's exit date.
-- - Salary and satisfaction comparisons are descriptive and do not
--   establish causation or prove pay inequity.
-- - Re-run data-quality checks whenever the source data changes.

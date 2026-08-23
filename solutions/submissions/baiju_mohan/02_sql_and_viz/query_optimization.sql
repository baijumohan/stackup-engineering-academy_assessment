-- =============================================================================
-- StackUp Engineering Academy — Data Engineering Assessment
-- Solution File: query_optimization.sql
-- Pillar: SQL & Data Visualization (Task 2.3) — Query optimisation
-- Author: Baiju Mohan | Engine: DuckDB
-- =============================================================================
--
-- PREREQUISITES
-- -------------
-- Uses plain employees/projects/transactions tables, not data_model.sql's
-- star schema. Needs employees_clean.csv, projects_clean.csv,
-- transactions_clean.csv on disk first — the setup block below loads them.
--
-- HOW TO USE
-- ----------
-- Substitute __RESULTS__ with the real outputs path and run in any SQL
-- client, or via run_optimization.py (does the substitution + benchmarks).
--
-- RESULT SUMMARY: at this scale (1,000 employees / 500 projects / 50,000
-- transactions), original and rewritten both run ~6-7ms on DuckDB — no
-- 10x+ speedup here. See 4a for why, and 4c for where it'd matter.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Setup — plain unindexed tables matching the starter query's table names
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE employees AS SELECT * FROM read_csv_auto('__RESULTS__/employees_clean.csv');
CREATE OR REPLACE TABLE projects AS SELECT * FROM read_csv_auto('__RESULTS__/projects_clean.csv');
CREATE OR REPLACE TABLE transactions AS SELECT * FROM read_csv_auto('__RESULTS__/transactions_clean.csv');


-- ---------------------------------------------------------------------------
-- ORIGINAL QUERY (unmodified from the starter file)
-- ---------------------------------------------------------------------------
SELECT
    e.full_name,
    e.department,
    e.role,
    p.project_name,
    p.status,
    p.budget,
    p.actual_cost,
    t.amount,
    t.category,
    t.payment_status,
    t.transaction_date
FROM employees e, projects p, transactions t
WHERE e.employee_id = p.project_manager_id
AND   p.project_id  = t.project_id
AND   p.status NOT IN ('Completed', 'On Hold')
AND   t.payment_status = 'Pending'
AND   t.amount > (
        SELECT AVG(amount)
        FROM transactions
        WHERE payment_status = 'Pending'
      )
ORDER BY e.department, t.amount DESC;


-- ---------------------------------------------------------------------------
-- 4a) EXPLAIN ANALYZE — original query, real captured output
-- ---------------------------------------------------------------------------
-- Total Time: 0.0074s (7.4ms) -> 923 rows returned
--   ORDER_BY (department ASC, amount DESC)              0.00s   923 rows
--     HASH_JOIN employee_id = project_manager_id         0.00s   923 rows
--       TABLE_SCAN employees                              0.00s   147 rows
--         Dynamic Filters: employee_id BETWEEN 'EMP0002' AND 'EMP0991'
--       HASH_JOIN project_id = project_id                  0.00s   923 rows
--         TABLE_SCAN projects                               0.00s   239 rows
--           Filters: status NOT IN ('Completed','On Hold')
--         NESTED_LOOP_JOIN amount > SUBQUERY                 0.00s 2,127 rows
--           TABLE_SCAN transactions                           0.00s 2,127 rows
--             Filters: payment_status='Pending'
--             Dynamic Filters: amount > 64552.30  (subquery result, already
--                                                   resolved to a constant)
--           UNGROUPED_AGGREGATE avg(amount)                   0.00s     1 row
--             TABLE_SCAN transactions (payment_status='Pending')  8,927 rows
--
-- Bottleneck analysis:
--   1. Join bottleneck? None — every join is 0.00s. The 7.4ms is scan I/O
--      on transactions, not join cost.
--   2. Correlated subquery re-run per row? No — AVG(amount) doesn't
--      reference the outer query, so DuckDB evaluates it once and folds
--      it into a literal filter (a single UNGROUPED_AGGREGATE node).
--   3. Missing indexes? DuckDB uses zone maps + dynamic filters instead
--      of B-tree indexes here, so no — 4c covers a Postgres deployment.
--   4. Implicit FROM A,B,C is still risky (a dropped WHERE silently
--      becomes a cartesian product), even though DuckDB's optimizer
--      already produces the same hash-join plan. Rewritten in 4b anyway.


-- ---------------------------------------------------------------------------
-- 4b) REWRITTEN QUERY
-- ---------------------------------------------------------------------------
-- 4 changes (none move the needle on DuckDB — see 4d — but they're the
-- right shape for a row-oriented production database):
--   1. Implicit FROM A,B,C -> explicit JOIN...ON
--   2. Subquery -> CTE
--   3. Status filter pushed onto JOIN...ON (early predicate pushdown)
--   4. No SELECT * — every column named
WITH pending_avg AS (
    SELECT AVG(amount) AS avg_pending_amount
    FROM transactions
    WHERE payment_status = 'Pending'
)
SELECT
    e.full_name,
    e.department,
    e.role,
    p.project_name,
    p.status,
    p.budget,
    p.actual_cost,
    t.amount,
    t.category,
    t.payment_status,
    t.transaction_date
FROM transactions t
JOIN projects p
    ON p.project_id = t.project_id
    AND p.status NOT IN ('Completed', 'On Hold')
JOIN employees e
    ON e.employee_id = p.project_manager_id
CROSS JOIN pending_avg
WHERE t.payment_status = 'Pending'
  AND t.amount > pending_avg.avg_pending_amount
ORDER BY e.department, t.amount DESC;


-- ---------------------------------------------------------------------------
-- 4c) Indexes — for a production PostgreSQL deployment
-- ---------------------------------------------------------------------------
-- DuckDB doesn't need these (see 4a.3), but the task frames this as a
-- query run "hundreds of times a day" in production — these target that.

-- Speeds up the manager->employee join + status filter. status listed
-- second — it's the lower-selectivity predicate (4 values).
CREATE INDEX idx_projects_manager_status ON projects (project_manager_id, status);

-- Speeds up the project_id join + payment_status filter. payment_status
-- first, so Postgres can seek the ~18% Pending rows before the join.
CREATE INDEX idx_transactions_status_project ON transactions (payment_status, project_id);

-- employee_id is already this table's PK in a real deployment — no new
-- index needed there.

-- Trade-off: write overhead on INSERT/UPDATE for read speed on a
-- read-heavy, high-frequency query — worth it here. Wouldn't index a
-- low-query-value column like `notes`.


-- ---------------------------------------------------------------------------
-- 4d) Benchmark — rewritten query, real captured output
-- ---------------------------------------------------------------------------
-- 0.0060-0.0077s across 5 runs — same as the original's steady state
-- (~7ms). Same physical plan as 4a — DuckDB's optimizer already found it
-- for the original syntax.
--
-- With the 4c indexes: 0.0063-0.0072s, 923 rows — still no change,
-- confirming the bottleneck is scan I/O, not joins or missing indexes.
--
-- Where this WOULD show 10x+: production volume (10-50M rows, where the
-- 4c indexes start mattering), or an engine that re-evaluates a
-- correlated subquery per row — 4b's CTE stays fast either way.

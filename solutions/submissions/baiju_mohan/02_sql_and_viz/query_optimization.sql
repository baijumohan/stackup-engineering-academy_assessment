-- =============================================================================
-- StackUp Engineering Academy — Data Engineering Assessment
-- Solution File: query_optimization.sql
-- Pillar: SQL & Data Visualization (Task 2.3) — Query optimisation
-- Author: Baiju Mohan | Engine: PostgreSQL 15
-- =============================================================================
--
-- SCENARIO
-- --------
-- A query used on the finance dashboard, run hundreds of times a day, is
-- slow. Diagnose it, rewrite it, and add indexes where they'd help in
-- production.
--
-- This was first measured on DuckDB, where the rewrite and indexes showed
-- no real speedup (1.03x — DuckDB is columnar with zone maps, so it
-- doesn't need a B-tree index to skip rows cheaply). That result was
-- reasoned about but not left unverified: it's tested here for real
-- against PostgreSQL, a genuine row-store, to check whether the reasoning
-- actually holds on the kind of engine the production indexes are written
-- for.
--
-- HOW TO RUN
-- ----------
-- Uses the presight-postgres container already defined in docker-compose.yml
-- (docker-compose up -d postgres) — against a dedicated presight_practice
-- database, not the airflow metadata database that container also hosts.
-- COPY below is server-side, so the CSVs need to exist inside the container
-- first (run_optimization.py does all of this automatically):
--
--   docker cp outputs/results/baiju_mohan/01_foundations/employees_clean.csv presight-postgres:/tmp/employees_clean.csv
--   docker cp outputs/results/baiju_mohan/01_foundations/projects_clean.csv   presight-postgres:/tmp/projects_clean.csv
--   docker cp outputs/results/baiju_mohan/02_sql_and_viz/transactions_clean.csv presight-postgres:/tmp/transactions_clean.csv
--   docker exec presight-postgres psql -U presight -d postgres -c "CREATE DATABASE presight_practice;"
--   docker exec -i presight-postgres psql -U presight -d presight_practice -f - < solutions/submissions/baiju_mohan/02_sql_and_viz/query_optimization.sql
-- =============================================================================

\timing on

-- ---------------------------------------------------------------------------
-- Setup — plain unindexed tables matching the starter query's table names
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS employees, projects, transactions;

CREATE TABLE employees (
    employee_id             TEXT,
    full_name                TEXT,
    email                     TEXT,
    department                 TEXT,
    role                        TEXT,
    level                         TEXT,
    hire_date                      DATE,
    salary                           NUMERIC,
    manager_id                        TEXT,
    region                              TEXT,
    status                               TEXT,
    years_experience                      NUMERIC,
    salary_flagged_outlier                 BOOLEAN
);

CREATE TABLE projects (
    project_id                TEXT,
    project_name                TEXT,
    department                    TEXT,
    status                          TEXT,
    start_date                        DATE,
    end_date                            DATE,
    budget                                NUMERIC,
    actual_cost                            NUMERIC,
    project_manager_id                       TEXT,
    priority                                   TEXT,
    region                                       TEXT,
    budget_variance                                NUMERIC,
    is_over_budget                                   BOOLEAN,
    duration_days                                      NUMERIC,
    budget_utilisation_pct                               NUMERIC,
    status_category                                        TEXT,
    risk_level                                               TEXT
);

CREATE TABLE transactions (
    transaction_id              TEXT,
    project_id                    TEXT,
    vendor_id                       TEXT,
    vendor_name                       TEXT,
    category                            TEXT,
    amount                                NUMERIC,
    currency                               TEXT,
    transaction_date                         DATE,
    approved_by                                TEXT,
    payment_status                               TEXT,
    invoice_ref                                    TEXT,
    notes                                            TEXT,
    project_name                                       TEXT,
    department                                           TEXT,
    approver_full_name                                     TEXT,
    is_approved                                              BOOLEAN,
    amount_aed                                                 NUMERIC,
    transaction_year_month                                       TEXT
);

COPY employees    FROM '/tmp/employees_clean.csv'    WITH (FORMAT csv, HEADER true);
COPY projects     FROM '/tmp/projects_clean.csv'     WITH (FORMAT csv, HEADER true);
COPY transactions FROM '/tmp/transactions_clean.csv' WITH (FORMAT csv, HEADER true);

-- select *from employees

-- ---------------------------------------------------------------------------
-- ORIGINAL QUERY (unmodified from the starter file)
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
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
-- EXPLAIN ANALYZE output — original query, real captured run (steady-state,
-- no indexes; one representative sample — see "repeated runs" note below
-- for why single captures on this query vary run to run)
-- ---------------------------------------------------------------------------
--                                                              QUERY PLAN
-- -------------------------------------------------------------------------------------------------------------------------------------
--  Sort  (cost=4251.72..4255.25 rows=1415 width=116) (actual time=15.005..15.035 rows=923 loops=1)
--    Sort Key: e.department, t.amount DESC
--    Sort Method: quicksort  Memory: 178kB
--    InitPlan 1 (returns $0)
--      ->  Aggregate  (cost=1984.21..1984.22 rows=1 width=32) (actual time=5.923..5.924 rows=1 loops=1)
--            ->  Seq Scan on transactions  (cost=0.00..1962.00 rows=8882 width=6) (actual time=0.001..5.326 rows=8927 loops=1)
--                  Filter: (payment_status = 'Pending'::text)
--                  Rows Removed by Filter: 41073
--    ->  Hash Join  (cost=61.74..2193.45 rows=1415 width=116) (actual time=6.446..13.853 rows=923 loops=1)
--          Hash Cond: (p.project_manager_id = e.employee_id)
--          ->  Hash Join  (cost=20.24..2132.49 rows=1415 width=87) (actual time=6.120..13.351 rows=923 loops=1)
--                Hash Cond: (t.project_id = p.project_id)
--                ->  Seq Scan on transactions t  (cost=0.00..2087.00 rows=2961 width=34) (actual time=5.935..12.928 rows=2127 loops=1)
--                      Filter: ((amount > $0) AND (payment_status = 'Pending'::text))
--                      Rows Removed by Filter: 47873
--                ->  Hash  (cost=17.25..17.25 rows=239 width=69) (actual time=0.161..0.162 rows=239 loops=1)
--                      Buckets: 1024  Batches: 1  Memory Usage: 33kB
--                      ->  Seq Scan on projects p  (cost=0.00..17.25 rows=239 width=69) (actual time=0.018..0.099 rows=239 loops=1)
--                            Filter: (status <> ALL ('{Completed,"On Hold"}'::text[]))
--                            Rows Removed by Filter: 261
--          ->  Hash  (cost=29.00..29.00 rows=1000 width=45) (actual time=0.315..0.316 rows=1000 loops=1)
--                Buckets: 1024  Batches: 1  Memory Usage: 86kB
--                ->  Seq Scan on employees e  (cost=0.00..29.00 rows=1000 width=45) (actual time=0.007..0.097 rows=1000 loops=1)
--  Planning Time: 0.665 ms
--  Execution Time: 15.133 ms
--
-- Summary — where this 15.1ms sample actually goes (self-time per step, approx.):
--   Step                         | Scan Type  | Rows In -> Out   | Time    | %
--   ------------------------------+-----------+------------------+---------+-----
--   AVG(amount) InitPlan          | Seq Scan  | 50,000 -> 8,927  | 5.33 ms | 35%
--   transactions filter (t)       | Seq Scan  | 50,000 -> 2,127  | 6.99 ms | 46%
--   Hash Join x2 + Sort           | (memory)  | -> 923 rows      | 2.81 ms | 19%
--   ------------------------------+-----------+------------------+---------+-----
--   TOTAL                                                         15.13 ms | 100%
--
-- Bottleneck analysis:
--   Joins used: two Hash Joins — transactions/projects on project_id, then
--   that result/employees on project_manager_id = employee_id. Both are
--   cheap (build a small in-memory hash table from projects/employees,
--   239 and 1000 rows) and are NOT the bottleneck — neither shows up as
--   expensive in "actual time".
--
--   What IS consuming the time: two separate full Seq Scans on
--   transactions (50,000 rows each), because the non-correlated AVG(amount)
--   subquery is pulled out as its own step (InitPlan 1) and evaluated
--   BEFORE the main query runs, not folded into the main scan's filter:
--     1. InitPlan 1's scan (~5.3ms this sample) — reads all 50,000 rows to
--        filter payment_status='Pending' (41,073 rows removed), just to
--        compute one number: the average.
--     2. The main Seq Scan on transactions t (~7.0ms this sample) — reads
--        all 50,000 rows AGAIN, this time filtering both
--        payment_status='Pending' AND amount > $0 (47,873 rows removed),
--        to get the 2,127 rows that actually matter.
--   Together these two full-table scans account for ~81% of this sample's
--   total — the joins, sort, and employees/projects scans are all
--   sub-millisecond by comparison. Neither scan has an index to seek
--   through the ~18% Pending rows directly; both must read and discard
--   most of the table. This is exactly what idx_transactions_status_project
--   (4c below) targets — it lets both scans become Bitmap Index Scans
--   instead of Seq Scans.


-- ---------------------------------------------------------------------------
-- REWRITTEN QUERY — before indexes
-- ---------------------------------------------------------------------------
-- 4 changes: implicit FROM A,B,C -> explicit JOIN...ON (a dropped WHERE on
-- a comma-join silently becomes a cartesian product); repeated subquery ->
-- CTE, referenced as a scalar subquery (not CROSS JOIN — nothing here
-- needs pending_avg's columns in the SELECT list, so a scalar subquery
-- expresses "compare against one precomputed value" more directly, and
-- lets Postgres plan it the same way as the original's InitPlan instead
-- of forcing an extra Nested Loop + Join Filter); status filter pushed
-- onto JOIN...ON; no SELECT *.
EXPLAIN ANALYZE
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
WHERE t.payment_status = 'Pending'
  AND t.amount > (SELECT avg_pending_amount FROM pending_avg)
ORDER BY e.department, t.amount DESC;


-- ---------------------------------------------------------------------------
-- EXPLAIN ANALYZE output — rewritten query, before indexes, real captured run
-- ---------------------------------------------------------------------------
--                                                             QUERY PLAN
-- -------------------------------------------------------------------------------------------------------------------------------------
--  Sort  (cost=4251.73..4255.27 rows=1415 width=116) (actual time=13.949..13.981 rows=923 loops=1)
--    Sort Key: e.department, t.amount DESC
--    Sort Method: quicksort  Memory: 178kB
--    InitPlan 1 (returns $0)
--      ->  Aggregate  (cost=1984.21..1984.22 rows=1 width=32) (actual time=4.773..4.774 rows=1 loops=1)
--            ->  Seq Scan on transactions  (cost=0.00..1962.00 rows=8883 width=6) (actual time=0.001..4.302 rows=8927 loops=1)
--                  Filter: (payment_status = 'Pending'::text)
--                  Rows Removed by Filter: 41073
--    ->  Hash Join  (cost=61.74..2193.45 rows=1415 width=116) (actual time=5.243..12.806 rows=923 loops=1)
--          Hash Cond: (p.project_manager_id = e.employee_id)
--          ->  Hash Join  (cost=20.24..2132.49 rows=1415 width=87) (actual time=4.939..12.298 rows=923 loops=1)
--                Hash Cond: (t.project_id = p.project_id)
--                ->  Seq Scan on transactions t  (cost=0.00..2087.00 rows=2961 width=34) (actual time=4.782..11.891 rows=2127 loops=1)
--                      Filter: ((amount > $0) AND (payment_status = 'Pending'::text))
--                      Rows Removed by Filter: 47873
--                ->  Hash  (cost=17.25..17.25 rows=239 width=69) (actual time=0.109..0.110 rows=239 loops=1)
--                      Buckets: 1024  Batches: 1  Memory Usage: 33kB
--                      ->  Seq Scan on projects p  (cost=0.00..17.25 rows=239 width=69) (actual time=0.011..0.061 rows=239 loops=1)
--                            Filter: (status <> ALL ('{Completed,"On Hold"}'::text[]))
--                            Rows Removed by Filter: 261
--          ->  Hash  (cost=29.00..29.00 rows=1000 width=45) (actual time=0.295..0.295 rows=1000 loops=1)
--                Buckets: 1024  Batches: 1  Memory Usage: 86kB
--                ->  Seq Scan on employees e  (cost=0.00..29.00 rows=1000 width=45) (actual time=0.005..0.086 rows=1000 loops=1)
--  Planning Time: 0.519 ms
--  Execution Time: 14.061 ms
--
-- Summary — where this 14.1ms sample actually goes (self-time per step, approx.):
--   Step                         | Scan Type  | Rows In -> Out   | Time    | %
--   ------------------------------+-----------+------------------+---------+-----
--   AVG(amount) InitPlan          | Seq Scan  | 50,000 -> 8,927  | 4.30 ms | 31%
--   transactions filter (t)       | Seq Scan  | 50,000 -> 2,127  | 7.11 ms | 50%
--   Hash Join x2 + Sort           | (memory)  | -> 923 rows      | 2.65 ms | 19%
--   ------------------------------+-----------+------------------+---------+-----
--   TOTAL                                                         14.06 ms | 100%
--
-- Analysis: same plan as the original, same bottleneck. Removing CROSS
-- JOIN lets Postgres fold the CTE back into an InitPlan — the identical
-- shape (InitPlan -> Hash Join x2 -> Sort) as the original comma-join
-- query. Same two Seq Scans on transactions dominate the time either way.
-- The CTE here is a readability change, not a performance one — the real
-- gain comes from the indexes below.


-- ---------------------------------------------------------------------------
-- INDEXES — for the production deployment this query actually runs in
-- ---------------------------------------------------------------------------
-- Speeds up the manager->employee join + status filter. status listed
-- second — it's the lower-selectivity predicate (4 values).
CREATE INDEX idx_projects_manager_status ON projects (project_manager_id, status);

-- Speeds up the project_id join + payment_status filter. payment_status
-- first, so Postgres can seek the ~18% Pending rows before the join.
CREATE INDEX idx_transactions_status_project ON transactions (payment_status, project_id);

-- employee_id is already this table's PK in a real deployment — no new
-- index needed there.

ANALYZE employees;
ANALYZE projects;
ANALYZE transactions;


-- ---------------------------------------------------------------------------
-- REWRITTEN QUERY — after indexes
-- ---------------------------------------------------------------------------
EXPLAIN ANALYZE
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
WHERE t.payment_status = 'Pending'
  AND t.amount > (SELECT avg_pending_amount FROM pending_avg)
ORDER BY e.department, t.amount DESC;


-- ---------------------------------------------------------------------------
-- EXPLAIN ANALYZE output — rewritten query, after indexes, real captured run
-- ---------------------------------------------------------------------------
--                                                                     QUERY PLAN
-- --------------------------------------------------------------------------------------------------------------------------------------------------
--  Sort  (cost=3328.63..3332.22 rows=1439 width=116) (actual time=9.209..9.245 rows=923 loops=1)
--    Sort Key: e.department, t.amount DESC
--    Sort Method: quicksort  Memory: 178kB
--    InitPlan 1 (returns $0)
--      ->  Aggregate  (cost=1582.79..1582.80 rows=1 width=32) (actual time=3.600..3.603 rows=1 loops=1)
--            ->  Bitmap Heap Scan on transactions  (cost=110.30..1560.21 rows=9033 width=6) (actual time=0.502..2.808 rows=8927 loops=1)
--                  Recheck Cond: (payment_status = 'Pending'::text)
--                  Heap Blocks: exact=1337
--                  ->  Bitmap Index Scan on idx_transactions_status_project  (cost=0.00..108.04 rows=9033 width=0) (actual time=0.344..0.345 rows=8927 loops=1)
--                        Index Cond: (payment_status = 'Pending'::text)
--    ->  Hash Join  (cost=172.16..1670.33 rows=1439 width=116) (actual time=5.363..8.014 rows=923 loops=1)
--          Hash Cond: (t.project_id = p.project_id)
--          ->  Bitmap Heap Scan on transactions t  (cost=108.79..1581.29 rows=3011 width=34) (actual time=4.997..7.358 rows=2127 loops=1)
--                Recheck Cond: (payment_status = 'Pending'::text)
--                Filter: (amount > $0)
--                Rows Removed by Filter: 6800
--                Heap Blocks: exact=1337
--                ->  Bitmap Index Scan on idx_transactions_status_project  (cost=0.00..108.04 rows=9033 width=0) (actual time=1.198..1.198 rows=8927 loops=1)
--                      Index Cond: (payment_status = 'Pending'::text)
--          ->  Hash  (cost=60.38..60.38 rows=239 width=98) (actual time=0.349..0.352 rows=239 loops=1)
--                Buckets: 1024  Batches: 1  Memory Usage: 40kB
--                ->  Hash Join  (cost=20.24..60.38 rows=239 width=98) (actual time=0.143..0.288 rows=239 loops=1)
--                      Hash Cond: (e.employee_id = p.project_manager_id)
--                      ->  Seq Scan on employees e  (cost=0.00..29.00 rows=1000 width=45) (actual time=0.010..0.070 rows=1000 loops=1)
--                      ->  Hash  (cost=17.25..17.25 rows=239 width=69) (actual time=0.123..0.124 rows=239 loops=1)
--                            Buckets: 1024  Batches: 1  Memory Usage: 33kB
--                            ->  Seq Scan on projects p  (cost=0.00..17.25 rows=239 width=69) (actual time=0.009..0.070 rows=239 loops=1)
--                                  Filter: (status <> ALL ('{Completed,"On Hold"}'::text[]))
--                                  Rows Removed by Filter: 261
--  Planning Time: 3.083 ms
--  Execution Time: 9.869 ms
--
-- What improved (14.06ms -> 9.87ms) — same InitPlan/Hash Join/Sort shape
-- before and after, just cheaper leaf scans:
--   Step                | Before (Seq Scan) | After (Bitmap Index) | Note
--   --------------------+--------------------+----------------------+------------------
--   InitPlan AVG scan   | 4.30 ms            | 2.81 ms              | index seeks ~8,927 Pending rows directly
--   Join-side scan      | 7.11 ms            | 7.36 ms              | unchanged (noise) — still Filters amount > $0 after
--   --------------------+--------------------+----------------------+------------------




-- ---------------------------------------------------------------------------
-- BONUS — does indexing `amount` too help further? Tested, yes.
-- ---------------------------------------------------------------------------
-- idx_transactions_status_project (payment_status, project_id) narrows to
-- the Pending rows via the index, but still needs a post-fetch Filter for
-- amount > $0 (the average) since amount isn't in that index — Filter:
-- amount > $0, Rows Removed by Filter: 6800 in the earlier capture.
--
-- Swapping the trailing column for amount instead of project_id lets
-- Postgres push that comparison into the index seek itself:

CREATE INDEX idx_transactions_status_amount ON transactions (payment_status, amount);
ANALYZE transactions;
--
-- Real captured plan, same query as "REWRITTEN QUERY — after indexes"
-- above, with this index also present:
--                                                                                  QUERY PLAN
-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--  Sort  (cost=1945.37..1948.92 rows=1417 width=116) (actual time=4.143..4.260 rows=923 loops=1)
--    Sort Key: e.department, t.amount DESC
--    Sort Method: quicksort  Memory: 178kB
--    InitPlan 1 (returns $0)
--      ->  Aggregate  (cost=322.28..322.29 rows=1 width=32) (actual time=1.066..1.066 rows=1 loops=1)
--            ->  Index Only Scan using idx_transactions_status_amount on transactions  (cost=0.41..300.04 rows=8893 width=6) (actual time=0.018..0.638 rows=8927 loops=1)
--                  Index Cond: (payment_status = 'Pending'::text)
--                  Heap Fetches: 0
--    ->  Hash Join  (cost=142.16..1548.91 rows=1417 width=116) (actual time=1.749..3.172 rows=923 loops=1)
--          Hash Cond: (t.project_id = p.project_id)
--          ->  Bitmap Heap Scan on transactions t  (cost=78.80..1460.26 rows=2964 width=34) (actual time=1.426..2.549 rows=2127 loops=1)
--                Recheck Cond: ((payment_status = 'Pending'::text) AND (amount > $0))
--                Heap Blocks: exact=1084
--                ->  Bitmap Index Scan on idx_transactions_status_amount  (cost=0.00..78.06 rows=2964 width=0) (actual time=1.337..1.337 rows=2127 loops=1)
--                      Index Cond: ((payment_status = 'Pending'::text) AND (amount > $0))
--          ->  Hash  (cost=60.38..60.38 rows=239 width=98) (actual time=0.312..0.314 rows=239 loops=1)
--                Buckets: 1024  Batches: 1  Memory Usage: 40kB
--                ->  Hash Join  (cost=20.24..60.38 rows=239 width=98) (actual time=0.124..0.256 rows=239 loops=1)
--                      Hash Cond: (e.employee_id = p.project_manager_id)
--                      ->  Seq Scan on employees e  (cost=0.00..29.00 rows=1000 width=45) (actual time=0.006..0.061 rows=1000 loops=1)
--                      ->  Hash  (cost=17.25..17.25 rows=239 width=69) (actual time=0.108..0.109 rows=239 loops=1)
--                            Buckets: 1024  Batches: 1  Memory Usage: 33kB
--                            ->  Seq Scan on projects p  (cost=0.00..17.25 rows=239 width=69) (actual time=0.006..0.060 rows=239 loops=1)
--                                  Filter: (status <> ALL ('{Completed,"On Hold"}'::text[]))
--                                  Rows Removed by Filter: 261
--  Planning Time: 0.638 ms
--  Execution Time: 4.367 ms
--
-- What improved, and why it's better than swapping — not just moving —
-- the bottleneck:
--   Step              | With (status,project_id) | With (status,amount)
--   ------------------+---------------------------+----------------------
--   InitPlan AVG scan  | Bitmap Index+Heap, 2.81ms | Index Only Scan, 1.07ms — Heap Fetches: 0
--   Join-side scan     | Bitmap + Filter, 7.36ms   | Bitmap, no Filter, ~2.46ms
--   ------------------+---------------------------+----------------------
--   Steady-state total | ~9.87 ms                  | ~4.4-5.7 ms (~2.1x further improvement)
--
--   1. InitPlan becomes an Index Only Scan (Heap Fetches: 0) — both
--      columns it needs (payment_status, amount) live entirely in the
--      index, so Postgres never touches the table at all.
--   2. The join-side scan's Filter disappears — amount > $0 is now part
--      of Index Cond, so the index returns exactly the 2,127 qualifying
--      rows directly instead of fetching 8,927 and discarding 6,800
--      afterward.
--
-- Trade-off (why this isn't unconditionally "just do this instead"):
--   This index is narrowly useful — it helps only this exact filter shape
--   (payment_status + amount range). idx_transactions_status_project
--   (payment_status, project_id) stays valuable for other queries that
--   join on project_id. Adding this as a THIRD index on transactions
--   means every INSERT/UPDATE to that table now maintains three indexes
--   instead of two — worth it only if this query is genuinely hot enough
--   in production to justify the extra write cost on what's likely the
--   fastest-growing table in the system.

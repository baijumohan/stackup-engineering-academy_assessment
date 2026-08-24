# Presight Analytics Platform — Data Engineering Assessment

*Author: Baiju Mohan*

> Master project story for interview walkthroughs. Each pillar has its own
> deeper write-up, same structure:
> [Foundations](project_docs/01_foundations.md) ·
> [SQL & Visualization](project_docs/02_sql_and_visualization.md) ·
> [Big Data Processing](project_docs/03_big_data_processing.md) ·
> [Infrastructure & Governance](project_docs/04_infrastructure_and_governance.md)
>
> To actually run the code: [HOW_TO_RUN.md](HOW_TO_RUN.md).

---

## Repository Layout

```
solutions/submissions/baiju_mohan/
├── 01_foundations/
│   ├── etl_pipeline.py              # Tasks 1.1, 1.3 (imported by Pillar 2/3/4, not duplicated)
│   ├── data_model.sql               # Task 1.2 — star schema DDL + SCD2 build + validation (Sections 1-2)
│   ├── ASSUMPTIONS.md
│   ├── VALIDATION_EVIDENCE.md
│   └── README.md
├── 02_sql_and_viz/
│   ├── etl_full.py                  # Task 2.2 — canonical ETL; Airflow + Docker both run this exact file
│   ├── queries.sql                  # Task 2.1 — six business questions
│   ├── query_optimization.sql       # Task 2.3 — original/rewrite/indexes/benchmark, self-contained
│   ├── export_dashboard_data.sql    # Task 2.4 support — documented, not the dashboard's actual data source
│   ├── run_queries.py, run_optimization.py  # drivers that execute the .sql files and print real output
│   ├── warehouse_explorer.ipynb     # live query exploration
│   └── README.md
├── 03_big_data/
│   ├── spark_pipeline.py            # Task 3.1
│   ├── kafka_streaming.py           # Task 3.2
│   ├── airflow_dag.py               # Task 3.3 — imports Pillar 1/2/4 modules, doesn't duplicate them
│   ├── deploy_dag.ps1               # copies the DAG + imports into the Airflow containers
│   ├── big_data_explorer.ipynb      # live Spark/Kafka output exploration
│   └── README.md
├── 04_infrastructure/
│   ├── data_governance.md           # Task 4.2
│   ├── dq_framework.py              # Task 4.3 — imported by the Airflow DQ gate
│   └── README.md
├── project_docs/                    # deeper per-pillar write-ups (linked above)
├── HOW_TO_RUN.md
└── SUBMISSION_NOTES.md              # this file

# Dockerfile/.dockerignore live at the repo root, not in 04_infrastructure/ —
# tasks/04_infrastructure/INSTRUCTIONS.md requires it there (build context
# needs solutions/ and datasets/, siblings of 04_infrastructure/, not children).
```

## Output Layout

Every artifact has **one** canonical location.

| Artifact | Path |
|---|---|
| `projects_clean.csv`, `employees_clean.csv`, `employees_quality_summary.json`, `pipeline_summary.txt` | `outputs/results/baiju_mohan/01_foundations/` |
| Star schema + `dim_employee` (SCD2) | `outputs/presight_warehouse.duckdb` — single shared file, not namespaced per pillar |
| `transactions_clean.csv`, `pipeline_summary.txt`, `presight_dashboard.pbix` | `outputs/results/baiju_mohan/02_sql_and_viz/` |
| Spark's 5 Parquet tables | `outputs/artifacts/baiju_mohan/03_big_data/spark/` — **gitignored**, regenerable binary build output |
| Kafka `summary.json` | `outputs/results/baiju_mohan/03_big_data/kafka/` |
| Airflow `pipeline_report_<date>.txt` | `outputs/results/baiju_mohan/03_big_data/` |
| `data_governance_document.md`, `dq_report_*.md` | `outputs/results/baiju_mohan/04_infrastructure/` |

---

## 1. Executive Summary

Presight runs a project management platform for enterprise and government clients. The data behind it — project records, HR data, transactions, a platform event stream — existed only as raw exports: dirty, historyless, processed by hand when it was processed at all.

I built the data engineering layer that turns that into something the business can rely on: a cleaned foundation (Pandas), a queryable star-schema warehouse with real historical employee tracking (DuckDB + SCD Type 2), a big-data layer for the 100K-event stream (PySpark + Kafka), a scheduled and quality-gated pipeline (Airflow), and the infrastructure/governance work that makes it deployable and audit-ready (Docker, a governance doc, a DQ framework).

Every piece was run against real infrastructure and real data — and four genuine bugs were found and fixed specifically because I ran things end to end, not because the code looked correct on paper.

**At a glance:**

| Metric | Result |
|---|---|
| Full transactions ETL (50,000 rows) | **0.84s** (target: <30s) |
| Spark event processing (99,996 events, 12 files) | **114.7s**, ~872 events/sec |
| Kafka end-to-end (8,333 messages) | All consumed, 14 critical escalations correctly routed |
| Airflow DAG | Runs fully green; DQ gate proven to actually block on failure |
| Dockerised ETL container | **11.1s** wall-clock (target: <30s) |
| SCD2 dimension integrity | 0 duplicate-current rows, 0 overlapping periods, across 2,232 versions |
| Data quality checks (framework) | 9 checks × 3 datasets, real mixed results (6/9, 3/9, 6/9) |

## 2. Business Problem

Three teams, one root problem: no trustworthy, queryable, historically-aware data.

Finance and Operations needed recurring questions answered with no way to query directly — every answer meant manually reconciling CSVs. HR and Finance needed historical answers ("what was this person earning when they approved this spend"), which a current-state-only export can't give. The event stream (100K+ events) had outgrown ad hoc analysis — nobody could say which projects escalate most or when usage peaks.

Underneath all three: the pipeline only ran manually, with no schedule, no quality gate, and no governance doc — nothing Compliance could sign off on or Ops could trust unattended.

## 3. Project Scope

**In scope:** the full pipeline from raw export to governed, scheduled warehouse — cleaning and DQ detection, dimensional modeling with real SCD2, six business questions plus a measured query-optimisation exercise, an executive dashboard, Spark batch processing, Kafka ingestion, Airflow orchestration with a quality gate, containerisation, and governance documentation.

**Out of scope:** a multi-node Spark cluster or production Kafka deployment (scoped to prove pipeline logic, not cluster ops); cloud deployment (the env-var configuration makes that step straightforward later); final legal sign-off on retention periods (defensible defaults, flagged for review).

**Scale:** 500 projects, 1,000 employees, ~1,800 salary-history records, 50,000 transactions, 100,000 platform events across 12 files — large enough that vectorisation, indexing, and partitioning decisions have measurable consequences.

## 4. Technology Stack

| Technology | Role in the Project | Why It Was Chosen |
|---|---|---|
| Python + Pandas + NumPy | Cleaning, DQ detection, SCD2 build, transaction enrichment | Squarely vectorised-pandas territory at these row counts — a distributed engine here would be over-engineering |
| DuckDB | Warehouse — star schema, business questions, optimisation benchmarking | Embedded, vectorised, native `EXPLAIN ANALYZE` — zero server to stand up |
| Apache Spark (PySpark) | Distributed processing of the 100K-event stream into 5 tables | Where volume actually crosses into needing a distributed engine |
| Apache Kafka | Real-time ingestion simulation, severity-based routing | Standard decoupled pattern, foundation for batch-to-real-time |
| Apache Airflow 2.7 | Daily orchestration, retries, a hard DQ gate, XCom reporting | Built for scheduled, observable, dependency-ordered execution |
| Docker (multi-stage build) | Containerises the ETL into a portable artifact | Splits the heavy dependency install from the runtime image |
| Java 17 + Hadoop native libs | JVM runtime Spark depends on, Windows I/O support | Not optional — Spark doesn't run without it |

## 5. High-Level Architecture & Data Flow

```mermaid
flowchart TD
    subgraph Raw["Raw operational exports"]
        RP["projects.csv"]
        RE["employees.csv"]
        RH["employees_salary_history.csv"]
        RT["transactions.json"]
        REV["events_stream/*.jsonl (12 files)"]
    end

    subgraph Foundations["Pillar 1 — Foundations"]
        Clean["Vectorised cleaning +\n6-category DQ detection"]
        SCD["SCD Type 2 build:\ndim_employee"]
    end
    RP --> Clean
    RE --> Clean
    RH --> SCD
    Clean --> SCD

    subgraph Warehouse["Pillar 2 — SQL & Visualization"]
        Star["DuckDB star schema\n(point-in-time employee resolution)"]
        BQ["6 business questions"]
        Dash["Executive dashboard"]
    end
    Clean --> Star
    SCD --> Star
    RT --> Star
    Star --> BQ --> Dash

    subgraph BigData["Pillar 3 — Big Data Processing"]
        Spark["Spark: 5 aggregated tables"]
        Kafka["Kafka: producer -> topic -> consumer\n-> critical-escalation routing"]
        Airflow["Airflow DAG: extract -> DQ GATE ->\ntransform -> load -> report\n(daily, 06:00 Dubai)"]
    end
    REV --> Spark
    REV --> Kafka
    Clean -.orchestrated by.-> Airflow
    SCD -.orchestrated by.-> Airflow

    subgraph Infra["Pillar 4 — Infrastructure & Governance"]
        Docker["Dockerised ETL\n(multi-stage build)"]
        DQ["Configurable DQ framework\n(9 checks, config-driven)"]
        Gov["Governance doc:\nPII, retention, access, lineage"]
    end
    Airflow -.DQ gate uses.-> DQ
    Clean -.containerised by.-> Docker
    Star -.classified in.-> Gov
```

The decision that ties everything together: treating `dim_employee` as real SCD Type 2 from the start. It's what makes the warehouse's point-in-time joins correct, what the compensation-history question depends on, and what the Airflow DQ gate re-validates on every run.

## 6. My Responsibilities & Contributions

Designed and built every layer end to end — the profiling that found the real data issues, the dimensional model, the SQL, the distributed processing, the streaming simulation, the orchestration, the containerisation, the governance doc. Verified every piece against real infrastructure, which is how the bugs below actually surfaced.

## 7. Task-by-Task Breakdown

Where the narrative above stays at the "why," this section is the "what/how" — one
entry per task, File → What was done → Decisions → Output throughout, so any single
task can be checked in isolation. Numbers below are real, captured by re-running each
pipeline (see each pillar's `VALIDATION_EVIDENCE.md` for the commands).

### Pillar 1 — Foundations (Tasks 1.1, 1.2, 1.3)

**Task 1.1 — Clean and transform `projects.csv`**
File: `01_foundations/etl_pipeline.py` → `load_projects()` + `transform_projects()`

- Parsed `start_date`/`end_date` as datetime; derived `budget_variance`, `is_over_budget`, `duration_days`, `budget_utilisation_pct`, `status_category`, `risk_level` — all vectorised (`np.select`/`np.where`, no `.iterrows()`).
- `risk_level`: Critical priority or over-budget → High; High priority or >90% utilisation → Medium; else Low.
- Decisions: null `budget`/`actual_cost` filled with `0` *before* deriving (not after); `budget_utilisation_pct` is `0`, not NaN/inf, when `budget` is `0`; unmapped `status` values pass through rather than being force-mapped.
- Output: `projects_clean.csv` — 500 rows, 17 columns.

**Task 1.2 — Star schema + `dim_employee` (SCD Type 2)**
File: `01_foundations/data_model.sql` (Section 1)

- 6-table star schema (`fact_transactions`, `dim_project`, `dim_employee`, `dim_vendor`, `dim_date`, `bridge_employee_project`) — surrogate integer keys, natural source IDs preserved.
- `dim_employee` built entirely in SQL: `employees_clean.csv` (current state) staged against `employees_salary_history.csv` (~1,826 rows, ~60% of employees) with `ROW_NUMBER()`/`LEAD()` chaining `valid_from`/`valid_to` periods. 5 validation queries run immediately after the build.
- Decisions: only `role`/`level`/`salary` are true Type 2 attributes (the history file has nothing else to version); `employees_clean.csv` wins the one case where it conflicts with history (`EMP0084`); 8 employees with both no history and a nulled `hire_date` get an explicit `1900-01-01` sentinel `valid_from` rather than `NULL`, to keep the interval-arithmetic validation queries working.
- Output: `dim_employee` — 2,232 versions in `outputs/presight_warehouse.duckdb`. 0 duplicate-current rows, 0 overlapping periods.

**Task 1.3 — Employee data quality (`clean_employees()`)**
File: `01_foundations/etl_pipeline.py`

All from full-column profiling, not the first 40 rows:

| Issue | Rows | Action |
|---|---|---|
| Blank/missing email | 10 | → placeholder `unknown@presight.ai` (not name-derived) |
| Unparseable `hire_date` | 5 | → null |
| Implausible `hire_date` (pre-1990) | 3 | → null |
| `years_experience` outside `[0,50]` | 5 | → imputed with level median |
| Salary outside level's `[p5,p95]` band | 3 | → winsorised to p95 |
| Active employee under an Inactive manager | 0 | guardrail, kept despite 0 hits |

Output: `employees_clean.csv` (1,000 rows, 13 columns) + `employees_quality_summary.json`.

### Pillar 2 — SQL & Data Visualization (Tasks 2.1–2.4)

**Task 2.1 — Six business questions**
File: `02_sql_and_viz/queries.sql`

| Q# | Question | Rows returned |
|---|---|---|
| Q1 | Department budget performance | 1 |
| Q2 | Project manager workload | 0 — legitimately empty, verified against raw distribution |
| Q3 | Vendor concentration risk | 0 — legitimately empty, max vendor share ~4.4% |
| Q4 | Open financial issues | 435 |
| Q5 | Monthly spend trend + running total (`SUM() OVER`, `LAG()`) | 726 |
| Q6 | Compensation history (SCD2 self-join) | 20 |

**Task 2.2 — Full ETL pipeline**
File: `02_sql_and_viz/etl_full.py` — the canonical ETL; Airflow and Docker both run this exact file.

- Loads `transactions.json` (50,000 rows), enriches with project (`project_name`/`department`) and current-employee (`approver_full_name`) context via row-count-asserted left joins, derives `is_approved`, `amount_aed`, `transaction_year_month`.
- Decisions: `amount` nulls (1.5%) kept as true `NaN`, not imputed — `amount_aed` derives `0.0` for aggregation safety; `approved_by` nulls (4.9%) → `is_approved = False`, no approver fabricated.
- Output: `transactions_clean.csv` (50,000 rows, 18 columns) + `pipeline_summary.txt`. Ran in 0.44s against a 30s target.

**Task 2.3 — Query optimisation**
File: `02_sql_and_viz/query_optimization.sql`

Captured `EXPLAIN ANALYZE` on the unmodified starter query, rewrote it (explicit `JOIN...ON`, correlated subquery → CTE, early predicate filtering), re-benchmarked best-of-5, documented indexes for a production Postgres deployment.

Reported honestly: both queries return the same 923 rows; best-of-5 best times 6.03ms → 5.86ms — a 1.03x speedup. DuckDB's own optimiser already rewrites the comma-join and resolves the subquery as uncorrelated at this data volume, so the rewrite's value here is readability and provable correctness, not raw speed. Where the rewrite/indexing would show a real difference (10-50M row Postgres) is documented alongside the benchmark.

**Task 2.4 — Executive dashboard**
Output: `presight_dashboard.pbix`, built in Power BI Desktop, connected directly to `projects_clean.csv`/`transactions_clean.csv` — not a mockup, not a separate extract.

### Pillar 3 — Big Data Processing (Tasks 3.1–3.3)

**Task 3.1 — PySpark event processing**
File: `03_big_data/spark_pipeline.py`

- Loaded all 12 monthly `events_*.jsonl` files (99,996 rows) with an explicit `StructType` schema (no `inferSchema`), dropped null `event_id`/`user_id`, deduped by `event_id` keeping the earliest timestamp, derived `event_date`/`event_hour`/`event_month`.
- Decisions: escalation resolution is real temporal matching (each `escalation_resolved` claims the earliest still-open `escalation_raised` before it), not positional pairing — see Challenges below for why that mattered.

| Table | Rows | Partitioned by |
|---|---|---|
| `project_activity_summary` | 500 | — |
| `user_activity_summary` | 960 | — |
| `escalation_log` | 1,969 | `severity` |
| `daily_event_volume` | 5,088 | `event_date` |
| `peak_usage_analysis` | 20 | — |

Output: `outputs/artifacts/baiju_mohan/03_big_data/spark/` (gitignored, regenerable). Total run: 82.80s, ~1,208 events/sec.

**Task 3.2 — Kafka producer/consumer**
File: `03_big_data/kafka_streaming.py`

Producer streams `events_2025_01.jsonl` (8,333 events) at 50ms/message, keyed by `event_type`, into `presight.project.events` (3 partitions); consumer (`auto_offset_reset=earliest`) tallies event counts and forwards Critical-severity `escalation_raised` events to `presight.escalations.critical` (1 partition).

Output: `outputs/results/baiju_mohan/03_big_data/kafka/summary.json` — 8,333 produced == 8,333 consumed (no loss), 14 critical escalations forwarded, 585.9 msg/sec consumer throughput.

**Task 3.3 — Airflow DAG**
File: `03_big_data/airflow_dag.py` — DAG `presight_etl_pipeline`, daily 06:00 Asia/Dubai, `catchup=False`, `max_active_runs=1`, `retries=2`.

Task chain: parallel extract (projects/employees/transactions) → `validate_data_quality` (DQ gate, hard-blocks if any key column's completeness drops below 80%) → `transform_and_enrich` → `load_to_output` → `generate_pipeline_report` (via XCom).

Deployment: `deploy_dag.ps1` copies the DAG plus its imported sibling modules (`etl_pipeline.py`, `etl_full.py`, `dq_framework.py`) into the Airflow containers' bind-mounted DAGs folder — a one-time copy, not a live mount, so it re-runs after any change to those files.

Output: a manually triggered run completed `success` in ~21s. DQ gate results that run: projects 6/9, employees 3/9, transactions 6/9 checks passed — none block the run since only primary-key completeness gates it, and all three pass that specific check.

### Pillar 4 — Infrastructure & Governance (Tasks 4.1–4.3)

**Task 4.1 — Docker containerisation**
Files: repo-root `Dockerfile`, `.dockerignore` (required at the root, not `04_infrastructure/`, since the build context needs `solutions/` and `datasets/` as siblings).

Two-stage build — a `builder` stage installs `requirements.txt` into a venv, a `runtime` stage copies only that venv plus the solution/dataset code onto a fresh `python:3.11-slim`, so pip's build cache never reaches the final image. `DATA_DIR`/`OUTPUT_DIR` read from the environment (the same mechanism built for Pillar 3's Airflow container).

Output: runs `etl_full.py`, writing to `outputs/results/baiju_mohan/02_sql_and_viz/` (the container runs Pillar 2's pipeline, so it doesn't get its own output folder). 11.1s wall-clock against a 30s target.

**Task 4.2 — Data governance document**
File: `04_infrastructure/data_governance.md`

Six sections across all 4 datasets: inventory, column-level classification (GDPR + UAE PDPL tags on every PII column), ownership (Owner vs. Steward), retention (salary history gets a longer window for the payroll/tax-audit angle, flagged for Legal confirmation), a least-privilege access-control matrix (Data Engineers get Read, not Read+Write, on salary history), and a Mermaid data-lineage diagram.

**Task 4.3 — Configurable data quality framework**
File: `04_infrastructure/dq_framework.py` — imported by the Airflow DQ gate (Task 3.3), not duplicated.

9 checks, all driven by a `DQ_CONFIG` dict (thresholds, PK columns, ranges, FK relationships — no hardcoded column names): completeness, uniqueness, validity (numeric), validity (date), consistency, referential integrity, distribution dominance, freshness, outliers (Z-score).

Kept honest: run against real uncleaned data, not tuned to pass — results are genuinely mixed (6/9 projects, 3/9 employees, 6/9 transactions on the live Airflow run), with specific real failures logged at `WARNING`, not a suspiciously clean report.

## 8. Key Engineering Decisions

**SCD Type 2 as the foundation, not an afterthought.** Once `dim_employee` versions salary/role/level, `fact_transactions` can resolve "who approved this, and what was true about them then" via a point-in-time `BETWEEN` match instead of a naive current-state lookup. Everything needing historical accuracy depends on this.

**Vectorisation as a hard rule.** Every DQ check and derived column is a whole-column operation — boolean masks, `np.select`, window functions instead of self-joins. Matters for readability at 1,000 rows; non-negotiable at 50,000+ for it to run in seconds, not minutes.

**Environment-variable configuration, built once, reused twice.** `DATA_DIR`/`OUTPUT_DIR` read from the environment solved the Airflow container's different filesystem layout in Pillar 3 — then solved the same problem for free in Pillar 4's Docker container.

**Reported honest results over convenient ones.** The query-optimisation exercise found no measurable DuckDB speedup, and I said so with the evidence. The zero-row business questions were verified against raw distributions, not assumed to be bugs. The DQ framework ran against real uncleaned data so its results would be genuine. When the real result wasn't the impressive one, I reported the real result.

## 9. Challenges & How I Solved Them

Four bugs, none visible from reading the code — all found by actually running the pipeline against real data and infrastructure:

- **A `np.select` call that broke only inside the Airflow container** — older pandas/numpy handled a nullable-boolean array differently. Found by running the DAG in the real container. *(Pillar 3)*
- **Negative escalation resolution times, down to -7,708 hours** — a positional pairing assumption broke when escalations weren't perfectly alternating. Found by checking actual output, not by trusting a clean run. *(Pillar 3)*
- **A Kafka double-serialization bug ~5,700 messages into a live run** — invisible to a smoke test, only caught by a full producer/consumer cycle against a real broker. *(Pillar 3)*
- **An SCD2 edge case at the intersection of two fixes** — employees with both an unparseable hire date and no salary history hit a path with nothing to set `valid_from` to. *(Pillar 1)*

Also worth naming: rather than trust the DQ gate's `raise ValueError`, I forced an impossible threshold, watched the gate fail and downstream tasks never run, then reverted and confirmed a clean run. Writing a check and proving it works are different things.

**A "fixed" bug that wasn't fully fixed.** The escalation-log guard above stopped negative durations, but I later found it was discarding 62% of escalations as "unresolved" rather than correctly matching them — the positional pairing itself was still wrong, the guard just hid the symptom. Replaced it with real temporal matching (each resolution claims the earliest still-open raise before it): correctly-resolved escalations went from 748 to 1,098, still zero negative durations. *(Pillar 3)*

**Two DQ framework gaps found by comparing against another trainee's independent solution**, not by re-reading my own code: `employees.manager_id` had no referential-integrity check against `employees.employee_id` (a legitimate self-referential FK), and the consistency check never actually verified salary-against-level despite the task naming that exact example. Fixed both — the self-reference surfaced a real, previously invisible issue (5 employees with a `manager_id` that doesn't resolve). *(Pillar 4)*

## 10. Data Quality, Reliability, Security & Performance

**Data quality**: targeted fixes during cleaning (Pillar 1, six issue categories from full-column profiling) plus a reusable framework (Pillar 4, 9 checks) that the Airflow DQ gate calls as a hard stop, not a warning.

**Reliability**: parallel extraction, a gate that provably blocks bad data, `retries=2`, `max_active_runs=1`, and an XCom-driven report of exactly what happened each run.

**Security**: every PII column tagged with GDPR/UAE PDPL, access control on least privilege — including narrower Data Engineer access to salary history than the "engineers need broad access" instinct suggests.

**Performance**: 0.84s for the transactions ETL, 114.7s for Spark across 99,996 events, 11.1s for the full Docker lifecycle — all measured by actually running the thing.

## 11. Outcome & Business Value

Finance and Operations get six previously-manual questions answered reliably, backed by a warehouse that threads historical employee context through every transaction. The event stream produces five analytics tables on every run, with a proven real-time path ready for what's next. The pipeline moved from "someone runs it manually" to scheduled, gated, containerised — reviewable by Compliance, deployable by DevOps.

Two Jupyter notebooks ([warehouse_explorer.ipynb](02_sql_and_viz/warehouse_explorer.ipynb), [big_data_explorer.ipynb](03_big_data/big_data_explorer.ipynb)) give a live, editable query surface over the warehouse and the Spark/Kafka outputs — useful for demoing the result interactively, not just reading static output.

More than any single number: every claim here is something I watched happen against real data, not something I assumed would work because the code looked right.

---

## Key Assumptions

1. Blank employee emails become a placeholder (`unknown@presight.ai`), not a name-derived fabrication — a placeholder can't be mistaken for real contact data downstream.
2. Unparseable/implausible dates are set to null, never guessed or defaulted to today.
3. Salary outliers are winsorised (capped to the level's p95), not just flagged — chosen because salary feeds directly into Q6 and the SCD2 build, so an uncorrected outlier would propagate.
4. `dim_employee`'s SCD2 history only versions `role`/`level`/`salary`, because that's all `employees_salary_history.csv` actually tracks — every other attribute carries forward from the current snapshot, documented as a scope limit rather than implied away.
5. Where the salary-history file conflicts with `employees_clean.csv` (one case, `EMP0084`), the clean CSV wins as the authoritative current-state export.
6. DQ thresholds (80% key-column completeness for the Airflow gate, 30% dominance for the distribution check, etc.) use the assessment's own reasonable defaults, not a client-specific SLA.
7. Retention periods in the governance doc are defensible defaults pending Legal sign-off, not verified legal citations.
8. Out of scope by design: a multi-node Spark cluster, a production Kafka deployment, and cloud deployment — the env-var configuration makes that last step straightforward later, not a rewrite.

Full per-task reasoning: [01_foundations/ASSUMPTIONS.md](01_foundations/ASSUMPTIONS.md) goes
task-by-task for Pillar 1; Pillars 2-4's assumptions are fewer and more load-bearing
individually, so they're folded into each pillar's `project_docs/*.md` write-up under
"Key Engineering Decisions" instead of a separate file.

---

## Known limitations (worth having ready if asked)

1. Q2/Q3 in Pillar 2 return zero rows on this dataset — the checks are real and would fire where the condition occurs.
2. The query-optimisation exercise shows no measurable speedup on DuckDB at 50K rows; documented why, and where it'd matter at production Postgres scale.
3. Retention periods in the governance doc are defensible defaults pending Legal sign-off, not verified legal citations.
4. `bridge_employee_project` only captures the guaranteed manager↔project edge in the source data; documented in `data_model.sql`.

---

## Completion Status

| Pillar | Task | Status |
|---|---|---|
| 1 | 1.1 — Clean/transform projects | Complete |
| 1 | 1.2 — Star schema + SCD2 `dim_employee` | Complete |
| 1 | 1.3 — Employee DQ detection/fixes | Complete |
| 2 | 2.1 — Six SQL business questions | Complete |
| 2 | 2.2 — Full ETL (50K transactions, <30s) | Complete |
| 2 | 2.3 — Query optimisation with real benchmarks | Complete |
| 2 | 2.4 — Power BI dashboard | Complete |
| 3 | 3.1 — Spark pipeline (5 Parquet tables) | Complete |
| 3 | 3.2 — Kafka producer/consumer + escalation forwarding | Complete |
| 3 | 3.3 — Airflow DAG with DQ gate + XCom reporting | Complete |
| 4 | 4.1 — Docker containerisation | Complete |
| 4 | 4.2 — Data governance document | Complete |
| 4 | 4.3 — Configurable DQ framework (9 checks) | Complete |

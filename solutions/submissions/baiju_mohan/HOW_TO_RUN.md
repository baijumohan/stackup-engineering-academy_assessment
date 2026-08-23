# How to Run This Submission

Exact commands to execute all 4 pillars, in order, from a clean clone. All
commands run from the **repo root**. For the design story behind each
pillar, see [SUBMISSION_NOTES.md](SUBMISSION_NOTES.md).

Each step below names the **tool/interface** to run it with — most are a
plain terminal, two are SQL-client-or-terminal (your choice), two are
Jupyter notebooks, and Pillar 3/4 need Docker.

## Prerequisites

- Python 3.11 + `pip install -r requirements.txt`. **Note:** if more than
  one Python is installed, plain `python` can resolve to the wrong one —
  verify with `python -c "import pandas, duckdb"` before running anything;
  if that fails, call the correct interpreter by full path.
- Docker Desktop running (Pillar 3 services + Pillar 4 container)
- Java 17 on PATH/`JAVA_HOME`, plus Hadoop native libs (`HADOOP_HOME`,
  Windows only) — required for Pillar 3's Spark job (exact env vars below)
- A DuckDB CLI or SQL client for the `.sql` files — see Pillar 1/2 below
- Jupyter support in your editor (e.g. VS Code's Jupyter extension) for the
  two `.ipynb` exploration notebooks
- Pillars run in order: 2 depends on 1's cleaned CSVs, 3's DAG imports 1 and
  2's pipeline functions, 4 containerises 2's pipeline.

## Pillar 1 — Foundations

**Tool: terminal**
```
python solutions/submissions/baiju_mohan/01_foundations/etl_pipeline.py
```
Writes `projects_clean.csv` / `employees_clean.csv` to
`outputs/results/baiju_mohan/01_foundations/`.

**Tool: DuckDB CLI (or any SQL client) against `outputs/presight_warehouse.duckdb`**
Run `01_foundations/data_model.sql`'s Section 1 (star schema DDL + SCD2
`dim_employee` build + validation). It has no path placeholders, so it runs
as-is — no substitution needed. It's also self-re-runnable: `CREATE TABLE
IF NOT EXISTS` + a `DELETE FROM` reset block at the top mean running it
twice in a row against the same file just rebuilds cleanly.
```
duckdb outputs\presight_warehouse.duckdb
.read solutions/submissions/baiju_mohan/01_foundations/data_model.sql
```
(A DuckDB CLI build lives at `%LOCALAPPDATA%\duckdb-cli\duckdb.exe` if not
already on PATH — add that folder to PATH, or call it by full path.)

## Pillar 2 — SQL & Data Visualization

**Tool: terminal**
```
python solutions/submissions/baiju_mohan/02_sql_and_viz/etl_full.py
python solutions/submissions/baiju_mohan/02_sql_and_viz/run_queries.py
python solutions/submissions/baiju_mohan/02_sql_and_viz/run_optimization.py
```
`etl_full.py` writes `transactions_clean.csv` + `pipeline_summary.txt`.
`run_queries.py` loads Section 2 of `data_model.sql` (remaining warehouse
tables) and runs `queries.sql`'s six business questions. `run_optimization.py`
runs `query_optimization.sql`'s original/rewritten queries and prints the
Task 2.3 EXPLAIN ANALYZE + benchmark output.

**Tool: DuckDB CLI (or any SQL client)** — all three `.sql` files
(`01_foundations/data_model.sql`, `02_sql_and_viz/queries.sql`,
`02_sql_and_viz/query_optimization.sql`) are plain runnable SQL; open any of
them and run statements directly against the warehouse. `queries.sql` needs
Section 2 already loaded first (via `run_queries.py` above, or manually).
`query_optimization.sql` is fully self-contained — its own setup block loads
plain `employees`/`projects`/`transactions` tables, just substitute
`__RESULTS__` with the real `outputs/results/baiju_mohan/02_sql_and_viz` path
first.

**Tool: Jupyter notebook** — [warehouse_explorer.ipynb](02_sql_and_viz/warehouse_explorer.ipynb)
gives the same warehouse a live, editable query surface with results
rendered as tables, useful for a demo. Open it in VS Code, select the
**"Presight (Python 3.14)"** kernel (registered via `python -m ipykernel
install --user --name=presight-py314`, points at whichever Python has
pandas/duckdb installed), run cells top to bottom.

Dashboard mockup is at
`outputs/results/baiju_mohan/02_sql_and_viz/dashboard_mockup.{html,pdf}`
(gitignored — superseded once the real Power BI dashboard exists).

## Pillar 3 — Big Data Processing

**Tool: Docker Desktop / terminal**
```
docker compose up -d
```

**Tool: terminal, with Spark env vars set first** (Windows PowerShell shown
— these don't persist between terminal sessions, set them each time or add
to your profile):
```powershell
$env:JAVA_HOME = "<path to your JDK 17 install>"
$env:HADOOP_HOME = "C:\hadoop"                    # folder containing bin\winutils.exe + bin\hadoop.dll
$env:Path = "$env:HADOOP_HOME\bin;$env:Path"
$env:PYSPARK_PYTHON = "$PWD\.venv\Scripts\python.exe"        # pin driver+worker to the same interpreter
$env:PYSPARK_DRIVER_PYTHON = "$PWD\.venv\Scripts\python.exe"

.venv\Scripts\python.exe solutions\submissions\baiju_mohan\03_big_data\spark_pipeline.py
```
PySpark lives in `.venv` (Python 3.11) — `PYSPARK_PYTHON`/`PYSPARK_DRIVER_PYTHON`
matter specifically because `escalation_log()` uses `applyInPandas`, which
spawns real worker processes; if those resolve to a *different* Python than
the driver (e.g. picked up from PATH), the job fails with a version-mismatch
error. `.venv` also needs `pandas`, `pyarrow`, and a working `numpy` — if
imports fail with an ABI/binary mismatch, `pip install --force-reinstall
--no-cache-dir numpy pandas pyarrow` inside `.venv` fixes it.

Writes the 5 Parquet tables to `outputs/artifacts/baiju_mohan/03_big_data/spark/`
— gitignored (a regenerable binary build output, unlike the CSV/JSON/markdown
deliverables tracked under `outputs/results/`).

**Tool: terminal**
```
python solutions/submissions/baiju_mohan/03_big_data/kafka_streaming.py --mode both
```
Producer streams all 8,333 events from `events_2025_01.jsonl` at 50ms/message
(~7 min), then the consumer drains them and writes
`outputs/results/baiju_mohan/03_big_data/kafka/summary.json`.

**Tool: Jupyter notebook** — [big_data_explorer.ipynb](03_big_data/big_data_explorer.ipynb)
explores all 5 Spark Parquet tables plus the Kafka summary via DuckDB's
`read_parquet()` (no pyarrow/pandas-parquet path needed for reading). Same
"Presight (Python 3.14)" kernel as the Pillar 2 notebook.

**Tool: terminal (deploy) + Airflow web UI or terminal (trigger)**
```
.\solutions\submissions\baiju_mohan\03_big_data\deploy_dag.ps1
```
Copies the DAG + sibling modules into the Airflow containers and restarts
them — re-run this any time `etl_pipeline.py`/`etl_full.py`/`dq_framework.py`/
`airflow_dag.py` change, since it's a one-time copy, not a live mount. Then
either trigger from the UI (`http://localhost:8081`, admin/admin) or:
```
docker exec presight-airflow-webserver airflow dags trigger presight_etl_pipeline
```

## Pillar 4 — Infrastructure & Governance

**Tool: Docker Desktop / terminal**
```
docker build -t presight-etl .
docker run --rm -v ${PWD}/outputs:/app/outputs presight-etl
```
(or `docker compose run --rm etl`, using the `etl` service in
`docker-compose.override.yml`). Runs the same Task 2.2 pipeline inside the
container. The DQ framework (`04_infrastructure/dq_framework.py`) isn't run
standalone — it's imported by `airflow_dag.py`'s quality-gate task, so the
`dq_report_{dataset}.md` files land in
`outputs/results/baiju_mohan/04_infrastructure/` as part of the Pillar 3
Airflow run above. `data_governance.md` is a static document, no script to run.

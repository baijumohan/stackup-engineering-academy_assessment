# Runs the entire project end-to-end, all 4 pillars, in the order documented
# in QUICK_RUN.md (steps 0-9). Chains what is otherwise a manual sequence of
# commands into one script -- nothing here does anything QUICK_RUN.md doesn't
# already document; see that file for what each step actually does and why.
#
# Run from the repo root:  .\solutions\submissions\baiju_mohan\run_all.ps1
#
# Steps 6 (Spark) and 7 (Kafka) are the slow ones -- Kafka alone is ~7 min
# (8,333 events at a scripted 50ms/event, matching the task's own spec).
# Skip switches are provided for re-runs where you don't need everything:
#   -SkipSpark    skip Task 3.1 (Spark)
#   -SkipKafka    skip Task 3.2 (Kafka, ~7 min)
#   -SkipAirflow  skip Task 3.3 (Airflow deploy + trigger)
#   -SkipDocker   skip Task 4.1 (Docker build + run)
#
# Example: .\solutions\submissions\baiju_mohan\run_all.ps1 -SkipKafka -SkipDocker

param(
    [switch]$SkipSpark,
    [switch]$SkipKafka,
    [switch]$SkipAirflow,
    [switch]$SkipDocker
)

$ErrorActionPreference = "Stop"
$PY = ".venv\Scripts\python.exe"
$SRC = "solutions\submissions\baiju_mohan"
$JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"
$HADOOP_HOME = "C:\hadoop"

function Step($n, $title) {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "  Step $n -- $title" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}

$started = Get-Date

# ---------------------------------------------------------------------------
# Step 0 -- Docker services (Kafka, Airflow, Postgres)
# ---------------------------------------------------------------------------
Step 0 "Start Docker services (docker compose up -d)"
docker compose up -d

# ---------------------------------------------------------------------------
# Pillar 1 -- Foundations
# ---------------------------------------------------------------------------
Step 1 "Clean projects/employees (1.1, 1.3)"
& $PY "$SRC\01_foundations\etl_pipeline.py"

Step 2 "Star schema + SCD2 build (1.2)"
# DuckDB's -c argument parses backslashes as C-style escapes (\b -> backspace,
# \0 -> null), which mangles a Windows path passed with backslashes -- use
# forward slashes instead (DuckDB accepts them fine on Windows).
$dataModelSql = "$SRC/01_foundations/data_model.sql" -replace '\\', '/'
try {
    duckdb outputs/presight_warehouse.duckdb -c ".read $dataModelSql"
} catch {
    Write-Host "Non-fatal: this step ends with a documented 'IO Error: __OUTPUTS__/projects_clean.csv not found' -- the actual schema + SCD2 build above it already succeeded (see QUICK_RUN.md row 2)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Pillar 2 -- SQL & Visualization
# ---------------------------------------------------------------------------
Step 3 "Clean transactions (2.2)"
& $PY "$SRC\02_sql_and_viz\etl_full.py"

Step 4 "Six business questions (2.1)"
& $PY "$SRC\02_sql_and_viz\run_queries.py"

Step 5 "Query optimization benchmark (2.3)"
& $PY "$SRC\02_sql_and_viz\run_optimization.py"

Write-Host ""
Write-Host "2.4 Dashboard Design has no command -- open $SRC\02_sql_and_viz\presight_dashboard.pbix in Power BI Desktop manually." -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Pillar 3 -- Big Data Processing
# ---------------------------------------------------------------------------
if (-not $SkipSpark) {
    Step 6 "Spark: process events at scale (3.1)"
    $env:JAVA_HOME = $JAVA_HOME
    $env:HADOOP_HOME = $HADOOP_HOME
    $env:Path = "$env:HADOOP_HOME\bin;$env:JAVA_HOME\bin;$env:Path"
    $env:PYSPARK_PYTHON = "$PWD\.venv\Scripts\python.exe"
    $env:PYSPARK_DRIVER_PYTHON = "$PWD\.venv\Scripts\python.exe"
    & $PY "$SRC\03_big_data\spark_pipeline.py"
} else {
    Write-Host "Skipping Step 6 (Spark) -- -SkipSpark passed." -ForegroundColor DarkGray
}

if (-not $SkipKafka) {
    Step 7 "Kafka: producer + consumer (3.2, ~7 min)"
    & $PY "$SRC\03_big_data\kafka_streaming.py" --mode both
} else {
    Write-Host "Skipping Step 7 (Kafka) -- -SkipKafka passed." -ForegroundColor DarkGray
}

if (-not $SkipAirflow) {
    Step 8 "Airflow: deploy + trigger DAG (3.3)"
    & "$SRC\03_big_data\deploy_dag.ps1"
    Start-Sleep -Seconds 5
    docker exec presight-airflow-webserver airflow dags trigger presight_etl_pipeline
    Write-Host "DAG triggered -- check progress at http://localhost:8081 (admin/admin)." -ForegroundColor DarkGray
} else {
    Write-Host "Skipping Step 8 (Airflow) -- -SkipAirflow passed." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Pillar 4 -- Infrastructure & Governance
# ---------------------------------------------------------------------------
if (-not $SkipDocker) {
    Step 9 "Docker: containerise the ETL pipeline (4.1)"
    docker build -t presight-etl .
    docker run --rm -v "${PWD}/outputs:/app/outputs" presight-etl
} else {
    Write-Host "Skipping Step 9 (Docker) -- -SkipDocker passed." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "4.2 Data Governance Document has no command -- it's a static file at outputs\results\baiju_mohan\04_infrastructure\data_governance_document.md." -ForegroundColor DarkGray
Write-Host "4.3 Data Quality Framework already ran as part of Step 8's DAG trigger -- see outputs\results\baiju_mohan\04_infrastructure\dq_report_*.md." -ForegroundColor DarkGray

$elapsed = (Get-Date) - $started
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "  Done. Total elapsed: $($elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green

# Pillar 3 — Validation Evidence

Real numbers from actually running Spark, Kafka, and the Airflow DAG against live
Docker services — not restated claims. Commands to reproduce each check are included.

## Task 3.1 — Spark (`spark_pipeline.py`)

| Check | Result |
|---|---|
| Raw event rows loaded (all 12 monthly files) | 99,996 |
| Rows dropped (null `event_id`/`user_id`) | 0 |
| Rows dropped (duplicate `event_id`) | 0 |
| Total execution time | 82.80s |
| Throughput | 1,208 events/sec |

Per-table output, all 5 written as Parquet under
`outputs/artifacts/baiju_mohan/03_big_data/spark/`:

| Table | Rows | Build time |
|---|---|---|
| `project_activity_summary` | 500 | 6.34s |
| `user_activity_summary` | 960 | 4.68s |
| `escalation_log` (partitioned by `severity`) | 1,969 | 21.83s |
| `daily_event_volume` (partitioned by `event_date`) | 5,088 | 3.61s |
| `peak_usage_analysis` | 20 | 2.90s |

```powershell
$env:JAVA_HOME = "<path to JDK 17>"
$env:HADOOP_HOME = "C:\hadoop"
$env:Path = "$env:HADOOP_HOME\bin;$env:Path"
$env:PYSPARK_PYTHON = "$PWD\.venv\Scripts\python.exe"
$env:PYSPARK_DRIVER_PYTHON = "$PWD\.venv\Scripts\python.exe"
.venv\Scripts\python.exe solutions\submissions\baiju_mohan\03_big_data\spark_pipeline.py
dir outputs\artifacts\baiju_mohan\03_big_data\spark   # 5 subfolders
```

## Task 3.2 — Kafka (`kafka_streaming.py --mode both`)

Full 12,333-event dataset streamed live against `presight-kafka`/`presight-kafka-ui`
(no mocked broker):

| Check | Result |
|---|---|
| Messages produced | 8,333 |
| Messages consumed | 8,333 (matches produced — no loss) |
| Critical escalations forwarded to `presight.escalations.critical` | 14 |
| Consumer elapsed time | 14.22s |
| Consumer throughput | 585.9 messages/sec |
| `escalation_raised` events in the stream | 178 |
| `escalation_resolved` events in the stream | 158 |

```powershell
python solutions/submissions/baiju_mohan/03_big_data/kafka_streaming.py --mode both
type outputs\results\baiju_mohan\03_big_data\kafka\summary.json
```

`total_messages_consumed` == `total_messages_consumed` sent by the producer confirms
no message loss end-to-end; `critical_escalations_forwarded` > 0 confirms the
severity-based forwarding logic actually fired, not just parsed.

## Task 3.3 — Airflow (`presight_etl_pipeline` DAG)

Manually triggered run `manual__2026-08-24T07:50:25+00:00` — real execution against
the deployed DAG, not a dry run:

| Check | Result |
|---|---|
| DAG run state | `success` |
| Run duration | ~21s |
| Row counts (raw → clean) | projects 500→500, employees 1000→1000, transactions 50000→50000 |

DQ gate results (`validate_data_quality` task, run against **raw** data before
cleaning — this is the gate, not a report on the cleaned output):

| Dataset | Checks passed |
|---|---|
| projects | 6/9 |
| employees | 3/9 |
| transactions | 6/9 |

None of these failures block the DAG — only primary-key completeness below 80% would
(`CRITICAL_COMPLETENESS_THRESHOLD` in `airflow_dag.py`), and all three datasets pass
that specific check. The failing checks here are the same known raw-data issues
Pillar 1 documents and fixes downstream (e.g. employees' 8 unparseable/implausible
`hire_date` values, 5 out-of-range `years_experience`, 3 salary/level mismatches) —
the gate is reporting them, not missing them.

```powershell
docker exec presight-airflow-webserver airflow dags list-runs -d presight_etl_pipeline
type outputs\results\baiju_mohan\03_big_data\pipeline_report_2026-08-24.txt
```

**A note on `04_infrastructure`'s `dq_report_*.md` files**: those are a separate,
standalone artifact from `dq_framework.py`'s `write_dq_report_markdown()` function,
which nothing in this DAG calls — `task_validate_data_quality` only pushes
`checks_run`/`checks_passed`/`checks_failed` to XCom for `pipeline_report_<date>.txt`
above. Re-running the same check directly against current code confirmed the DAG's
live numbers (employees 3/9) are correct; the existing `dq_report_employees.md`
(5/9, dated 2026-08-23) predates a framework change and is stale. It reflects a real
gap — nothing currently regenerates those markdown files — not a data discrepancy.

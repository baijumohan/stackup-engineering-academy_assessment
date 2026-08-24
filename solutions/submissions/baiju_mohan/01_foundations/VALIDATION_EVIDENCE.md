# Pillar 1 — Validation Evidence

Real numbers from the actual outputs, not restated claims. Re-verified by re-running the pipeline and querying the warehouse directly — commands to reproduce each check are included.

## Pipeline run

| Check | Result |
|---|---|
| `pipeline_summary.txt` target | < 30s |
| `pipeline_summary.txt` actual | 0.07s (PASS) |

```powershell
python solutions/submissions/baiju_mohan/01_foundations/etl_pipeline.py
type outputs\results\baiju_mohan\01_foundations\pipeline_summary.txt
```

## Task 1.1 — `projects_clean.csv`

| Check | Result |
|---|---|
| Row count (excl. header) | 500 |
| Column count | 17 |
| Required derived columns present | `budget_variance`, `is_over_budget`, `duration_days`, `budget_utilisation_pct`, `status_category`, `risk_level` — all present |

```powershell
(Get-Content outputs\results\baiju_mohan\01_foundations\projects_clean.csv).Count   # 501 (incl. header)
```

## Task 1.3 — `employees_clean.csv`

| Check | Result |
|---|---|
| Row count (excl. header) | 1,000 |
| Column count | 13 |

`employees_quality_summary.json` (machine-readable, not just log lines):
```json
{
  "missing_email_fixed": 10,
  "invalid_hire_date_format_fixed": 5,
  "implausible_hire_date_fixed": 3,
  "years_experience_out_of_range_fixed": 5,
  "salary_level_mismatch_fixed": 3,
  "status_conflicts_found": 0
}
```
The last check (`status_conflicts_found`) is a real query against the data that returns 0 — it isn't omitted just because it found nothing.

## Task 1.2 — `dim_employee` (SCD Type 2)

All 5 validation queries in `data_model.sql` Section 1 return real results, not just "should be zero":

| Check | Result |
|---|---|
| No duplicate `is_current = TRUE` per employee | 0 rows |
| Overlapping `valid_from`/`valid_to` periods (self-join) | 0 rows |
| Row-count sanity check (independently computed expected count) | `actual_rows = 2232`, `expected_rows = 2232` — match |
| Gap check (every period contiguous to the next) | 1 row (`EMP0084`) — see below |
| Total `dim_employee` rows | 2,232 |

```powershell
duckdb outputs\presight_warehouse.duckdb -readonly -c "SELECT COUNT(*) FROM dim_employee;"
```

**The one non-zero result is a known, documented data conflict, not a bug**: `EMP0084`'s salary-history file and `employees_clean.csv` disagree on its final values (see `ASSUMPTIONS.md` #2) — `employees_clean.csv` is used as the source of truth per that documented decision, which is exactly what the gap-check query is surfacing.

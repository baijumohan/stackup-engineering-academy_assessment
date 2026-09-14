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
| Row-count sanity check (independently computed expected count) | `actual_rows = 2231`, `expected_rows = 2231` — match |
| Gap check (every period contiguous to the next) | 0 rows |
| Total `dim_employee` rows | 2,231 |

```powershell
duckdb outputs\presight_warehouse.duckdb -readonly -c "SELECT COUNT(*) FROM dim_employee;"
```

**All five queries return clean 0-row results now** — this wasn't always true, and the earlier version of this document mischaracterized why. The gap-check used to return 1 row for `EMP0084`, and this doc previously attributed that to the unrelated "`EMP0084`'s current values disagree with its salary history" data conflict (`ASSUMPTIONS.md` #2). That explanation was wrong. The real cause: `EMP0084` has two salary-history events on the *same* `effective_date` (an Annual Raise and a Promotion, both 2025-03-02). `valid_to` is computed as `LEAD(effective_date) - 1 day`, so two versions sharing one `valid_from` leaves no room for a distinct interval — the earlier-in-the-day version got `valid_to` one day *before* its own `valid_from`. The overlap check (Q3) couldn't catch this (it assumes `valid_to >= valid_from`), only the gap check (Q5) could. Fixed in `data_model.sql` by collapsing same-day history rows to their terminal state via the `previous_salary`/`new_salary` chain before building versions — `dim_employee` dropped from 2,232 to 2,231 rows as a result (the superseded intra-day row no longer produces a version). `EMP0084`'s current-row values now agree exactly with its (correctly resolved) last history row, too — the old "disagreement" in `ASSUMPTIONS.md` #2 was itself a symptom of this same bug, not a separate data conflict.

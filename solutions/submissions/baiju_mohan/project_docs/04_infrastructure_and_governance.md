# Infrastructure & Governance: Making the Pipeline Deployable, Compliant, and Self-Checking

## 1. Executive Summary

A pipeline that only runs on the machine it was built on is a demo, not a deliverable. And one that touches salary history and government-client data without a governance story isn't something Compliance can sign off on. This pillar closes both gaps: a multi-stage Docker build for the Pillar 2 ETL, a full governance document across all four datasets, and a configurable DQ framework the team can extend by editing a config, not by touching code.

The container runs the full 50,000-transaction ETL in under 17 seconds against a 30s target. The DQ framework runs 9 checks against real data with genuinely mixed pass/fail results — I ran it against the raw datasets, not tuned it to look clean.

## 2. Business Problem

Three gaps. Deployability: the pipeline only ran as "run this file on my laptop" — nothing DevOps could hand to a scheduler. Compliance: salary history and government-client project data with no documented answer to who can access what, and under what regulation. Extensibility: DQ checks existed as one-off logic in pipeline code — every new rule meant a code change and a deploy.

## 3. Project Scope

**In scope:** a multi-stage Dockerfile + `.dockerignore` for the Pillar 2 ETL; a governance document across all four datasets; a config-driven DQ framework with 6+ checks (built 9).

**Out of scope:** actual cloud deployment (the env-var configuration makes that step straightforward later, not a rewrite); a secrets manager (nothing here needs one); final legal sign-off on retention periods (documented as defensible defaults, flagged for Legal review, not presented as settled law).

## 4. Technology Stack

| Technology | Role in the Project | Why It Was Chosen |
|---|---|---|
| Docker | Containerises the ETL into a portable artifact | Standard "runs the same way everywhere" — eliminates "works on my machine" |
| Multi-stage build | Separates the dependency-install stage from the runtime image | `requirements.txt` pulls in a large tree (incl. Airflow's); a single stage would ship all of pip's build cache in the final image |
| Docker Compose override | Adds a bonus `etl` service + env vars without editing the fixed `docker-compose.yml` | Keeps additions separate from provided infra; Compose merges overrides automatically |
| Python (config-driven) | The DQ check engine (`dq_framework.py`) | A plain dict-driven design gave real configurability without a heavier framework |

## 5. High-Level Architecture & Data Flow

```mermaid
flowchart TD
    subgraph Build["Docker build (two stages)"]
        Builder["builder stage:\npython:3.11-slim\n+ full requirements.txt install"]
        Runtime["runtime stage:\npython:3.11-slim\n+ copies ONLY /opt/venv + solution code"]
    end
    Builder -- "copy built venv only" --> Runtime

    Runtime --> Container["presight-etl container"]
    Vol["./outputs volume mount"] <--> Container
    Container --> Run["etl_full.py executes\n(0.92s pipeline time,\n16.8s total wall-clock)"]

    subgraph DQ["dq_framework.py"]
        Config["DQ_CONFIG dict\n(thresholds, PK columns,\nranges, FK relationships)"]
        Checks["9 checks:\ncompleteness, uniqueness,\nvalidity (numeric/date),\nconsistency, referential integrity,\ndistribution, freshness, outliers"]
    end
    Config --> Checks
    Checks --> Results["Structured result dict\n+ WARNING logs on FAIL"]
    Results --> MD["dq_report_{dataset}.md\nper dataset"]

    subgraph Gov["data_governance.md"]
        Inv["Inventory"] --> Class["Classification\n(PII: GDPR + UAE PDPL)"]
        Class --> Own["Ownership\n(Owner vs Steward)"]
        Own --> Ret["Retention\n(salary history: longer window)"]
        Ret --> Access["Access control\n(least privilege)"]
        Access --> Lineage["Data lineage diagram"]
    end
```

## 6. My Responsibilities & Contributions

Wrote the Dockerfile and `.dockerignore`, the full governance document across all four datasets, and the DQ framework's config schema and all 9 checks. Verified all of it by actually running the container and the framework against real data.

## 7. Key Engineering Decisions

**Multi-stage build to contain a literal instruction's cost.** The task specified installing `requirements.txt` as-is, which pulls in Airflow's full dependency tree — far more than `etl_full.py` needs, and slow to resolve. Rather than quietly trim the file, I kept it as instructed and used the multi-stage split to keep that cost out of the runtime image.

**Config-driven DQ rules.** Every check reads thresholds, PK columns, and FK relationships out of `DQ_CONFIG` — none hardcode a column name. A new rule means a config entry, not a code change.

**Narrower Data Engineer access on salary history.** The instinct is "engineers get broad access." I gave Data Engineers Read, not Read+Write, on `employees_salary_history` — the pipeline only needs to read it for the SCD2 build; corrections belong in HR's own tooling. The one place I went narrower than the obvious call.

**Reused the Pillar 3 env-var mechanism.** The container needed `DATA_DIR`/`OUTPUT_DIR` to resolve inside its own filesystem — same problem the Airflow container hit. Already solved, so containerising here was configuration, not new code.

## 8. Challenges & How I Solved Them

**A distribution check that was a permanent false positive.** The "flag if >30% of a column shares one value" check correctly caught real issues in `category`/`payment_status`, but also flagged `currency` — legitimately 100% "AED" by design. Excluded it from that config entry rather than let it become noise nobody trusts.

**Keeping the "6+ checks" requirement honest.** Easy to write nine checks that all trivially pass. Ran the framework against the real, uncleaned data instead — results are genuinely mixed (6/9, 3/9, 6/9 across the three datasets), with specific real failures, not a suspiciously clean report.

## 9. Data Quality, Reliability, Security & Performance

Every DQ failure logs at `WARNING` with the column and count — the log output is the audit trail. The governance doc tags every PII column with GDPR/UAE PDPL, and gives salary history a longer retention window for the payroll/tax-audit angle, flagged for Legal confirmation rather than presented as settled.

Performance: 0.92s pipeline time, 16.8s wall-clock including Docker startup, against a 30s target — timed by actually running `docker run`.

## 10. Outcome & Business Value

DevOps gets a container that builds cleanly and runs well under target, ready for a scheduler or registry without rework. Compliance gets a governance doc that actually answers who can touch salary history and why. The Data Quality team gets a framework extendable by editing a dict, with 9 checks already proven against real data. This is the piece that turns "works" into "ready to hand to someone else."

"""
Driver for Pillar 2, Task 2.3 (query_optimization.sql) — parses the setup
block, original query, rewritten query, and indexes straight out of that
.sql file (no queries duplicated in Python), loads plain (unindexed)
employees/projects/transactions tables, then benchmarks original vs.
rewritten, then again after adding the indexes.
"""

import os
import time

import duckdb

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
SQL_FILE = os.path.join(BASE_DIR, "solutions", "submissions", "baiju_mohan", "02_sql_and_viz", "query_optimization.sql")
RESULTS_DIR = os.path.join(BASE_DIR, "outputs", "results", "baiju_mohan", "02_sql_and_viz").replace("\\", "/")


def split_sections(sql_text: str):
    setup_end = sql_text.index("-- ORIGINAL QUERY (unmodified from the starter file)")
    orig_end = sql_text.index("-- 4a) EXPLAIN ANALYZE")
    rewritten_start = sql_text.index("-- 4b) REWRITTEN QUERY")
    rewritten_end = sql_text.index("-- 4c) Indexes")
    indexes_end = sql_text.index("-- 4d) Benchmark")
    return (
        sql_text[:setup_end],
        sql_text[setup_end:orig_end],
        sql_text[rewritten_start:rewritten_end],
        sql_text[rewritten_end:indexes_end],
    )


def bench(con, query, n=5):
    times = []
    for _ in range(n):
        t0 = time.perf_counter()
        result = con.execute(query).fetchdf()
        times.append(time.perf_counter() - t0)
    return result, times


def main():
    with open(SQL_FILE, "r", encoding="utf-8") as f:
        sql_text = f.read()
    sql_text = sql_text.replace("__RESULTS__", RESULTS_DIR)

    setup_sql, original_query, rewritten_query, index_sql = split_sections(sql_text)

    con = duckdb.connect(":memory:")
    con.execute(setup_sql)
    print("Loaded: employees=%d projects=%d transactions=%d" % (
        con.execute("SELECT COUNT(*) FROM employees").fetchone()[0],
        con.execute("SELECT COUNT(*) FROM projects").fetchone()[0],
        con.execute("SELECT COUNT(*) FROM transactions").fetchone()[0],
    ))

    print("\n--- EXPLAIN ANALYZE: original query ---")
    for row in con.execute("EXPLAIN ANALYZE " + original_query).fetchall():
        print(row[-1])
    result, times = bench(con, original_query)
    print(f"Original: {len(result)} rows | best={min(times)*1000:.2f}ms | runs(ms)={[round(t*1000,2) for t in times]}")

    print("\n--- EXPLAIN ANALYZE: rewritten query ---")
    for row in con.execute("EXPLAIN ANALYZE " + rewritten_query).fetchall():
        print(row[-1])
    result2, times2 = bench(con, rewritten_query)
    print(f"Rewritten: {len(result2)} rows | best={min(times2)*1000:.2f}ms | runs(ms)={[round(t*1000,2) for t in times2]}")

    assert len(result) == len(result2), "row count mismatch between original and rewritten query!"
    print(f"\nRow counts match: {len(result)} == {len(result2)}")
    print(f"Speedup (best-of-5): {min(times)/min(times2):.2f}x")

    print("\n--- With indexes (4c) ---")
    con.execute(index_sql)
    result3, times3 = bench(con, rewritten_query)
    print(f"Rewritten+indexed: {len(result3)} rows | best={min(times3)*1000:.2f}ms | runs(ms)={[round(t*1000,2) for t in times3]}")


if __name__ == "__main__":
    main()

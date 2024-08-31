-- Schema in `schema_constrexpr.sql`
----------------------


-- Queries for Constraint Exclusion tests
EXPLAIN ANALYZE SELECT * FROM tbl1 WHERE value > 0 AND value <= 0;

EXPLAIN ANALYZE SELECT * FROM tbl1 t1 JOIN tbl2 t2 ON t1.value > 0 WHERE t1.value <= 0;


----------------------
-- More complex queries
EXPLAIN ANALYZE SELECT * FROM tbl1 t1 JOIN tbl2 t2 ON t1.id = t2.id AND t1.value > 0 WHERE t1.value <= 0;

EXPLAIN ANALYZE SELECT * FROM tbl1 t1
JOIN LATERAL (
    SELECT MAX(value) FROM tbl2 GROUP BY id WHERE t1.value > 0
) t2 ON t1.id = t2.id
WHERE t1.value <= 0;
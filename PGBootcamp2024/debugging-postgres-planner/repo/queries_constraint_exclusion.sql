-- Schema setup (run once)

CREATE TABLE tbl1(
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    value INTEGER
);
INSERT INTO tbl1(value) SELECT (random() * 1000)::INTEGER FROM generate_series(1, 1000);

CREATE TABLE tbl2(
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    value INTEGER
);
INSERT INTO tbl1(value) SELECT (random() * 1000)::INTEGER FROM generate_series(1, 1000);

ANALYZE tbl1;
ANALYZE tbl2;

-- Queries for Constraint Exclusion tests

SELECT * FROM tbl1 WHERE value > 0 AND value <= 0;

SELECT * FROM tbl1 t1 JOIN tbl2 t2 ON t1.value > 0 WHERE t1.value <= 0;

-- More complex queries
SELECT * FROM tbl1 t1 JOIN tbl2 t2 ON t1.id = t2.id AND t1.value > 0 WHERE t1.value <= 0;

SELECT * FROM tbl1 t1
JOIN LATERAL (
    SELECT MAX(value) FROM tbl2 GROUP BY id WHERE t1.value > 0
) t2 ON t1.id = t2.id
WHERE t1.value <= 0;

-- TODO: check self-join
SELECT * FROM tbl1 t1
JOIN tbl2 t2 ON t1.id = t2.id
WHERE t1.value > 0 AND t1.value <= 0;
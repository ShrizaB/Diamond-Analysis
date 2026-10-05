-- PostgreSQL 14+ | Diamonds price analysis
-- Run:  psql -d yourdb -v csv="'/full/path/diamonds_clean.csv'" -f diamonds.sql
-- (use \copy instead of COPY if the server cannot read your local file)

DROP SCHEMA IF EXISTS dia CASCADE;
CREATE SCHEMA dia;

CREATE TABLE dia.diamonds (
  id      integer PRIMARY KEY,
  carat   numeric(4,2) NOT NULL CHECK (carat > 0),
  cut     text NOT NULL CHECK (cut     IN ('Fair','Good','Very Good','Premium','Ideal')),
  color   text NOT NULL CHECK (color   IN ('D','E','F','G','H','I','J')),
  clarity text NOT NULL CHECK (clarity IN ('I1','SI2','SI1','VS2','VS1','VVS2','VVS1','IF')),
  depth   numeric(4,1), "table" numeric(4,1),
  price   integer NOT NULL CHECK (price > 0),
  x numeric(5,2) CHECK (x > 0), y numeric(5,2) CHECK (y > 0), z numeric(5,2) CHECK (z > 0)
);

COPY dia.diamonds FROM :csv WITH (FORMAT csv, HEADER true);

-- Ordered grade dimensions (so Power BI/Excel sort quality properly)
CREATE TABLE dia.clarity_rank (clarity text PRIMARY KEY, rnk int);
INSERT INTO dia.clarity_rank VALUES ('I1',1),('SI2',2),('SI1',3),('VS2',4),('VS1',5),('VVS2',6),('VVS1',7),('IF',8);
CREATE TABLE dia.cut_rank (cut text PRIMARY KEY, rnk int);
INSERT INTO dia.cut_rank VALUES ('Fair',1),('Good',2),('Very Good',3),('Premium',4),('Ideal',5);
CREATE TABLE dia.color_rank (color text PRIMARY KEY, rnk int);
INSERT INTO dia.color_rank VALUES ('J',1),('I',2),('H',3),('G',4),('F',5),('E',6),('D',7);

-- Fact view for Power BI
CREATE VIEW dia.v_diamonds AS
SELECT d.*,
       round(price / carat, 0)                          AS price_per_carat,
       ln(price)                                        AS ln_price,
       ln(carat)                                        AS ln_carat,
       CASE WHEN carat < 0.5 THEN '1: <0.5'
            WHEN carat < 1   THEN '2: 0.5-0.99'
            WHEN carat < 1.5 THEN '3: 1.0-1.49'
            WHEN carat < 2   THEN '4: 1.5-1.99'
            ELSE '5: 2.0+' END                          AS carat_band,
       ntile(5) OVER (ORDER BY price)                   AS price_quintile
FROM dia.diamonds d;

-- Q1 Data quality profile
SELECT count(*) AS n, count(DISTINCT (carat,cut,color,clarity,depth,"table",price,x,y,z)) AS distinct_rows,
       min(price) AS min_price, max(price) AS max_price,
       round(avg(price)) AS mean_price,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM dia.diamonds;

-- Q2 Clarity effect, size held roughly constant (0.9-1.1 ct)
SELECT d.clarity, count(*) AS n,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM dia.diamonds d JOIN dia.clarity_rank r USING (clarity)
WHERE carat BETWEEN 0.9 AND 1.1
GROUP BY d.clarity, r.rnk ORDER BY r.rnk;

-- Q3 Log-log regression: price elasticity of carat (carat-only model)
SELECT round(regr_slope(ln_price, ln_carat)::numeric, 3)     AS elasticity,
       round(regr_intercept(ln_price, ln_carat)::numeric, 3) AS intercept,
       round(regr_r2(ln_price, ln_carat)::numeric, 3)        AS r2,
       round(corr(ln_price, ln_carat)::numeric, 3)           AS r
FROM dia.v_diamonds;

-- Q4 Paradox check: Fair/Good cuts can look pricier on average because they are bigger
SELECT cut, round(avg(carat),2) AS avg_carat, round(avg(price)) AS avg_price,
       round(avg(price/carat)) AS avg_price_per_carat
FROM dia.diamonds GROUP BY cut ORDER BY avg_price;

-- Q5 Each stone's price relative to the median of its size-band + clarity peers
-- (percentile_cont is an ordered-set aggregate: it cannot be used with OVER, so group then join)
WITH med AS (
  SELECT carat_band, clarity,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY price) AS band_median
  FROM dia.v_diamonds GROUP BY carat_band, clarity
)
SELECT v.carat_band, v.clarity, count(*) AS n,
       round(avg(v.price / m.band_median)::numeric, 3) AS avg_ratio_to_band_median
FROM dia.v_diamonds v JOIN med m USING (carat_band, clarity)
GROUP BY v.carat_band, v.clarity ORDER BY v.carat_band, v.clarity;

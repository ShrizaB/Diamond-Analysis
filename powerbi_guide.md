# Power BI build guide (about 20 minutes)

I can't generate a .pbix file here, so this is the exact recipe. Everything is defined on top of the PostgreSQL views, so the numbers match the SQL and Excel.

## 1. Connect
Home > Get data > PostgreSQL database > server/db > **Import** mode.
Select: `dia.v_diamonds`, `dia.clarity_rank`, `dia.cut_rank`, `dia.color_rank`.
(Alternative with no database: Get data > Excel > `diamonds_analysis.xlsx` > Data sheet. Rename columns to match.)

## 2. Model
- Relationships (many-to-one, single direction): `v_diamonds[clarity]` > `clarity_rank[clarity]`, same for `cut` and `color`.
- Set **Sort by column**: `clarity_rank[clarity]` by `rnk`, `cut_rank[cut]` by `rnk`, `color_rank[color]` by `rnk`. Hide `rnk`.
- Use the rank-table columns on all axes and slicers so quality sorts low to high.
- Format `price` as currency, `carat` as 0.00.

## 3. DAX measures (create in a `_Measures` table)
```DAX
Diamonds = COUNTROWS(v_diamonds)
Avg Price = AVERAGE(v_diamonds[price])
Median Price = MEDIAN(v_diamonds[price])
Avg Carat = AVERAGE(v_diamonds[carat])
Avg Price per Carat = DIVIDE(SUM(v_diamonds[price]), SUM(v_diamonds[carat]))

Avg Price (0.9-1.1ct) =
CALCULATE([Avg Price], v_diamonds[carat] >= 0.9, v_diamonds[carat] <= 1.1)

-- Log-log elasticity (matches SQL regr_slope and Excel SLOPE: 1.677)
Elasticity =
VAR t = SUMMARIZE(v_diamonds, v_diamonds[id], v_diamonds[ln_price], v_diamonds[ln_carat])
VAR n = COUNTROWS(t)
VAR sx = SUMX(t, v_diamonds[ln_carat])
VAR sy = SUMX(t, v_diamonds[ln_price])
VAR sxy = SUMX(t, v_diamonds[ln_carat] * v_diamonds[ln_price])
VAR sxx = SUMX(t, v_diamonds[ln_carat] ^ 2)
RETURN DIVIDE(n * sxy - sx * sy, n * sxx - sx ^ 2)

-- Price relative to the overall average, to expose the cut paradox
Price Index vs All = DIVIDE([Avg Price], CALCULATE([Avg Price], ALL(v_diamonds)))
Size Index vs All  = DIVIDE([Avg Carat], CALCULATE([Avg Carat], ALL(v_diamonds)))
```

## 4. Report pages (three, no more)
**Page 1: Overview.** KPI cards (`Diamonds`, `Avg Price`, `Median Price`, `Avg Carat`). Histogram-style column chart: `carat_band` vs `Diamonds`. Slicers: cut, color, clarity.

**Page 2: What drives price.** Scatter: x = `carat`, y = `price` (use a sample or the density option), log axis on both, add a trend line (it will be near-linear, which is the point). Column chart: `Avg Price (0.9-1.1ct)` by clarity. Matrix: clarity rows by color columns, value `Avg Price per Carat`, conditional-format background.

**Page 3: Cut paradox.** Clustered bars by cut with `Avg Carat`, `Avg Price`, `Avg Price per Carat`. Message: Fair and Good cuts show higher average price only because stones are bigger. Per carat the order is roughly flat.

## 5. Checks before sharing
- `Diamonds` = 53,772; `Elasticity` = 1.677 (card on page 2).
- Median price = 2,401; mean = 3,931.
- Clarity chart should rise monotonically from I1 (about 2.7k) to IF (about 10.6k) at 0.9 to 1.1 ct.

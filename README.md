# Diamonds price analysis (Python, Excel, PostgreSQL, Power BI)

How much of a diamond's price can be predicted from its specs and grades, and what drives it?

**Headline results** (53,772 clean rows)
- Log carat alone explains 93% of log-price variance; price elasticity of carat is about 1.68.
- At 0.9-1.1 ct, median price rises from about $2.7k (I1) to about $10k (IF) across clarity grades.
- Gradient boosting reaches 7.4% MAPE vs 10.4% for log-log OLS (paired bootstrap 95% CI for the gap: 2.93 to 3.06 points).

## Files
| File | Purpose |
|---|---|
| `diamonds_raw.csv` | Original data (Seaborn `diamonds`) |
| `diamonds_clean.csv` | Deduplicated, impossible dimensions removed, with `id` |
| `diamonds_analysis.py` | Cleaning, EDA, 5-fold CV model comparison, bootstrap CI |
| `diamonds.sql` | PostgreSQL schema, load, views, five analysis queries |
| `build_xlsx.py` | Builds `diamonds_analysis.xlsx` (live formulas) |
| `diamonds_analysis.xlsx` | Excel summary workbook |
| `powerbi_guide.md` | Power BI model, DAX measures and report layout |

## Run
```bash
pip install -r requirements.txt
python diamonds_analysis.py
python build_xlsx.py
psql -d yourdb -v csv="'$(pwd)/diamonds_clean.csv'" -f diamonds.sql
```

## Caveats
Carat and volume are collinear, so coefficients are conditional estimates. CV uses random splits; the data has no dates, so drift over time can't be tested.

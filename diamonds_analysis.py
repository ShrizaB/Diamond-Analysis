import numpy as np, pandas as pd, warnings
warnings.filterwarnings("ignore")
from sklearn.model_selection import KFold, cross_val_predict
from sklearn.pipeline import make_pipeline
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, OrdinalEncoder
from sklearn.linear_model import LinearRegression
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.dummy import DummyRegressor
from sklearn.metrics import mean_absolute_percentage_error as mape, r2_score

df = pd.read_csv("diamonds_raw.csv")
print("rows=%d dupes=%d missing=%d"%(len(df),df.duplicated().sum(),df.isna().sum().sum()))
bad = (df[["x","y","z"]]==0).any(axis=1) | (df.y>30) | (df.z>30)
print("impossible dims removed:", int(bad.sum()))
df = df[~bad].drop_duplicates().reset_index(drop=True)
print("clean rows:", len(df))

# EDA: price skew, and what the log transform does
print("\nprice skew raw=%.2f log=%.2f"%(df.price.skew(), np.log(df.price).skew()))
print("corr(log price, log carat)=%.3f"%np.corrcoef(np.log(df.price),np.log(df.carat))[0,1])
print("\nMedian price/carat by quality (carat 0.9-1.1, fixes size):")
s = df[df.carat.between(.9,1.1)]
print(s.groupby("clarity").price.median().reindex(["I1","SI2","SI1","VS2","VS1","VVS2","VVS1","IF"]).round(0).to_string())

# Features
df["lcarat"]=np.log(df.carat); df["vol"]=np.log(df.x*df.y*df.z)
cuts=["Fair","Good","Very Good","Premium","Ideal"]; cols=list("JIHGFED"); cl=["I1","SI2","SI1","VS2","VS1","VVS2","VVS1","IF"]
num=["lcarat","depth","table","vol"]; cat=["cut","color","clarity"]
y = np.log(df.price)
lin = ColumnTransformer([("c",OneHotEncoder(drop="first"),cat)],remainder="passthrough")
gb = ColumnTransformer([("o",OrdinalEncoder(categories=[cuts,cols,cl]),cat)],remainder="passthrough")
models = {
 "baseline(mean)": make_pipeline(gb, DummyRegressor()),
 "carat-only OLS": None,
 "OLS (log-log)": make_pipeline(lin, LinearRegression()),
 "GradBoost": make_pipeline(gb, HistGradientBoostingRegressor(max_iter=300,learning_rate=.1,random_state=0)),
}
cv = KFold(5, shuffle=True, random_state=0)
res=[]; preds={}
for n,m in models.items():
    cols_ = ["lcarat"] if n=="carat-only OLS" else num+cat
    m = m or LinearRegression()
    p = cross_val_predict(m, df[cols_], y, cv=cv); preds[n]=p
    res.append((n, r2_score(y,p), mape(df.price,np.exp(p))*100))
print("\n5-fold CV (out-of-fold):")
print(pd.DataFrame(res,columns=["model","R2(log)","MAPE % (price)"]).round(3).to_string(index=False))

# Bootstrap CI on the MAPE gap between OLS and GB (paired)
rng=np.random.default_rng(0); a=np.abs(df.price-np.exp(preds["OLS (log-log)"]))/df.price
b=np.abs(df.price-np.exp(preds["GradBoost"]))/df.price; d=(a-b).values
bs=[d[rng.integers(0,len(d),len(d))].mean()*100 for _ in range(1000)]
print("\nMAPE improvement GB vs OLS: %.2f pts, 95%% CI [%.2f, %.2f]"%(d.mean()*100,*np.percentile(bs,[2.5,97.5])))

# Error by segment: where does the model fail?
df["err"]=b.values*100
df["bin"]=pd.qcut(df.price,5,labels=["Q1 cheap","Q2","Q3","Q4","Q5 expensive"])
print("\nGB MAPE by price quintile:\n", df.groupby("bin").err.mean().round(2).to_string())

# OLS interpretable elasticity
ols=models["OLS (log-log)"].fit(df[num+cat],y)
print("\nElasticity of price to carat: %.2f (1%% more carat -> %.2f%% more price)"%(ols[-1].coef_[-4],ols[-1].coef_[-4]))

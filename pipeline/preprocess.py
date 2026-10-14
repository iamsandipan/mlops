"""Split the raw CSV into train and validation sets for built-in XGBoost.

Runs inside the SageMaker processing container. Expects a CSV with a header
row and the label in the first column.
"""
import pandas as pd
from sklearn.model_selection import train_test_split

df = pd.read_csv("/opt/ml/processing/input/data.csv").dropna()
train, val = train_test_split(df, test_size=0.2, random_state=42)

# Built-in XGBoost wants no header and the label first.
train.to_csv("/opt/ml/processing/train/train.csv", header=False, index=False)
val.to_csv("/opt/ml/processing/validation/validation.csv", header=False, index=False)

#!/usr/bin/env python3
"""Download the full IBM / Kaggle Telco Customer Churn file into data/raw_full/ and verify its SHA-256.

Dataset : "Telco Customer Churn" (IBM Sample Data Sets, uploaded to Kaggle by BlastChar),
          Kaggle: https://www.kaggle.com/datasets/blastchar/telco-customer-churn
          7,043 customers x 21 columns, WA_Fn-UseC_-Telco-Customer-Churn.csv (977,501 bytes, CRLF line endings).
Licence : Kaggle lists "Data files (c) Original Authors" (IBM sample data, no explicit open licence on Kaggle).
          IBM's own GitHub copy sits in an Apache-2.0 repository; the Hugging Face copy is tagged CC BY 4.0 by its uploader.
There is no Kaggle API key here, so the file comes from public mirrors. Two byte-level variants exist:
  * EXACT  : identical to the Kaggle file (977,501 B, CRLF, SHA-256 88be4b93...), used as is;
  * LF     : the same 7,044 lines with LF endings (970,457 B, SHA-256 16320c9c...), e.g. IBM's own repo and Hugging Face;
             these are converted LF -> CRLF, which reproduces the Kaggle bytes exactly (checked against the SHA-256).
The script tries the mirrors in order and stops at the first copy that yields the Kaggle SHA-256.
The original bytes are kept in data/orig/ and copied unchanged to data/raw_full/ (both gitignored).
"""
import hashlib, pathlib, shutil, sys, time, urllib.request

NAME = "WA_Fn-UseC_-Telco-Customer-Churn.csv"
SHA256 = "88be4b93fbe0cc83421af1c503794c97c342eca914c1576db7c276e61d61358a"      # Kaggle bytes (CRLF)
SHA256_LF = "16320c9c1ec72448db59aa0a26a0b95401046bef5d02fd3aeb906448e3055e91"   # same content, LF endings
SIZE = 977_501
MIRRORS = [
    "https://raw.githubusercontent.com/carlosfab/dsnp2/master/datasets/WA_Fn-UseC_-Telco-Customer-Churn.csv",          # EXACT
    "https://raw.githubusercontent.com/dsrscientist/DSData/master/Telecom_customer_churn.csv",                          # EXACT
    "https://raw.githubusercontent.com/srees1988/predict-churn-py/main/customer_churn_data.csv",                        # EXACT
    "https://raw.githubusercontent.com/IBM/telco-customer-churn-on-icp4d/master/data/Telco-Customer-Churn.csv",         # LF
    "https://raw.githubusercontent.com/treselle-systems/customer_churn_analysis/master/WA_Fn-UseC_-Telco-Customer-Churn.csv",  # LF
    "https://huggingface.co/datasets/scikit-learn/churn-prediction/resolve/main/dataset.csv",                           # LF
]
root = pathlib.Path(__file__).resolve().parents[1]
orig, out = root / "data" / "orig", root / "data" / "raw_full"
orig.mkdir(parents=True, exist_ok=True); out.mkdir(parents=True, exist_ok=True)


def fetch(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            print(f"  attempt {i + 1} failed: {e}")
            time.sleep(2 * (i + 1))
    return b""


def sha(b):
    return hashlib.sha256(b).hexdigest()


cached = orig / NAME
raw = cached.read_bytes() if cached.exists() else b""
route = "cache (data/orig)"
if sha(raw) != SHA256:
    for url in MIRRORS:
        print("downloading", url)
        raw = fetch(url)
        if sha(raw) == SHA256_LF:
            raw = raw.replace(b"\n", b"\r\n")
            print("  LF variant -> converted to CRLF")
        if sha(raw) == SHA256:
            route = url
            cached.write_bytes(raw)
            break
        print(f"  wrong checksum / empty ({len(raw):,d} B), trying next mirror")
    else:
        sys.exit("no mirror returned the expected file (sha256 " + SHA256 + ")")
shutil.copyfile(cached, out / NAME)
print(f"{NAME}: {len(raw):,d} B (expected {SIZE:,d}) sha256 {SHA256} OK via {route} -> data/raw_full/{NAME}")

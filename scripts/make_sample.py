#!/usr/bin/env python3
"""Build the reproducible raw sample data/raw/WA_Fn-UseC_-Telco-Customer-Churn.csv from data/raw_full/.

Rule (deterministic, no randomness), applied to the original lines, which are copied byte-for-byte (same header,
CRLF line endings, the blank ' ' TotalCharges values):
  * every customer whose zlib.crc32(customerID) % 5 = 0                         (~20% hash sample)
  * every anomaly row: blank TotalCharges (tenure 0), TotalCharges more than 25% away from MonthlyCharges x tenure,
    and every customer whose 19 non-id attributes are identical to another customer's
so every cleaning rule and flag in sql/02 is exercised on the sample.
"""
import collections, csv, io, pathlib, zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "WA_Fn-UseC_-Telco-Customer-Churn.csv"
src, dst = ROOT / "data/raw_full" / NAME, ROOT / "data/raw" / NAME
data = src.read_bytes()
eol = b"\r\n" if b"\r\n" in data else b"\n"
lines = data.split(eol)
if lines[-1] == b"":
    lines = lines[:-1]
head, body = lines[0], lines[1:]
cols = next(csv.reader(io.StringIO(head.decode())))
ix = {c: i for i, c in enumerate(cols)}
rows = [next(csv.reader(io.StringIO(l.decode()))) for l in body]
profile = lambda r: tuple(v for i, v in enumerate(r) if i != ix["customerID"])
copies = collections.Counter(profile(r) for r in rows)


def keep(r):
    cid, tenure, monthly, total = r[ix["customerID"]], int(r[ix["tenure"]]), float(r[ix["MonthlyCharges"]]), r[ix["TotalCharges"]].strip()
    blank = total == ""
    mismatch = not blank and tenure > 0 and abs(float(total) - monthly * tenure) > 0.25 * monthly * tenure
    return zlib.crc32(cid.encode()) % 5 == 0 or blank or mismatch or copies[profile(r)] > 1


out = [l for l, r in zip(body, rows) if keep(r)]
dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_bytes(eol.join([head] + out) + eol)
print(f"{dst.relative_to(ROOT)}: {len(out):,d} of {len(body):,d} customers, {dst.stat().st_size:,d} B")

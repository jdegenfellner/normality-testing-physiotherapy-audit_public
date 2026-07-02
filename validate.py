#!/usr/bin/env python3
"""Validate the rule-based classifier against independent manual coding of a
random 100-paper sample. Computes raw agreement and Cohen's kappa."""
import csv, json

# Manual codes assigned by reading each paper's extracted normality passages
# (indexed 1-100, matching validation_ids.csv / validation_passages.txt).
MANUAL = {
 1:"INCORRECT",2:"INCORRECT",3:"INCORRECT",4:"INCORRECT",5:"INCORRECT",6:"INCORRECT",
 7:"INCORRECT",8:"INCORRECT",9:"INCORRECT",10:"INCORRECT",11:"INCORRECT",12:"INCORRECT",
 13:"INCORRECT",14:"INCORRECT",15:"INCORRECT",16:"INCORRECT",17:"INCORRECT",18:"INCORRECT",
 19:"ACCEPTABLE",20:"UNCLEAR",21:"INCORRECT",22:"INCORRECT",23:"INCORRECT",24:"INCORRECT",
 25:"INCORRECT",26:"INCORRECT",27:"INCORRECT",28:"INCORRECT",29:"INCORRECT",30:"INCORRECT",
 31:"INCORRECT",32:"INCORRECT",33:"INCORRECT",34:"INCORRECT",35:"INCORRECT",36:"INCORRECT",
 37:"INCORRECT",38:"INCORRECT",39:"INCORRECT",40:"ACCEPTABLE",41:"INCORRECT",42:"INCORRECT",
 43:"INCORRECT",44:"INCORRECT",45:"MIXED",46:"INCORRECT",47:"INCORRECT",48:"INCORRECT",
 49:"INCORRECT",50:"INCORRECT",51:"INCORRECT",52:"INCORRECT",53:"INCORRECT",54:"INCORRECT",
 55:"INCORRECT",56:"INCORRECT",57:"CORRECT",58:"INCORRECT",59:"INCORRECT",60:"INCORRECT",
 61:"INCORRECT",62:"INCORRECT",63:"INCORRECT",64:"INCORRECT",65:"INCORRECT",66:"INCORRECT",
 67:"INCORRECT",68:"INCORRECT",69:"INCORRECT",70:"INCORRECT",71:"INCORRECT",72:"INCORRECT",
 73:"ACCEPTABLE",74:"INCORRECT",75:"INCORRECT",76:"INCORRECT",77:"INCORRECT",78:"INCORRECT",
 79:"INCORRECT",80:"INCORRECT",81:"ACCEPTABLE",82:"INCORRECT",83:"INCORRECT",84:"INCORRECT",
 85:"INCORRECT",86:"INCORRECT",87:"INCORRECT",88:"INCORRECT",89:"INCORRECT",90:"UNCLEAR",
 91:"INCORRECT",92:"INCORRECT",93:"INCORRECT",94:"INCORRECT",95:"INCORRECT",96:"INCORRECT",
 97:"INCORRECT",98:"INCORRECT",99:"INCORRECT",100:"INCORRECT",
}

ids = {int(r["idx"]): r["id"] for r in csv.DictReader(open("validation_ids.csv"))}
auto = {r["id"]: r["auto_code"] for r in csv.DictReader(open("coded_auto.csv"))}

pairs = []  # (manual, auto)
for idx, rid in ids.items():
    pairs.append((MANUAL[idx], auto[rid]))

cats = ["CORRECT", "ACCEPTABLE", "INCORRECT", "MIXED", "UNCLEAR", "NOT_RELEVANT"]
n = len(pairs)
agree = sum(1 for m, a in pairs if m == a)
po = agree / n

# Cohen's kappa
from collections import Counter
mc = Counter(m for m, a in pairs)
ac = Counter(a for m, a in pairs)
pe = sum((mc[c]/n) * (ac[c]/n) for c in cats)
kappa = (po - pe) / (1 - pe) if pe < 1 else 1.0

print(f"Validation sample: n = {n}")
print(f"Raw agreement: {agree}/{n} = {100*po:.1f}%")
print(f"Cohen's kappa: {kappa:.3f}")

# Binary collapse: INCORRECT/MIXED vs CORRECT/ACCEPTABLE (definitive only)
def binc(c): return "incorrect" if c in ("INCORRECT", "MIXED") else ("ok" if c in ("CORRECT", "ACCEPTABLE") else "unclear")
bin_pairs = [(binc(m), binc(a)) for m, a in pairs if binc(m) != "unclear" and binc(a) != "unclear"]
bagree = sum(1 for m, a in bin_pairs if m == a)
bn = len(bin_pairs)
bpo = bagree / bn
bm = Counter(m for m, a in bin_pairs); ba = Counter(a for m, a in bin_pairs)
bpe = sum((bm[c]/bn)*(ba[c]/bn) for c in ["incorrect","ok"])
bkappa = (bpo-bpe)/(1-bpe) if bpe < 1 else 1.0
print(f"\nBinary (incorrect vs ok), definitive in both: n={bn}")
print(f"  agreement {100*bpo:.1f}%, kappa {bkappa:.3f}")

# Confusion matrix
print("\nConfusion (rows=manual, cols=auto):")
present = [c for c in cats if mc[c] or ac[c]]
print("            " + "".join(f"{c[:5]:>7}" for c in present))
for m in present:
    row = Counter(a for mm, a in pairs if mm == m)
    print(f"  {m[:10]:11s}" + "".join(f"{row[a]:>7}" for a in present))

# disagreements
print("\nDisagreements:")
for idx, rid in ids.items():
    if MANUAL[idx] != auto[rid]:
        print(f"  [{idx}] id={rid}: manual={MANUAL[idx]} auto={auto[rid]}")

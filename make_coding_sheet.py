#!/usr/bin/env python3
"""Build a STRATIFIED human coding sheet for validation across the whole corpus.

Strata (by the classifier's binary call):
  * negative = classifier said CORRECT or ACCEPTABLE (rare; ~37): take ALL.
  * positive = classifier said INCORRECT or MIXED: take a random 63.
The sheet is shuffled and contains NO stratum/code hint (blind coding).
A separate file records the stratum sizes for the later design-based correction.

Only aggregate counts are printed (no passage text), so that full text of the
non-open-licensed journals is not surfaced."""
import csv, json, random

random.seed(2025)

# metadata: Europe PMC corpus + Elsevier corpus
CORP = {r["id"]: r for r in json.load(open("corpus_raw.json"))}
for r in json.load(open("elsevier_corpus.json")):
    CORP[r["id"]] = r
# passages: Europe PMC/render + Elsevier
P = json.load(open("passages.json"))
P.update(json.load(open("elsevier_passages.json")))
# classifier codes
AUTO = {r["id"]: r["auto_code"] for r in csv.DictReader(open("coded_auto.csv"))}

import re
CUE = re.compile(r"(?i)shapiro|kolmogorov|smirnov|lilliefors|anderson|d['’]?agostino|"
                 r"(?<!ab)normalit|(?<!ab)normal(ly)? distribut")
def norm_sentences(rid):
    out, seen = [], set()
    for p in P.get(rid, {}).get("passages", []):
        for s in re.split(r"(?<=[.;])\s+", p):
            if CUE.search(s):
                s = s.strip()
                if s[:80] not in seen:
                    seen.add(s[:80]); out.append(s[:400])
    return " || ".join(out)

neg = [rid for rid, c in AUTO.items() if c in ("CORRECT", "ACCEPTABLE")]
pos = [rid for rid, c in AUTO.items() if c in ("INCORRECT", "MIXED")]
random.shuffle(pos)
sample = neg + pos[:63]              # all negatives + 63 random positives
random.shuffle(sample)              # blind order

with open("validation_coding_sheet.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["idx", "id", "journal", "year", "title", "normality_sentences", "CODE"])
    for i, rid in enumerate(sample, 1):
        rec = CORP.get(rid, {})
        w.writerow([i, rid, rec.get("journal_abbr", ""), rec.get("year", ""),
                    (rec.get("title") or "").replace("\n", " "),
                    norm_sentences(rid), ""])

# private record for the correction (stratum sizes; NOT for coding)
json.dump({"n_neg_total": len(neg), "n_pos_total": len(pos),
           "n_neg_sampled": len(neg), "n_pos_sampled": min(63, len(pos)),
           "sample_ids": sample}, open("validation_sample_design.json", "w"), indent=1)

from collections import Counter
print(f"Sheet rows: {len(sample)}  (all {len(neg)} classifier-negative + "
      f"{min(63,len(pos))} of {len(pos)} classifier-positive)")
print("Journal spread:", dict(Counter(CORP.get(r,{}).get('journal_abbr','?') for r in sample)))
print("Source spread:", dict(Counter(CORP.get(r,{}).get('source','europepmc') for r in sample)))
print("Wrote validation_coding_sheet.csv (blind) + validation_sample_design.json")

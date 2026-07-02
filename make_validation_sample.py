#!/usr/bin/env python3
"""Draw a reproducible random sample of full-text papers and dump their
normality passages for independent manual coding (validation of the classifier)."""
import json, random, csv

random.seed(2025)
P = json.load(open("passages.json"))
CORP = {r["id"]: r for r in json.load(open("corpus_raw.json"))}

# eligible = papers with at least one extracted full-text normality passage
elig = [rid for rid, v in P.items()
        if v["source_used"] == "full_text" and v["n_passages"] > 0]
elig.sort()
random.shuffle(elig)
SAMPLE_N = 100
sample = elig[:SAMPLE_N]

with open("validation_passages.txt", "w") as f:
    for i, rid in enumerate(sample, 1):
        rec = CORP[rid]
        v = P[rid]
        f.write(f"\n{'='*90}\n[{i}] id={rid}  {rec['journal_abbr']}  {rec.get('year')}\n")
        f.write(f"TITLE: {(rec.get('title') or '').strip()}\n")
        f.write("NORMALITY SENTENCES:\n")
        import re as _re
        seen = set()
        for p in v["passages"]:
            for s in _re.split(r"(?<=[.;])\s+", p):
                if _re.search(r"(?i)shapiro|kolmogorov|smirnov|lilliefors|anderson|d['’]?agostino|(?<!ab)normalit|(?<!ab)normal(ly)? distribut", s):
                    s = s.strip()
                    if s[:80] not in seen:
                        seen.add(s[:80]); f.write(f"  * {s[:400]}\n")

# also write the sample id list (ordered) for joining codes later
with open("validation_ids.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["idx", "id"])
    for i, rid in enumerate(sample, 1):
        w.writerow([i, rid])

print(f"Eligible full-text papers: {len(elig)}")
print(f"Wrote {len(sample)} papers to validation_passages.txt")

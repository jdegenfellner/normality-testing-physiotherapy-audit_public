#!/usr/bin/env python3
"""Rule-based classifier implementing the Midway & White (2025) coding scheme,
applied at the SENTENCE level to the normality-test passages extracted from
each paper's full text.

For each paper we locate the sentence(s) that actually name/describe a
normality test and classify the TARGET of that test:
  CORRECT      : assessed on model RESIDUALS.
  ACCEPTABLE   : assessed separately PER GROUP (= residuals for balanced
                 two-group designs).
  INCORRECT    : assessed on the data / outcome / variables / distribution
                 with no residual or per-group qualifier.  Per the coding
                 guide, an unqualified "data were tested for normality" is
                 INCORRECT.
  MIXED        : a residual/per-group statement AND an explicit pooled
                 statement both occur.
  UNCLEAR      : no sentence actually describing a normality test could be
                 located (e.g. the keyword matched 'normal range', 'normal
                 pitching', 'abnormality', a Gaussian filter, etc.).
"""
import json, re, csv
from collections import Counter

import os
P = json.load(open("passages.json"))
CORP = {r["id"]: r for r in json.load(open("corpus_raw.json"))}

# Merge the two ScienceDirect-only journals retrieved via the Elsevier TDM API.
# Their passage text is held locally only; for compliance the per-row
# norm_sentence is blanked below so no Elsevier text enters coded_auto.csv.
if os.path.exists("elsevier_corpus.json"):
    for r in json.load(open("elsevier_corpus.json")):
        CORP[r["id"]] = r
    P.update(json.load(open("elsevier_passages.json")))

# A sentence genuinely about a normality TEST (named test, or "normality"/
# "normal distribution" used in a testing sense). Negative lookbehind (?<!ab)
# prevents matching 'abnormality'/'abnormal'.
NORMTEST = re.compile(
    r"(?i)(shapiro|kolmogorov|smirnov|lilliefors|anderson[\s\-]?darling|d['’]?agostino|"
    r"(?<!ab)normality|(?<!ab)normal(ly)? distribut|"
    r"test.{0,15}for (?<!ab)normal|assumption.{0,15}of (?<!ab)normal)")
# exclude non-testing uses of 'normal'
EXCLUDE_ONLY = re.compile(
    r"(?i)(gaussian (filter|kernel|smoothing|blur)|normal range|normal pitching|"
    r"normal walking|within normal limits|normal force|normal saline|"
    r"normali[sz]ed|normali[sz]ation|abnormalit)")

RESIDUAL = re.compile(r"(?i)residual")
PERGROUP = re.compile(
    r"(?i)(each group|per group|for each group|within[\s\-]?each[\s\-]?group|"
    r"both groups|in each group|group(s)? separately|separately (for|within|in|by)|"
    r"each of the (two |three |\d+ )?groups|for (the )?(intervention|control|"
    r"experimental|each) group|men and women .{0,30}separately|"
    r"for (each|both) (of the )?(sub)?group)")

NORMCUE_SHORT = re.compile(
    r"(?i)(shapiro|kolmogorov|smirnov|lilliefors|anderson[\s\-]?darling|d['’]?agostino|(?<!ab)normalit)")

TESTS = {
    "Shapiro-Wilk": re.compile(r"(?i)shapiro"),
    "Kolmogorov-Smirnov": re.compile(r"(?i)kolmogorov|smirnov|lilliefors"),
    "Anderson-Darling": re.compile(r"(?i)anderson[\s\-]?darling"),
    "D'Agostino": re.compile(r"(?i)d['’]?agostino"),
}
STATCTX = {
    "t-test": re.compile(r"(?i)\bt[\s\-]?test|student'?s? t|paired t|independent.{0,12}t[\s\-]?test"),
    "ANOVA": re.compile(r"(?i)\banova\b|analysis of variance"),
    "regression": re.compile(r"(?i)regression"),
    "correlation": re.compile(r"(?i)correlation|pearson|spearman"),
    "Mann-Whitney/Wilcoxon": re.compile(r"(?i)mann[\s\-]?whitney|wilcoxon|kruskal"),
    "ANCOVA/mixed model": re.compile(r"(?i)ancova|mixed[\s\-]?model|mixed[\s\-]?effect|\bgee\b"),
}


def split_sentences(text):
    text = re.sub(r"\s+", " ", text).strip()
    return [s.strip() for s in re.split(r"(?<=[.;])\s+(?=[A-Z(])", text) if s.strip()]


def classify(passages):
    # gather candidate normality-test sentences across all passages
    norm_sents = []
    for p in passages:
        for s in split_sentences(p):
            if NORMCUE_SHORT.search(s) or (NORMTEST.search(s) and not EXCLUDE_ONLY.search(s)):
                if not (EXCLUDE_ONLY.search(s) and not NORMCUE_SHORT.search(s)):
                    norm_sents.append(s)
    # dedup
    seen, sents = set(), []
    for s in norm_sents:
        k = s[:100]
        if k not in seen:
            seen.add(k); sents.append(s)
    if not sents:
        return "UNCLEAR", sents
    any_res = any(RESIDUAL.search(s) for s in sents)
    # per-group counts only when the group phrase sits close to a normality cue
    # (so "in each group" describing a between-group COMPARISON test does not
    #  get mistaken for per-group normality assessment)
    def grp_near_norm(s):
        for gm in PERGROUP.finditer(s):
            for nm in re.finditer(r"(?i)(?<!ab)normal|shapiro|kolmogorov|smirnov|lilliefors|anderson|d['’]?agostino", s):
                if abs(gm.start() - nm.start()) <= 55:
                    return True
        return False
    any_grp = any(grp_near_norm(s) for s in sents)
    # pooled = a normality-test sentence with neither residual nor per-group qualifier
    any_pool = any((not RESIDUAL.search(s)) and (not PERGROUP.search(s)) for s in sents)
    if any_res and any_pool:
        return "MIXED", sents
    if any_res:
        return "CORRECT", sents
    if any_grp and any_pool:
        # group qualifier present but also an unqualified pooled statement
        return "ACCEPTABLE", sents  # per-group dominates a generic statement
    if any_grp:
        return "ACCEPTABLE", sents
    return "INCORRECT", sents


rows = []
for rid, rec in CORP.items():
    pas = P.get(rid)
    if pas and pas["n_passages"] > 0:
        passages = pas["passages"]; src = pas["source_used"]; npass = pas["n_passages"]
    elif rec.get("abstract"):
        passages = [rec["abstract"]]; src = "abstract_only"; npass = 0
    else:
        passages = []; src = "none"; npass = 0
    code, sents = classify(passages)
    alltext = " ".join(passages)
    tests = [t for t, rgx in TESTS.items() if rgx.search(alltext)]
    ctx = [c for c, rgx in STATCTX.items() if rgx.search(alltext)]
    rows.append({
        "id": rid, "pmid": rec.get("pmid"), "pmcid": rec.get("pmcid"),
        "journal_abbr": rec["journal_abbr"], "journal_full": rec["journal_full"],
        "year": rec.get("year"), "title": (rec.get("title") or "").replace("\n", " "),
        "source_used": src, "n_passages": npass, "auto_code": code,
        "norm_tests": "; ".join(tests), "stat_context": "; ".join(ctx),
        "norm_sentence": ("" if rec.get("source") in ("elsevier_tdm", "epmc_pdf_render")
                          else (sents[0][:300] if sents else "")),
    })

# Restrict to the study window (full publication years 2015-2024). Online-first
# records dated 2025 are outside the window and excluded, as described in Methods.
rows = [r for r in rows
        if str(r.get("year")).isdigit() and 2015 <= int(r["year"]) <= 2024]

with open("coded_auto.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)

print("Auto-code distribution (%d papers, 2015-2024):" % len(rows))
for k, v in Counter(r["auto_code"] for r in rows).most_common():
    print(f"  {k:14s} {v:4d}  ({100*v/len(rows):.1f}%)")
defin = [r for r in rows if r["auto_code"] in ("CORRECT", "ACCEPTABLE", "INCORRECT", "MIXED")]
inc = [r for r in defin if r["auto_code"] in ("INCORRECT", "MIXED")]
print(f"\nDefinitive-coded: {len(defin)} | Incorrect: {len(inc)} ({100*len(inc)/len(defin):.1f}%)")
print("Saved coded_auto.csv")

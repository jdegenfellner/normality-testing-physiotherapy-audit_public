#!/usr/bin/env python3
"""Recover full text for articles whose structured full text is NOT in the
PMC/Europe PMC open-access subset (so efetch returned only the abstract), by
downloading the freely-rendered PDF from Europe PMC and extracting text with
pdftotext. Generalises fetch_pc_pdf.py to every abstract-only article that has a
PMCID. Updates passages.json in place.

These articles are free-to-read but not necessarily openly licensed; as before,
the full text is processed locally only and is not redistributed (the open-data
deposit keeps DOIs + derived codes for non-CC content)."""
import json, urllib.request, ssl, subprocess, tempfile, os, re, sys, time

SSLCTX = ssl._create_unverified_context()
NORM_RE = re.compile(
    r"(?i)(shapiro|kolmogorov|smirnov|lilliefors|anderson[\s\-]?darling|d['’]?agostino|"
    r"(?<!ab)normalit|(?<!ab)normally\s*distribut|test.{0,15}for (?<!ab)normal|"
    r"assumption.{0,20}(?<!ab)normal)")

corp = {r["id"]: r for r in json.load(open("corpus_raw.json"))}
corp_list = list(corp.values())
P = json.load(open("passages.json"))

# target: every paper currently coded from its abstract that has a PMCID
targets = [rid for rid, p in P.items()
           if p.get("source_used") in ("abstract", "abstract_only")
           and corp.get(rid, {}).get("pmcid")]
print(f"Abstract-only articles with PMCID to recover: {len(targets)}", flush=True)


def split_sentences(text):
    text = re.sub(r"\s+", " ", text).strip()
    return [s.strip() for s in re.split(r"(?<=[.;])\s+(?=[A-Z(])", text) if s.strip()]


def extract(full):
    sents = split_sentences(full)
    hits = []
    for i, s in enumerate(sents):
        if NORM_RE.search(s):
            hits.append(" ".join(sents[max(0, i - 1):i + 2]))
    seen, uniq = set(), []
    for h in hits:
        if h[:120] not in seen:
            seen.add(h[:120]); uniq.append(h)
    return uniq[:12]


n_ok = n_norm = n_fail = 0
for k, rid in enumerate(targets):
    pmcid = corp[rid]["pmcid"].lower()
    url = f"https://europepmc.org/articles/{pmcid}?pdf=render"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 normality-audit"})
        data = urllib.request.urlopen(req, timeout=90, context=SSLCTX).read()
    except Exception as e:
        sys.stderr.write(f"{pmcid} fail: {e}\n"); n_fail += 1; continue
    if data[:5] != b"%PDF-":
        n_fail += 1; continue
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
        f.write(data); tmp = f.name
    try:
        txt = subprocess.run(["pdftotext", tmp, "-"], capture_output=True, timeout=60).stdout.decode("utf-8", "replace")
    finally:
        os.unlink(tmp)
    hits = extract(txt)
    P[rid] = {"pmcid": corp[rid]["pmcid"], "source_used": "full_text_pdf",
              "n_passages": len(hits), "passages": hits}
    corp[rid]["source"] = "epmc_pdf_render"
    n_ok += 1
    if hits:
        n_norm += 1
    if (k + 1) % 25 == 0:
        print(f"  ...{k+1}/{len(targets)}", flush=True)
    time.sleep(0.5)

json.dump(P, open("passages.json", "w"))
json.dump(corp_list, open("corpus_raw.json", "w"), indent=1)
print(f"\nRecovered: PDF+text OK {n_ok} | with norm passage {n_norm} | failed {n_fail}")
print("Updated passages.json and corpus_raw.json")

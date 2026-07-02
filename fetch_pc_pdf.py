#!/usr/bin/env python3
"""Retrieve full text for Physiotherapy Canada articles, whose structured XML is
not in the PMC/Europe PMC open-access subset (so efetch/fullTextXML returned only
abstracts), by downloading the freely-rendered PDF from Europe PMC and extracting
text locally with pdftotext. Updates passages.json in place for these articles.

Physiotherapy Canada is free-to-read but not CC-licensed (bronze OA); as with the
Elsevier journals, the full text is processed locally only and is not
redistributed (the open-data deposit keeps DOIs + derived codes only)."""
import json, urllib.request, ssl, subprocess, tempfile, os, re, sys, time

SSLCTX = ssl._create_unverified_context()
NORM_RE = re.compile(
    r"(?i)(shapiro|kolmogorov|smirnov|lilliefors|anderson[\s\-]?darling|d['’]?agostino|"
    r"(?<!ab)normalit|(?<!ab)normally\s*distribut|test.{0,15}for (?<!ab)normal|"
    r"assumption.{0,20}(?<!ab)normal)")

corp = json.load(open("corpus_raw.json"))
P = json.load(open("passages.json"))
pc = [r for r in corp if r["journal_abbr"] == "Physiother Can" and r.get("pmcid")]
marked = set()


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
for r in pc:
    pmcid = r["pmcid"].lower()
    url = f"https://europepmc.org/articles/{pmcid}?pdf=render"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 normality-audit"})
        data = urllib.request.urlopen(req, timeout=90, context=SSLCTX).read()
    except Exception as e:
        sys.stderr.write(f"{pmcid} download fail: {e}\n"); n_fail += 1; continue
    if not data[:5] == b"%PDF-":
        n_fail += 1; continue
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
        f.write(data); tmp = f.name
    try:
        txt = subprocess.run(["pdftotext", tmp, "-"], capture_output=True, timeout=60).stdout.decode("utf-8", "replace")
    finally:
        os.unlink(tmp)
    hits = extract(txt)
    P[r["id"]] = {"pmcid": r["pmcid"], "source_used": "full_text_pdf",
                  "n_passages": len(hits), "passages": hits}
    r["source"] = "epmc_pdf_render"  # mark for deposit/compliance handling
    marked.add(r["id"])
    n_ok += 1
    if hits:
        n_norm += 1
    time.sleep(0.6)

json.dump(P, open("passages.json", "w"))
json.dump(corp, open("corpus_raw.json", "w"), indent=1)
print(f"Physiotherapy Canada: {len(pc)} articles | PDF+text OK: {n_ok} | "
      f"with norm passage: {n_norm} | failed: {n_fail}")
print("Updated passages.json and corpus_raw.json (marked source=epmc_pdf_render)")

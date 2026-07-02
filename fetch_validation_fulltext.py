#!/usr/bin/env python3
"""Download the full text of the 100 validation papers into validation_fulltext/
so the human coder has everything in one place.

  * PMC-indexed papers -> rendered PDF from Europe PMC (no key needed).
  * Elsevier-only papers -> Elsevier full-text API (needs ELS_KEY; subscription
    titles need the ZHAW network/VPN). Saved as .txt; a link stub if not entitled.

Files are named <idx>_<journal>_<id>.<ext> so they sort like the coding sheet.
This folder is for the author's own use and is git-ignored (contains
non-open-licensed content)."""
import json, urllib.request, urllib.parse, ssl, os, re, time, sys

SSLCTX = ssl._create_unverified_context()
OUT = "validation_fulltext"
os.makedirs(OUT, exist_ok=True)
KEY = os.environ.get("ELS_KEY", "").strip()

design = json.load(open("validation_sample_design.json"))
ids = design["sample_ids"]
CORP = {r["id"]: r for r in json.load(open("corpus_raw.json"))}
for r in json.load(open("elsevier_corpus.json")):
    CORP[r["id"]] = r


def safe(s):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", (s or ""))[:40]


def get(url, headers, timeout=90):
    req = urllib.request.Request(url, headers=headers)
    return urllib.request.urlopen(req, timeout=timeout, context=SSLCTX).read()


index = [["idx", "file", "journal", "year", "title", "link"]]
n_pdf = n_els = n_stub = 0
for k, rid in enumerate(ids, 1):
    rec = CORP.get(rid, {})
    j = rec.get("journal_abbr", "?"); yr = rec.get("year", "")
    title = (rec.get("title") or "").replace("\n", " ")
    pmcid = rec.get("pmcid"); doi = rec.get("doi")
    base = f"{k:03d}_{safe(j)}_{safe(rid)}"
    link = (f"https://europepmc.org/article/MED/{rec.get('pmid')}" if rec.get("pmid")
            else (f"https://doi.org/{doi}" if doi else ""))
    try:
        if pmcid:  # Europe PMC rendered PDF
            data = get(f"https://europepmc.org/articles/{pmcid.lower()}?pdf=render",
                       {"User-Agent": "Mozilla/5.0 normality-audit"})
            if data[:5] == b"%PDF-":
                fn = base + ".pdf"
                open(os.path.join(OUT, fn), "wb").write(data); n_pdf += 1
            else:
                raise ValueError("not a pdf")
            link = f"https://europepmc.org/article/MED/{rec.get('pmid')}"
        elif KEY and doi:  # Elsevier full text -> txt
            body = get(f"https://api.elsevier.com/content/article/doi/{urllib.parse.quote(doi)}?view=FULL",
                       {"X-ELS-APIKey": KEY, "Accept": "application/json", "User-Agent": "normality-audit/1.0"})
            txt = json.loads(body).get("full-text-retrieval-response", {}).get("originalText") or ""
            if isinstance(txt, str) and txt.strip():
                fn = base + ".txt"
                open(os.path.join(OUT, fn), "w").write(f"{title}\n{doi}\n\n{txt}")
                n_els += 1
            else:
                raise ValueError("no text")
        else:
            raise ValueError("no key/pmcid")
    except Exception as e:
        fn = base + "_LINK.txt"
        open(os.path.join(OUT, fn), "w").write(
            f"{title}\nJournal: {j} ({yr})\nDOI: {doi}\nOpen: {link}\n\n"
            f"(Full text not auto-downloaded: {e}. Use the link above; the relevant\n"
            f"normality sentence is in the coding sheet.)\n")
        n_stub += 1
    index.append([k, fn, j, yr, title, link])
    time.sleep(0.4)
    if k % 20 == 0:
        print(f"  ...{k}/100", flush=True)

import csv
with open(os.path.join(OUT, "_index.csv"), "w", newline="") as f:
    csv.writer(f).writerows(index)

print(f"\nDone -> {OUT}/  | PDFs: {n_pdf} | Elsevier txt: {n_els} | link stubs: {n_stub}")
print("See validation_fulltext/_index.csv for the idx -> file mapping.")

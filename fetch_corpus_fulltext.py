#!/usr/bin/env python3
"""Download the full text of EVERY corpus article into corpus_fulltext/ (for the
author's own archive). Resumable: skips files that already exist.

  * PMC-indexed -> Europe PMC rendered PDF (.pdf); efetch fallback (.txt).
  * Elsevier-only -> Elsevier full-text API (.txt; needs ELS_KEY, VPN for
    subscription titles). Link stub if not retrievable.

Local convenience only; not redistributed (folder is git-ignored)."""
import json, os, re, ssl, sys, time, urllib.request, urllib.parse
import xml.etree.ElementTree as ET

SSLCTX = ssl._create_unverified_context()
OUT = "corpus_fulltext"
os.makedirs(OUT, exist_ok=True)
KEY = os.environ.get("ELS_KEY", "").strip()

CORP = {r["id"]: r for r in json.load(open("corpus_raw.json"))}
for r in json.load(open("elsevier_corpus.json")):
    CORP[r["id"]] = r
ids = list(CORP)


def safe(s):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", (s or ""))[:48]


def get(url, headers, timeout=90):
    for a in range(4):
        try:
            return urllib.request.urlopen(
                urllib.request.Request(url, headers=headers), timeout=timeout, context=SSLCTX).read()
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(5 + 3 * a); continue
            raise
    raise RuntimeError("retries exhausted")


def already(base):
    return any(os.path.exists(os.path.join(OUT, base + ext))
               for ext in (".pdf", ".txt", "_LINK.txt"))


n_pdf = n_txt = n_stub = n_skip = 0
for k, rid in enumerate(ids, 1):
    rec = CORP[rid]
    j = rec.get("journal_abbr", "?")
    base = f"{safe(j)}_{safe(rid)}"
    if already(base):
        n_skip += 1
    else:
        pmcid = rec.get("pmcid"); doi = rec.get("doi")
        try:
            if pmcid:
                data = get(f"https://europepmc.org/articles/{pmcid.lower()}?pdf=render",
                           {"User-Agent": "Mozilla/5.0 normality-audit"})
                if data[:5] == b"%PDF-":
                    open(os.path.join(OUT, base + ".pdf"), "wb").write(data); n_pdf += 1
                else:  # efetch fallback
                    p = urllib.parse.urlencode({"db": "pmc", "id": pmcid.replace("PMC", ""), "rettype": "xml"})
                    xml = get("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?" + p,
                              {"User-Agent": "normality-audit/1.0"}).decode("utf-8", "replace")
                    body = next((a.find(".//body") for a in ET.fromstring(xml).iter("article")
                                 if a.find(".//body") is not None), None)
                    txt = "".join(body.itertext()) if body is not None else ""
                    if len(txt) > 500:
                        open(os.path.join(OUT, base + ".txt"), "w").write(txt); n_txt += 1
                    else:
                        raise ValueError("no full text")
            elif KEY and doi:
                body = get(f"https://api.elsevier.com/content/article/doi/{urllib.parse.quote(doi)}?view=FULL",
                           {"X-ELS-APIKey": KEY, "Accept": "application/json", "User-Agent": "normality-audit/1.0"})
                txt = json.loads(body).get("full-text-retrieval-response", {}).get("originalText") or ""
                if isinstance(txt, str) and txt.strip():
                    open(os.path.join(OUT, base + ".txt"), "w").write(txt); n_txt += 1
                else:
                    raise ValueError("no text")
            else:
                raise ValueError("no key/pmcid")
        except Exception as e:
            open(os.path.join(OUT, base + "_LINK.txt"), "w").write(
                f"{(rec.get('title') or '')}\n{j} {rec.get('year','')}\nDOI: {doi}\n({e})\n")
            n_stub += 1
        time.sleep(0.5)
    if k % 50 == 0:
        print(f"  ...{k}/{len(ids)}  pdf={n_pdf} txt={n_txt} stub={n_stub} skip={n_skip}", flush=True)

print(f"\nDONE -> {OUT}/  | pdf={n_pdf} txt={n_txt} stub={n_stub} skipped(existing)={n_skip} | total={len(ids)}")

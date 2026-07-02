#!/usr/bin/env python3
"""Retrieve the two ScienceDirect-only journals (Journal of Physiotherapy,
Physiotherapy) via the Elsevier TDM API, mirroring the Europe PMC full-text
search, and extract the normality passages for the LOCAL rule-based classifier.

Compliance notes (Elsevier API Service Agreement 2.4 + TDM policy):
  * Access is via the sanctioned ScienceDirect API only (no browser scraping).
  * Classification is done locally and deterministically; full texts are NOT
    sent to any third-party AI system.
  * Full texts are held only transiently for extraction; only DOIs, metadata
    and the derived codes are intended for the open-data deposit (no full-text
    or >200-char snippet redistribution).
  * The script prints AGGREGATE counts only, never the passage text.
"""
import urllib.request, urllib.parse, json, time, sys, ssl, re, os
SSLCTX = ssl._create_unverified_context()
KEY = os.environ["ELS_KEY"].strip()

SEARCH = "https://api.elsevier.com/content/search/sciencedirect"
ARTICLE = "https://api.elsevier.com/content/article/doi/"

JOURNALS = {  # exact prism:publicationName : (abbr, full name)
    "Journal of Physiotherapy": ("J Physiother", "Journal of Physiotherapy"),
    "Physiotherapy":            ("Physiotherapy", "Physiotherapy"),
}

NORM_TERMS = ['"Shapiro-Wilk"', '"Shapiro Wilk"', '"Kolmogorov-Smirnov"',
    '"Kolmogorov Smirnov"', '"Lilliefors"', '"Anderson-Darling"', '"normality test"',
    '"test for normality"', '"tested for normality"', '"assess normality"',
    '"check normality"', '"D\'Agostino"', '"D Agostino"']
NORM_CLAUSE = "(" + " OR ".join(NORM_TERMS) + ")"

NORM_RE = re.compile(
    r"(?i)(shapiro|kolmogorov|smirnov|lilliefors|anderson[\s\-]?darling|d['’]?agostino|"
    r"(?<!ab)normality|(?<!ab)normally distribut|test.{0,15}for (?<!ab)normal|"
    r"assumption.{0,20}(?<!ab)normal|gaussian distribut)")


def req(url, accept="application/json"):
    for a in range(5):
        try:
            r = urllib.request.Request(url, headers={
                "X-ELS-APIKey": KEY, "Accept": accept, "User-Agent": "normality-audit/1.0"})
            with urllib.request.urlopen(r, timeout=90, context=SSLCTX) as resp:
                return resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            if e.code == 429:
                sys.stderr.write("  429, backing off\n"); time.sleep(6 + a * 4); continue
            return None  # 400/401/404 -> no access for this item
        except Exception as e:
            sys.stderr.write(f"  retry {a} ({e})\n"); time.sleep(2 + a)
    return None


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


def search_journal(jname):
    hits, start = [], 0
    while True:
        params = urllib.parse.urlencode({
            "query": f'srctitle("{jname}") AND {NORM_CLAUSE}',
            "date": "2015-2024", "count": 100, "start": start})
        body = req(f"{SEARCH}?{params}")
        if body is None:
            break
        d = json.loads(body)["search-results"]
        for e in d.get("entry", []):
            doi = e.get("prism:doi"); pub = e.get("prism:publicationName", "")
            if doi and pub.strip().lower() == jname.strip().lower():
                hits.append({"doi": doi, "title": e.get("dc:title"),
                             "coverDate": e.get("prism:coverDate")})
        total = int(d.get("opensearch:totalResults", 0))
        start += 100
        if start >= total or not d.get("entry"):
            break
        time.sleep(1)
    # de-dup by doi
    seen, uniq = set(), []
    for h in hits:
        if h["doi"] not in seen:
            seen.add(h["doi"]); uniq.append(h)
    return uniq


corpus, passages = [], {}
for jname, (abbr, full) in JOURNALS.items():
    found = search_journal(jname)
    sys.stderr.write(f"{jname}: {len(found)} search hits\n")
    n_ft = n_norm = n_noaccess = 0
    for rec in found:
        doi = rec["doi"]
        body = req(f"{ARTICLE}{urllib.parse.quote(doi)}?view=FULL")
        time.sleep(0.4)
        if body is None:
            n_noaccess += 1; continue
        try:
            ft = json.loads(body).get("full-text-retrieval-response", {})
        except json.JSONDecodeError:
            n_noaccess += 1; continue
        orig = ft.get("originalText")
        if not isinstance(orig, str) or not orig.strip():
            n_noaccess += 1; continue
        n_ft += 1
        hits = extract(orig)
        year = (rec.get("coverDate") or "")[:4]
        rid = "ELS:" + doi
        corpus.append({"id": rid, "pmid": None, "pmcid": None, "doi": doi,
                       "journal_abbr": abbr, "journal_full": full,
                       "title": rec.get("title"), "year": year,
                       "isOpenAccess": None, "source": "elsevier_tdm"})
        passages[rid] = {"pmcid": None, "source_used": "full_text",
                         "n_passages": len(hits), "passages": hits}
        if hits:
            n_norm += 1
    print(f"{abbr:14s} hits={len(found):4d}  fulltext={n_ft:4d}  "
          f"with_norm_passage={n_norm:4d}  no_access={n_noaccess}")

json.dump(corpus, open("elsevier_corpus.json", "w"), indent=1)
json.dump(passages, open("elsevier_passages.json", "w"))  # NOT for deposit; not read
print(f"\nTOTAL Elsevier records: {len(corpus)} | with >=1 norm passage: "
      f"{sum(1 for v in passages.values() if v['n_passages']>0)}")
print("Saved elsevier_corpus.json (+ elsevier_passages.json, local only)")

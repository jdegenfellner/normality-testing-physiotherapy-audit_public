#!/usr/bin/env python3
"""Retrieve the physiotherapy normality-testing corpus from Europe PMC (full-text search).

Journals are queried by their NLM abbreviation (Europe PMC `journalTitle`).
J Physiother and Physiotherapy are excluded: Europe PMC indexes only their
abstracts (no full-text), so a full-text methods search returns nothing for them.
"""
import urllib.request, urllib.parse, json, time, sys, ssl

SSLCTX = ssl._create_unverified_context()
BASE = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"

# NLM abbreviation : full journal name (for tables)
JOURNALS = {
    "Phys Ther": "Physical Therapy",
    "Physiother Theory Pract": "Physiotherapy Theory and Practice",
    "J Orthop Sports Phys Ther": "Journal of Orthopaedic & Sports Physical Therapy",
    "Arch Phys Med Rehabil": "Archives of Physical Medicine and Rehabilitation",
    "Clin Rehabil": "Clinical Rehabilitation",
    "Disabil Rehabil": "Disability and Rehabilitation",
    "Eur J Phys Rehabil Med": "European Journal of Physical and Rehabilitation Medicine",
    "J Phys Ther Sci": "Journal of Physical Therapy Science",
    "Musculoskelet Sci Pract": "Musculoskeletal Science and Practice",
    "J Hand Ther": "Journal of Hand Therapy",
    "Braz J Phys Ther": "Brazilian Journal of Physical Therapy",
    "Hong Kong Physiother J": "Hong Kong Physiotherapy Journal",
    "Phys Ther Sport": "Physical Therapy in Sport",
    "Physiother Can": "Physiotherapy Canada",
}

NORM_TERMS = [
    '"Shapiro-Wilk"', '"Shapiro Wilk"', '"Kolmogorov-Smirnov"', '"Kolmogorov Smirnov"',
    '"Lilliefors"', '"Anderson-Darling"', '"normality test"', '"test for normality"',
    '"tested for normality"', '"assess normality"', '"check normality"', '"D\'Agostino"',
]
NORM_CLAUSE = "(" + " OR ".join(NORM_TERMS) + ")"
DATE_CLAUSE = "(FIRST_PDATE:[2015-01-01 TO 2024-12-31])"


def fetch_url(url):
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "normality-audit/1.0"})
            with urllib.request.urlopen(req, timeout=90, context=SSLCTX) as r:
                return json.load(r)
        except Exception as e:
            sys.stderr.write(f"  retry {attempt} ({e})\n")
            time.sleep(2 + attempt * 2)
    raise RuntimeError("failed: " + url)


def search_journal(abbr):
    query = f'(JOURNAL:"{abbr}") AND {NORM_CLAUSE} AND {DATE_CLAUSE}'
    records, cursor = [], "*"
    while True:
        params = urllib.parse.urlencode({
            "query": query, "format": "json", "pageSize": 1000,
            "cursorMark": cursor, "resultType": "core",
        })
        d = fetch_url(f"{BASE}?{params}")
        results = d.get("resultList", {}).get("result", [])
        records.extend(results)
        nxt = d.get("nextCursorMark")
        if not nxt or nxt == cursor or not results:
            break
        cursor = nxt
        time.sleep(0.3)
    return d.get("hitCount", len(records)), records


def jabbr(r):
    return (r.get("journalInfo", {}).get("journal", {}).get("medlineAbbreviation")
            or r.get("journalInfo", {}).get("journal", {}).get("isoabbreviation") or "").strip()


def slim(r, abbr, fullname):
    return {
        "id": r.get("id"), "source": r.get("source"), "pmid": r.get("pmid"),
        "pmcid": r.get("pmcid"), "doi": r.get("doi"),
        "journal_abbr": abbr, "journal_full": fullname,
        "title": r.get("title"), "authorString": r.get("authorString"),
        "year": r.get("pubYear"),
        "isOpenAccess": r.get("isOpenAccess"),
        "inEPMC": (r.get("inEPMC") == "Y"),
        "hasTextMinedTerms": r.get("hasTextMinedTerms"),
        "abstract": r.get("abstractText"),
    }


all_records, summary = {}, []
for abbr, fullname in JOURNALS.items():
    hit, recs = search_journal(abbr)
    kept = [r for r in recs if jabbr(r).lower() == abbr.lower()]
    for r in kept:
        key = r.get("id") or r.get("pmid") or r.get("doi")
        if key:
            all_records[key] = slim(r, abbr, fullname)
    summary.append((abbr, hit, len(recs), len(kept)))
    sys.stderr.write(f"{abbr}: hit={hit}, kept={len(kept)}\n")
    time.sleep(0.3)

records = list(all_records.values())
print("\n=== PER-JOURNAL SUMMARY ===")
for abbr, hit, fetched, kept in summary:
    print(f"  {abbr:28s} hit={hit:4d} kept={kept:4d}")
print(f"\nTOTAL unique records kept: {len(records)}")
oa = sum(1 for r in records if r["isOpenAccess"] == "Y")
inepmc = sum(1 for r in records if r["inEPMC"])
print(f"Open access: {oa}   |   inEPMC (full text fetchable): {inepmc}")

with open("corpus_raw.json", "w") as f:
    json.dump(records, f, indent=1)
print("Saved corpus_raw.json")

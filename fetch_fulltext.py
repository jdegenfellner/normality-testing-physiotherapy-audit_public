#!/usr/bin/env python3
"""Fetch PMC full text (NCBI efetch) for each corpus paper and extract the
sentences that mention a normality test, for focused coding."""
import urllib.request, urllib.parse, json, time, sys, ssl, re
import xml.etree.ElementTree as ET

SSLCTX = ssl._create_unverified_context()
EFETCH = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"

NORM_RE = re.compile(
    r"(?i)(shapiro|kolmogorov|smirnov|lilliefors|anderson[\s\-]?darling|d['’]?agostino|"
    r"normality|normally distribut|test.{0,15}for normal|assumption.{0,20}normal|"
    r"gaussian distribut)")


def get(url, tries=5):
    for a in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "normality-audit/1.0"})
            with urllib.request.urlopen(req, timeout=120, context=SSLCTX) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:
            sys.stderr.write(f"  retry {a} ({e})\n")
            time.sleep(1.5 + a)
    return None


def node_text(node):
    return "".join(node.itertext())


def split_sentences(text):
    text = re.sub(r"\s+", " ", text).strip()
    # split on sentence boundaries, keep it simple
    parts = re.split(r"(?<=[.;])\s+(?=[A-Z(])", text)
    return [p.strip() for p in parts if p.strip()]


def extract_from_article(art):
    # pmcid
    pmcid = None
    for aid in art.iter("article-id"):
        t = aid.get("pub-id-type")
        val = (aid.text or "").strip()
        if t == "pmcid":
            pmcid = val if val.startswith("PMC") else "PMC" + val
        elif t in ("pmcaid", "pmcaiid") and pmcid is None:
            pmcid = "PMC" + val
    # body text (full text); fall back to abstract
    body = art.find(".//body")
    src = "full_text"
    if body is None:
        body = art.find(".//abstract")
        src = "abstract"
    if body is None:
        return pmcid, src, [], ""
    full = node_text(body)
    sents = split_sentences(full)
    hits = []
    for i, s in enumerate(sents):
        if NORM_RE.search(s):
            # include one neighbour each side for context
            ctx = " ".join(sents[max(0, i - 1):i + 2])
            hits.append(ctx)
    # dedup while preserving order
    seen, uniq = set(), []
    for h in hits:
        k = h[:120]
        if k not in seen:
            seen.add(k); uniq.append(h)
    return pmcid, src, uniq[:12], full[:200]


records = json.load(open("corpus_raw.json"))
by_pmc = {}
for r in records:
    if r.get("pmcid"):
        by_pmc[r["pmcid"].replace("PMC", "")] = r

ids = list(by_pmc.keys())
print(f"Fetching full text for {len(ids)} papers with PMCID...", flush=True)

passages = {}
BATCH = 20
for bi in range(0, len(ids), BATCH):
    batch = ids[bi:bi + BATCH]
    params = urllib.parse.urlencode({"db": "pmc", "id": ",".join(batch), "rettype": "xml"})
    xml = get(f"{EFETCH}?{params}")
    if xml is None:
        sys.stderr.write(f"batch {bi} failed\n"); continue
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as e:
        sys.stderr.write(f"parse error batch {bi}: {e}\n"); continue
    for art in root.iter("article"):
        pmcid, src, hits, head = extract_from_article(art)
        if pmcid:
            rec = by_pmc.get(pmcid.replace("PMC", ""))
            rid = rec["id"] if rec else pmcid
            passages[rid] = {"pmcid": pmcid, "source_used": src,
                             "n_passages": len(hits), "passages": hits}
    if (bi // BATCH) % 5 == 0:
        print(f"  ...{bi+len(batch)}/{len(ids)} done", flush=True)
    time.sleep(0.34)

# papers with no PMC retrieval -> use abstract from corpus
n_ft = sum(1 for v in passages.values() if v["source_used"] == "full_text")
n_with_hits = sum(1 for v in passages.values() if v["n_passages"] > 0)
print(f"\nRetrieved: {len(passages)} | full_text: {n_ft} | with >=1 norm passage: {n_with_hits}")

json.dump(passages, open("passages.json", "w"), indent=1)
print("Saved passages.json")

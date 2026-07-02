#!/usr/bin/env python3
"""LLM-based replication of the normality-test target classification.
Independent of the rule-based classifier: a local Qwen2.5-32B-Instruct (4-bit,
MLX) reads the extracted normality passages and assigns one of the five codes.
Deterministic (greedy decoding). See classify.py for the rule-based version."""
import json, csv, re, sys, time
from mlx_lm import load, generate
from mlx_lm.sample_utils import make_sampler

MODEL = "/Users/degn/models/Qwen2.5-32B-Instruct-4bit"

SYSTEM = (
"You are a meticulous methodologist coding how a study applied a NORMALITY TEST "
"(e.g. Shapiro-Wilk, Kolmogorov-Smirnov). You are given the methods sentences that "
"mention normality. Decide the TARGET the normality test was applied to, and return "
"exactly one code.\n\n"
"CODES:\n"
"- CORRECT: normality assessed on the model RESIDUALS (or 'errors'), e.g. 'Q-Q plot of residuals', 'residuals were normally distributed'.\n"
"- ACCEPTABLE: normality assessed SEPARATELY WITHIN EACH GROUP, e.g. 'for each group', 'in both groups separately', 'within groups'. (Not residuals, but per-group.)\n"
"- INCORRECT: normality assessed on the POOLED / RAW outcome data or variables, not conditioned on group and not on residuals. Following Midway & White, an UNQUALIFIED statement such as 'the data were tested for normality' or 'normality of the variables was checked' counts as INCORRECT, because the data/variables (not the residuals or within-group observations) are named as the object of the test.\n"
"- MIXED: BOTH a residual target (correct) AND an unqualified pooled/raw target (incorrect) are reported.\n"
"- UNCLEAR: no normality TEST of an assumption is actually described, or its target cannot be determined. Examples: 'within normal limits', 'normal range', text not about checking a distributional assumption.\n\n"
"RULES:\n"
"- Use ONLY the excerpt. Do not infer beyond what is written.\n"
"- If residuals are named as the target -> CORRECT, even if the word 'data' appears elsewhere.\n"
"- Per-group testing -> ACCEPTABLE (do not upgrade to CORRECT).\n"
"- An unqualified 'tested X for normality' with no residuals and no per-group wording -> INCORRECT.\n"
"- Reply with STRICT JSON on a single line: {\"code\": \"CORRECT|ACCEPTABLE|INCORRECT|MIXED|UNCLEAR\", \"reason\": \"<=20 words\"}"
)

def build_prompt(tok, text):
    msgs=[{"role":"system","content":SYSTEM},
          {"role":"user","content":"EXCERPT:\n\"\"\"\n"+text.strip()[:4000]+"\n\"\"\""}]
    return tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False)

CODES={"CORRECT","ACCEPTABLE","INCORRECT","MIXED","UNCLEAR"}
def parse(out):
    m=re.search(r'\{.*\}', out, re.S)
    if m:
        try:
            j=json.loads(m.group(0)); c=str(j.get("code","")).upper().strip()
            if c in CODES: return c, j.get("reason","")
        except Exception: pass
    for c in CODES:
        if c in out.upper(): return c, "(fallback parse)"
    return "PARSE_FAIL", out[:120]

def main():
    pas=json.load(open("passages.json")); el=json.load(open("elsevier_passages.json"))
    rows=[r for r in csv.DictReader(open("coded_auto.csv")) if r["year"].isdigit() and 2015<=int(r["year"])<=2024]
    defin=[r for r in rows if r["auto_code"] in ("CORRECT","ACCEPTABLE","INCORRECT","MIXED")]
    def txt(r):
        i=r["id"]
        if i in pas: return " ".join(pas[i]["passages"])
        if i in el:  return " ".join(el[i]["passages"])
        return (r.get("norm_sentence") or "").strip()
    limit=int(sys.argv[1]) if len(sys.argv)>1 else len(defin)
    defin=defin[:limit]
    print(f"loading model...", file=sys.stderr)
    model,tok=load(MODEL)
    sampler=make_sampler(temp=0.0)   # greedy / deterministic
    out=csv.writer(open("llm_codes.csv","w",newline=""))
    out.writerow(["id","journal_abbr","year","auto_code","llm_code","llm_reason"])
    t0=time.time()
    for k,r in enumerate(defin,1):
        p=build_prompt(tok, txt(r))
        gen=generate(model,tok,prompt=p,max_tokens=80,sampler=sampler,verbose=False)
        code,reason=parse(gen)
        out.writerow([r["id"],r["journal_abbr"],r["year"],r["auto_code"],code,reason])
        if k%25==0 or k<=6:
            dt=time.time()-t0
            print(f"  {k}/{len(defin)}  {dt/k:.1f}s/paper  rule={r['auto_code']:10s} llm={code}", file=sys.stderr, flush=True)
    print(f"DONE {len(defin)} papers in {time.time()-t0:.0f}s -> llm_codes.csv", file=sys.stderr)

if __name__=="__main__": main()

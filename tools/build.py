import json, re, os, shutil, sys
raw=json.load(open("raw.json"))
LET="ABCD"

TERM=re.compile(r'[.?!\u201d"\u2019\']\s*$')
MARK=re.compile("[\ue000\ue001]")   # underline markers from extract.py
bare=lambda s: MARK.sub("", s)
def reflow(t):
    lines=[l for l in t.split("\n") if l.strip()]
    out=[]
    for l in lines:
        if out and re.match(r"^[a-z0-9(\u2014\u2013,;)]", bare(l)) and not TERM.search(bare(out[-1])):
            out[-1]=out[-1].rstrip()+" "+l.lstrip()
        else: out.append(l)
    return "\n".join(out)


def find_choices(lines):
    idx={}
    end=len(lines)
    for L in reversed(LET):
        pat=re.compile(rf"^{L}[\.\)]\s")
        found=None
        for i in range(end-1,-1,-1):
            if pat.match(bare(lines[i])): found=i; break
        if found is None: return None
        idx[L]=found; end=found
    if not (idx["A"]<idx["B"]<idx["C"]<idx["D"]): return None
    return idx

def structure(q):
    lines=[l for l in q["stem_raw"].split("\n") if l.strip()]
    idx=find_choices(lines)
    if idx is None: return None,"no choices"
    bounds=[idx["A"],idx["B"],idx["C"],idx["D"],len(lines)]
    stem=reflow("\n".join(lines[:idx["A"]]).strip())
    choices=[]
    for i,L in enumerate(LET):
        seg=bare(" ".join(lines[bounds[i]:bounds[i+1]])).strip()
        seg=re.sub(rf"^{L}[\.\)]\s*","",seg)
        choices.append(seg.strip())
    if not stem: return None,"empty stem"
    if any(not c for c in choices): return None,"empty choice"

    a=q["ans_raw"]
    a=bare(a)
    m=re.search(r"^Correct Answer:\s*([A-D])\s*$", a, re.M)
    if not m: return None,"no correct answer"
    correct=m.group(1)
    rest=a[m.end():]
    rest=re.sub(r"^\s*Rationale\s*","",rest.strip())
    rest=re.split(r"Question Difficulty:\s*\w+", rest)[0].strip()
    expl=reflow(rest)
    if not expl: return None,"empty explanation"
    return dict(id=q["id"], difficulty=q["difficulty"],
                domain=q["meta"].get("domain","Unknown"),
                skill=re.sub(r"Cross-text","Cross-Text",q["meta"].get("skill","Unknown")),
                stem=stem, choices=choices, correct=LET.index(correct),
                explanation=expl,
                figures=[f["file"] for f in q["figs"]]), None

out=[]; fails={}
for q in raw:
    s,err=structure(q)
    if s: out.append(s)
    else: fails.setdefault(err,[]).append(q["id"])
print("ok",len(out),"failed",sum(len(v) for v in fails.items().__iter__().__next__()[1:]) if False else sum(len(v) for v in fails.values()))
for k,v in fails.items(): print("  FAIL",k,len(v),v[:5])
import collections
print("domains:",collections.Counter(x["domain"] for x in out))
print("skills:",len(set(x["skill"] for x in out)))
for s,c in collections.Counter(x["skill"] for x in out).most_common(): print("   ",s,c)
json.dump(out,open("questions.json","w"),ensure_ascii=False)
print("bytes",os.path.getsize("questions.json"))

import pymupdf, re, json, os
SRC=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
R=pymupdf.Rect
MARKER=re.compile(r"^(Question ID \w+|ID: \w+( Answer)?|Correct Answer:|Rationale|Question Difficulty:)")

def text_lines(page):
    out=[]
    for blk in page.get_text("dict")["blocks"]:
        if blk["type"]!=0: continue
        for ln in blk["lines"]: out.append(R(ln["bbox"]))
    return out

def is_underline(r, lines):
    if r.height>2.0: return False
    for ln in lines:
        ov=min(r.x1,ln.x1)-max(r.x0,ln.x0)
        if ov < 0.45*max(r.width,1e-6): continue
        if ln.y0-2 <= r.y0 <= ln.y1+5: return True
    return False

def block_rects(page):
    """Block bboxes widened to include superscript fragments that sit on their lines.

    A superscript is its own PDF block, so a raw block bbox can stop short of it;
    using the widened rect as a figure-band delimiter keeps stray digits out of figures.
    """
    frags=[]
    for bi,blk in enumerate(page.get_text("dict")["blocks"]):
        if blk["type"]!=0: continue
        for ln in blk["lines"]:
            r=R(ln["bbox"]); txt="".join(sp["text"] for sp in ln["spans"])
            if not txt.strip() or r.get_area()<=0: continue
            frags.append({"bi":bi,"r":r,"t":txt})
    frags.sort(key=lambda f:(f["r"].y0,f["r"].x0))
    vlines=[]
    for f in frags:
        hit=None
        for v in vlines:
            oy=min(v["r"].y1,f["r"].y1)-max(v["r"].y0,f["r"].y0)
            if oy > 0.55*min(v["r"].height,f["r"].height): hit=v; break
        if hit: hit["parts"].append(f); hit["r"]|=f["r"]
        else: vlines.append({"r":R(f["r"]),"parts":[f]})
    out={}
    for v in vlines:
        main=max(v["parts"], key=lambda f:f["r"].width)
        bi=main["bi"]
        v["parts"].sort(key=lambda f:f["r"].x0)
        txt="".join(f["t"] for f in v["parts"])
        if bi in out:
            out[bi]["r"]|=v["r"]; out[bi]["t"]+=" "+txt
        else:
            out[bi]={"r":R(v["r"]),"t":txt}
    return list(out.values())

def header_cut(page, qid):
    """Bottom of the metadata header: the y1 of the 'ID: <qid>' label block."""
    for b in page.get_text("blocks"):
        if b[6]==0 and b[4].strip()==f"ID: {qid}":
            return b[3]+6
    return 152.0

def delimiters(page, cut):
    """y-ranges of prose/marker blocks that bound figure whitespace."""
    out=[]
    for b in block_rects(page):
        br=b["r"]; t=b["t"].strip()
        if br.get_area()<=0 or not t: continue
        if br.y1<=cut: continue
        if MARKER.match(t) or (br.x0<=22 and br.x1>=400):
            out.append((br.y0,br.y1))
    return out

def figure_bands(page, cut):
    lines=text_lines(page)
    cand=[]; allr=[]
    for dr in page.get_drawings():
        r=R(dr["rect"])
        if r.get_area()>100000: continue
        if r.y1<=cut: continue
        if 12<=r.x0<=17 and 23<=r.height<=29: continue
        if r.width<=0.6 and r.height<=0.6: continue
        allr.append(r)
        if is_underline(r, lines): continue
        cand.append(r)
    if not cand: return []
    cand.sort(key=lambda r:(r.y0,r.x0))
    clusters=[]; cur=[cand[0]]; bb=R(cand[0])
    for r in cand[1:]:
        if r.y0 <= bb.y1+55: cur.append(r); bb|=r
        else: clusters.append((bb,cur)); cur=[r]; bb=R(r)
    clusters.append((bb,cur))
    dels=delimiters(page, cut)
    top_lim = max(cut, 8.0)
    bands=[]
    for bb,items in clusters:
        if len(items)<3 or bb.width<40 or bb.height<25: continue
        for _ in range(3):
            grow=R(bb.x0-6,bb.y0-6,bb.x1+6,bb.y1+6)
            nb=R(bb)
            for r in allr:
                if grow.contains(R(r.x0,r.y0,max(r.x1,r.x0+0.1),max(r.y1,r.y0+0.1))): nb|=r
            if nb==bb: break
            bb=nb
        above=[d1 for d0,d1 in dels if d1 <= bb.y0+2]
        below=[d0 for d0,d1 in dels if d0 >= bb.y1-2]
        # Prefer the prose gap, but never clip the figure's own geometry ...
        y0=min(max([top_lim]+above)+8, bb.y0-3)
        y1=max((min(below)-2) if below else page.rect.y1-8, bb.y1+1.5)
        # ... and never let that clamp reach into the neighbouring prose either.
        if above: y0=max(y0, max(above)+0.5)
        if below: y1=min(y1, min(below)-0.5)
        if y1-y0 < 20: continue
        bands.append([y0,y1])
    bands.sort()
    merged=[]
    for b in bands:
        if merged and b[0] <= merged[-1][1]+6: merged[-1][1]=max(merged[-1][1],b[1])
        else: merged.append(b)
    return [R(8,y0,page.rect.x1-8,y1) for y0,y1 in merged]

def page_paragraphs(page, cut, bands, qid):
    """Reconstruct paragraphs: merge visual lines (incl. superscripts), join wrapped lines."""
    frags=[]
    for bi,blk in enumerate(page.get_text("dict")["blocks"]):
        if blk["type"]!=0: continue
        for ln in blk["lines"]:
            r=R(ln["bbox"]); txt="".join(sp["text"] for sp in ln["spans"])
            if not txt.strip() or r.get_area()<=0: continue
            frags.append({"bi":bi,"r":r,"t":txt})
    frags.sort(key=lambda f:(f["r"].y0,f["r"].x0))
    vlines=[]
    for f in frags:
        hit=None
        for v in vlines:
            oy=min(v["r"].y1,f["r"].y1)-max(v["r"].y0,f["r"].y0)
            if oy > 0.55*min(v["r"].height,f["r"].height): hit=v; break
        if hit: hit["parts"].append(f); hit["r"]|=f["r"]
        else: vlines.append({"r":R(f["r"]),"parts":[f]})
    paras=[]   # (y0, x0, block_key, text)
    for v in vlines:
        cy=(v["r"].y0+v["r"].y1)/2
        if v["r"].y1<=cut: continue
        if any(fr.y0<=cy<=fr.y1 for fr in bands): continue
        v["parts"].sort(key=lambda f:f["r"].x0)
        txt="".join(f["t"] for f in v["parts"])
        main=max(v["parts"], key=lambda f:f["r"].width)
        t=txt.strip()
        if not t: continue
        if t==f"Question ID {qid}" or t==f"ID: {qid}": continue
        paras.append({"y":v["r"].y0,"x":main["r"].x0,"bi":main["bi"],"t":txt})
    # group consecutive visual lines sharing a block into one paragraph
    out=[]
    for p in paras:
        if out and out[-1]["bi"]==p["bi"]:
            out[-1]["t"]=out[-1]["t"].rstrip()+" "+p["t"].lstrip()
        else:
            out.append({"bi":p["bi"],"y":p["y"],"x":p["x"],"t":p["t"]})
    return [(o["y"],o["x"],clean(o["t"])) for o in out if clean(o["t"])]

def clean(s): return re.sub(r"\s+"," ", s.replace("\xa0"," ")).strip()

def parse_pdf(fname, difficulty, outdir, scale=3):
    doc=pymupdf.open(f"{SRC}/{fname}")
    starts=[i for i,p in enumerate(doc) if re.match(r"^Question ID (\w+)", p.get_text())]
    qs=[]; warn=[]
    for qi,sp in enumerate(starts):
        ep = starts[qi+1]-1 if qi+1<len(starts) else len(doc)-1
        qid=re.match(r"^Question ID (\w+)", doc[sp].get_text()).group(1)
        meta={}; parts=[]; figs=[]
        for pno in range(sp,ep+1):
            page=doc[pno]; is_start=(pno==sp)
            cut = header_cut(page,qid) if is_start else 8.0
            bands=figure_bands(page,cut)
            blocks=[b for b in page.get_text("blocks") if b[6]==0]
            if is_start:
                hdr=[b for b in blocks if b[3]<=cut]
                for label,key in (("Test","test"),("Domain","domain"),("Skill","skill")):
                    lb=next((b for b in hdr if b[4].strip()==label), None)
                    if lb is None: continue
                    vals=[b for b in hdr if abs(b[0]-lb[0])<6 and b[1]>lb[3]]
                    if vals: meta[key]=clean(min(vals,key=lambda b:b[1])[4]).replace("\n"," ")
            for fr in bands:
                if fr.height>640: warn.append((qid,"tall band",round(fr.height)))
                pix=page.get_pixmap(clip=fr, matrix=pymupdf.Matrix(scale,scale))
                name=f"{qid}_{len(figs)}.png"; pix.save(os.path.join(outdir,name))
                figs.append({"file":name,"page":pno,"y":float(fr.y0),"w":pix.width,"h":pix.height})
            for y,x,t in page_paragraphs(page, cut, bands, qid):
                parts.append((pno,y,x,t))
        parts.sort()
        si=next((i for i,p in enumerate(parts) if re.match(rf"^ID: {qid} Answer",p[3].strip())),None)
        if si is None: warn.append((qid,"no answer marker")); continue
        jb=lambda ps:"\n".join(clean(p[3]) for p in ps if clean(p[3]))
        qs.append(dict(id=qid,difficulty=difficulty,meta=meta,figs=figs,
                       stem_raw=jb(parts[:si]),ans_raw=jb(parts[si+1:])))
    return qs,warn

if __name__=="__main__":
    out="figures_raw"; os.makedirs(out,exist_ok=True)
    allq=[]; W=[]
    for fn,diff in [("easy-questions.pdf","Easy"),("medium-questions.pdf","Medium"),("hard-questions.pdf","Hard")]:
        qs,w=parse_pdf(fn,diff,out); print(diff,len(qs),"warn",len(w)); allq+=qs; W+=w
    json.dump(allq,open("raw.json","w"),indent=1)
    print("total",len(allq),"qs w/figs",sum(1 for q in allq if q["figs"]),"files",len(os.listdir(out)))
    for x in W[:20]: print("WARN",x)

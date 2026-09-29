"""Extract SAT/PSAT Math questions from sat-math-all.pdf / psat-math-all.pdf.

Unlike the Reading & Writing PDFs, math notation here isn't real text — every
formula, variable and number is drawn as an inline vector graphic, so there's
nothing to reconstruct as a string. Instead each question is captured as a
handful of cropped page images: one for the stem (prompt text + any diagram,
which naturally fall in the same region so one crop gets both), one per
multiple-choice option, and one or more for the rationale (long rationales
can spill onto a following page). Only "Question", "Answer", "Correct
Answer:" and "Rationale" are real text labels, so their block positions are
used purely as crop boundaries. The one exception: "Correct Answer: <value>"
is real text too, so the grading key comes straight from there — a letter
for multiple choice, or one or more comma-separated accepted strings for
student-produced-response (free numeric entry) questions.

Output: raw.json (list of question dicts with image filenames) + PNGs in
figures_raw/. Web-only — never touches SATPrep/SATPrep/Resources.
"""
import pymupdf, re, json, os, sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
R = pymupdf.Rect
MARGIN = 8

def blocks(page):
    return [b for b in page.get_text("blocks") if b[6] == 0]

def clean(s):
    return re.sub(r"\s+", " ", s.replace("\xa0", " ")).strip()

def find_after(doc, sp, ep, start_page, start_y, pred):
    """First text block matching pred, scanning from (start_page, start_y) to ep inclusive."""
    for pno in range(start_page, ep + 1):
        y0 = start_y if pno == start_page else -1
        for b in blocks(doc[pno]):
            if pno == start_page and b[1] < y0:
                continue
            t = clean(b[4])
            if pred(t):
                return {"page": pno, "y0": b[1], "y1": b[3], "text": t}
    return None

def label_bottom(page, label):
    for b in blocks(page):
        if clean(b[4]) == label:
            return b[3]
    return None

def crop_span(doc, sp_page, sp_y, ep_page, ep_y, outdir, prefix, scale=2.2):
    files = []
    for pno in range(sp_page, ep_page + 1):
        page = doc[pno]
        y0 = sp_y if pno == sp_page else MARGIN
        y1 = ep_y if pno == ep_page else page.rect.y1 - MARGIN
        if y1 - y0 < 4:
            continue
        rect = R(MARGIN, y0, page.rect.x1 - MARGIN, y1)
        pix = page.get_pixmap(clip=rect, matrix=pymupdf.Matrix(scale, scale))
        fname = f"{prefix}_{len(files)}.png"
        pix.save(os.path.join(outdir, fname))
        files.append(fname)
    return files

def extract_meta(page, cut):
    hdr = [(R(ln["bbox"]), clean("".join(sp["text"] for sp in ln["spans"])))
           for blk in page.get_text("dict")["blocks"] if blk["type"] == 0
           for ln in blk["lines"] if ln["bbox"][3] <= cut]
    meta = {}
    for label, key in (("Domain", "domain"), ("Skill", "skill")):
        lb = next((r for r, t in hdr if t == label), None)
        if lb is None:
            continue
        vals = [(r, t) for r, t in hdr if abs(r.x0 - lb.x0) < 6 and r.y0 > lb.y1 and t]
        if vals:
            meta[key] = " ".join(t for r, t in sorted(vals, key=lambda v: v[0].y0))
    return meta

def parse(fname, exam, outdir, scale=2.2, limit=None):
    doc = pymupdf.open(f"{SRC}/{fname}")
    starts = [i for i, p in enumerate(doc) if re.match(r"^Question ID: (\w+)", p.get_text())]
    if limit:
        starts = starts[:limit]
    qs = []
    warn = []
    for qi, sp in enumerate(starts):
        ep = starts[qi + 1] - 1 if qi + 1 < len(starts) else len(doc) - 1
        qid = re.match(r"^Question ID: (\w+)", doc[sp].get_text()).group(1)
        page0 = doc[sp]

        cut = (label_bottom(page0, "Question") or 140.0) + 1
        meta = extract_meta(page0, cut)
        diff_b = next((b for b in blocks(page0) if b[1] <= cut and
                        clean(b[4]) in ("Easy", "Medium", "Hard")), None)
        difficulty = clean(diff_b[4]) if diff_b else "Medium"

        q_lbl = next((b for b in blocks(page0) if clean(b[4]) == "Question"), None)
        if q_lbl is None:
            warn.append((qid, "no Question label")); continue
        stem_start = (sp, q_lbl[3] + 2)

        answer_evt = find_after(doc, sp, ep, *stem_start, lambda t: t == "Answer")
        ca_evt = find_after(doc, sp, ep, *stem_start, lambda t: t.startswith("Correct Answer:"))
        if ca_evt is None:
            warn.append((qid, "no Correct Answer")); continue

        is_mc = answer_evt is not None and (
            answer_evt["page"], answer_evt["y0"]) < (ca_evt["page"], ca_evt["y0"])
        stem_end = answer_evt if is_mc else ca_evt

        stem_files = crop_span(doc, stem_start[0], stem_start[1],
                                stem_end["page"], stem_end["y0"] - 2, outdir, f"{qid}_stem", scale)
        if not stem_files:
            warn.append((qid, "empty stem crop")); continue

        choice_files = None
        correct = None
        correct_answers = None
        if is_mc:
            cursor = (answer_evt["page"], answer_evt["y1"] + 1)
            positions = []
            ok = True
            for L in "ABCD":
                pat = re.compile(rf"^{L}\.\s")
                pos = find_after(doc, sp, ep, *cursor, lambda t, pat=pat: pat.match(t) or t == L + ".")
                if pos is None:
                    ok = False; break
                positions.append(pos)
                cursor = (pos["page"], pos["y1"] + 0.5)
            if not ok:
                warn.append((qid, "missing choice label")); continue
            bounds = positions + [ca_evt]
            choice_files = []
            for i in range(4):
                b0, b1 = bounds[i], bounds[i + 1]
                files = crop_span(doc, b0["page"], b0["y0"] - 1, b1["page"], b1["y0"] - 1,
                                   outdir, f"{qid}_choice{i}", scale)
                if not files:
                    ok = False; break
                choice_files.append(files)
            if not ok:
                warn.append((qid, "empty choice crop")); continue
            letter = ca_evt["text"].split(":", 1)[1].strip()
            if letter not in "ABCD":
                warn.append((qid, f"bad MC answer {letter!r}")); continue
            correct = "ABCD".index(letter)
        else:
            raw = ca_evt["text"].split(":", 1)[1].strip()
            correct_answers = [s.strip() for s in raw.split(",") if s.strip()]
            if not correct_answers:
                warn.append((qid, "empty SPR answer")); continue

        rat_evt = find_after(doc, sp, ep, ca_evt["page"], ca_evt["y1"] + 1, lambda t: t == "Rationale")
        if rat_evt is None:
            warn.append((qid, "no Rationale")); continue
        last_page = doc[ep]
        rationale_files = crop_span(doc, rat_evt["page"], rat_evt["y1"] + 2, ep,
                                     last_page.rect.y1 - MARGIN, outdir, f"{qid}_rationale", scale)
        if not rationale_files:
            warn.append((qid, "empty rationale crop")); continue

        qs.append(dict(
            id=qid, exam=exam, difficulty=difficulty,
            domain=meta.get("domain", "Math"), skill=meta.get("skill", "Unknown"),
            type=("mc" if is_mc else "spr"),
            stemImages=stem_files,
            choiceImages=choice_files,
            correct=correct,
            correctAnswers=correct_answers,
            rationaleImages=rationale_files,
        ))
    return qs, warn

if __name__ == "__main__":
    out = "figures_raw_math"
    os.makedirs(out, exist_ok=True)
    allq = []
    W = []
    for fname, exam in (("sat-math-all.pdf", "SAT"), ("psat-math-all.pdf", "PSAT")):
        qs, warn = parse(fname, exam, out, scale=1.8)
        print(exam, "ok", len(qs), "warn", len(warn))
        allq += qs
        W += warn
    json.dump(allq, open("math-raw.json", "w"), indent=1)
    print("total", len(allq), "files", len(os.listdir(out)))
    for x in W[:30]:
        print("WARN", x)
    print("warn total", len(W))

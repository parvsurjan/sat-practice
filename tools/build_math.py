"""Trim/resize the raw math crops and emit docs/data/math-questions.json + math-figures/.

Web-only: writes into docs/, never into SATPrep/SATPrep/Resources, so the iOS
app's bundle and on-device storage are unaffected by the math question bank.
"""
import json, os, glob, shutil
from PIL import Image, ImageChops

SRC = "figures_raw_math"
DST = "docs/data/math-figures"
MAX_WIDTH = 1000

def trim_and_save(name):
    im = Image.open(os.path.join(SRC, name)).convert("RGB")
    bg = Image.new("RGB", im.size, (255, 255, 255))
    bbox = ImageChops.difference(im, bg).convert("L").point(lambda p: 255 if p > 12 else 0).getbbox()
    if bbox:
        p = 6
        bbox = (max(0, bbox[0] - p), max(0, bbox[1] - p),
                 min(im.width, bbox[2] + p), min(im.height, bbox[3] + p))
        im = im.crop(bbox)
    if im.width > MAX_WIDTH:
        im = im.resize((MAX_WIDTH, round(im.height * MAX_WIDTH / im.width)), Image.LANCZOS)
    im = im.convert("L")  # these are all black text/lines on white; grayscale cuts size ~3x
    out = os.path.join(DST, name)
    im.save(out, optimize=True, compress_level=9)
    return os.path.getsize(out)

def main():
    raw = json.load(open("math-raw.json"))
    shutil.rmtree(DST, ignore_errors=True)
    os.makedirs(DST, exist_ok=True)

    out = []
    total_bytes = 0
    for q in raw:
        def process(files):
            nonlocal total_bytes
            r = []
            for f in files:
                total_bytes += trim_and_save(f)
                r.append(f)
            return r

        entry = dict(
            id=q["id"], exam=q["exam"], difficulty=q["difficulty"],
            domain=q["domain"], skill=q["skill"], type=q["type"],
            stemImages=process(q["stemImages"]),
            rationaleImages=process(q["rationaleImages"]),
        )
        if q["type"] == "mc":
            entry["choiceImages"] = [process(files) for files in q["choiceImages"]]
            entry["correct"] = q["correct"]
        else:
            entry["correctAnswers"] = q["correctAnswers"]
        out.append(entry)

    json.dump(out, open("docs/data/math-questions.json", "w"), ensure_ascii=False)
    print("questions", len(out))
    print("mc", sum(1 for q in out if q["type"] == "mc"))
    print("spr", sum(1 for q in out if q["type"] == "spr"))
    print("images", len(glob.glob(DST + "/*.png")), "total", round(total_bytes / 1e6, 1), "MB")
    print("questions.json bytes", os.path.getsize("docs/data/math-questions.json"))

if __name__ == "__main__":
    main()

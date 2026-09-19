from PIL import Image, ImageChops
import glob,os,shutil
src,dst="figures_raw","figures"
shutil.rmtree(dst,ignore_errors=True); os.makedirs(dst)
tot=0
for f in sorted(glob.glob(src+"/*.png")):
    im=Image.open(f).convert("RGB")
    bg=Image.new("RGB",im.size,(255,255,255))
    bbox=ImageChops.difference(im,bg).convert("L").point(lambda p:255 if p>12 else 0).getbbox()
    if bbox:
        p=14
        bbox=(max(0,bbox[0]-p),max(0,bbox[1]-p),min(im.width,bbox[2]+p),min(im.height,bbox[3]+p))
        im=im.crop(bbox)
    if im.width>1400:
        im=im.resize((1400,round(im.height*1400/im.width)), Image.LANCZOS)
    out=os.path.join(dst,os.path.basename(f))
    im.save(out,optimize=True); tot+=os.path.getsize(out)
print(len(glob.glob(dst+"/*.png")),"files", round(tot/1e6,2),"MB")

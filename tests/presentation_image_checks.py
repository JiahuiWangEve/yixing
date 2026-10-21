"""Visible seal detection: central square ink footprint minus pre-action red ink."""
import io
from PIL import Image, ImageChops

def seal_score(data, baseline, logical_size):
    frame=Image.open(io.BytesIO(data)).convert('RGB')
    before=Image.open(io.BytesIO(baseline)).convert('RGB').resize(frame.size)
    lw,lh=logical_size
    scale=min(frame.width/lw,frame.height/lh)
    side=min(260,min(lw,lh)*.5)*scale
    cx,cy=frame.width/2,frame.height/2
    roi=(int(cx-side*.75),int(cy-side*.75),int(cx+side*.75),int(cy+side*.75))
    current=frame.crop(roi);old=before.crop(roi)
    def red(rgb):
        r,g,b=rgb
        return r>110 and r>g*1.8 and r>b*1.8
    # Existing player red ink is never seal evidence. Require visibly new ink.
    mask=Image.new('L',current.size)
    mask.putdata([255 if red(now) and not red(was) and sum(abs(a-b) for a,b in zip(now,was))>50 else 0
                  for now,was in zip(current.getdata(),old.getdata())])
    bbox=mask.getbbox()
    if not bbox:return 0
    width,height=bbox[2]-bbox[0],bbox[3]-bbox[1]
    if min(width,height)<side*.65 or not .65<width/height<1.5:return 0
    return mask.histogram()[255]

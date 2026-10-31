#!/usr/bin/env python3
"""Offline edit: real sources only. Missing media becomes an explicitly marked slate."""
import argparse, json, math, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
ROOT = Path(__file__).resolve().parents[1]
PURPLE = '#6e24e6'; YELLOW = '#ffc93c'; INK = '#211434'; PAPER = '#f8f5ff'

def font(size):
    f = ImageFont.truetype(str(ROOT/'assets/DMSans.ttf'), size)
    f.set_variation_by_axes([14, 650])
    return f

def probe(path):
    return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(path)]))

def stroke(d, points, progress, color, width=5):
    """Draw a deterministic wobbly pencil line progressively, without a dependency."""
    n = max(0, min(len(points), int(len(points)*progress)))
    if n > 1: d.line(points[:n], fill=color, width=width, joint='curve')

def make_frame(size, scene, idx, t, duration, media, final):
    W,H=size; s=W/1920
    im=Image.new('RGB',(W,H),PAPER); d=ImageDraw.Draw(im)
    def text_center(text, y, px, color=INK):
        f=font(round(px*s)); box=d.textbbox((0,0),text,font=f)
        d.text(((W-(box[2]-box[0]))/2,y),text,font=f,fill=color)
    def line(points,p=1,color=PURPLE,width=5):
        stroke(d,[(round(x*s),round(y*s)) for x,y in points],p,color,max(1,round(width*s)))
    wide=W>H
    title_y=round((65 if wide else 86)*s)
    if scene.get('endcard'):
        text_center('DogBar',round(H*.12),104)
        dog=Image.open(ROOT/'assets/dog.jpg').convert('RGB')
        n=round(W*.19 if wide else W*.28)
        dog=ImageOps.fit(dog,(n,n)); mask=Image.new('L',(n,n)); ImageDraw.Draw(mask).ellipse((0,0,n-1,n-1),fill=255)
        # Small settling bounce, graphic only; no app behaviour is simulated.
        y=round(H*.31 + math.sin(min(t,1)*math.pi*2)*8*s*max(0,1-t))
        im.paste(dog,((W-n)//2,y),mask)
        d=ImageDraw.Draw(im)
        text_center(scene['caption'],round(H*.68),56)
        label='dogbar.hristijan.dev'; f=font(round(42*s)); b=d.textbbox((0,0),label,font=f)
        x=(W-b[2])/2; y=round(H*.82)
        d.rounded_rectangle((x-35*s,y-16*s,x+b[2]+35*s,y+69*s),radius=23*s,fill=YELLOW)
        d.text((x,y),label,font=f,fill=INK)
        line([(770+i*3,225+math.sin(i/9)*3) for i in range(125)],min(1,t/0.7))
        return im
    text_center(scene['caption'],title_y,64 if wide else 76)
    # Drawn underline is outside footage; nothing obscures the Dock or preview panel.
    baseline=(title_y/s)+95
    line([(650+i*5,baseline+math.sin(i/7)*3) for i in range(125)],max(0,min(1,(t-.25)/.65)))
    x0=round(W*.045); x1=round(W*.955)
    y0=round(H*(.235 if wide else .32)); y1=round(H*(.91 if wide else .85))
    d.rounded_rectangle((x0-3,y0-3,x1+3,y1+3),radius=20*s,fill='#e6ddef')
    if media:
        fit=ImageOps.contain(media,(x1-x0,y1-y0),Image.Resampling.LANCZOS)
        d.rectangle((x0,y0,x1,y1),fill='#1d1825')
        im.paste(fit,(x0+(x1-x0-fit.width)//2,y0+(y1-y0-fit.height)//2))
    else:
        d.rounded_rectangle((x0,y0,x1,y1),radius=20*s,fill='#eee7fa')
        # Neutral recording slate, deliberately no fabricated macOS UI.
        text_center('Recording needed',round((y0+y1)/2-22*s),40,PURPLE)
        cy=(y0+y1)/2-100*s; cx=W/2
        pts=[(cx/s+36*math.cos(a),cy/s+36*math.sin(a)) for a in [i*math.tau/120 for i in range(121)]]
        line(pts,min(1,t/.8),PURPLE,4)
    if not final:
        # Draft badge is a symbol to preserve the six-word caption budget.
        d.ellipse((W-48*s,25*s,W-30*s,43*s),fill=YELLOW)
    if scene.get('source','') and str(scene.get('source')).lower().endswith(('.png','.jpg','.jpeg')):
        text_center('Still',round(H*.94),24,PURPLE)
    # Optional manual annotations in normalized footage-box coordinates.
    for a in scene.get('annotations',[]):
        pts=[(x0+x*(x1-x0),y0+y*(y1-y0)) for x,y in a['points']]
        stroke(d,pts,max(0,min(1,(t-a.get('at',1))/.6)),YELLOW,max(2,round(4*s)))
    return im

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--final',action='store_true'); ap.add_argument('--format',choices=['wide','square','both'],default='both'); args=ap.parse_args()
    edit=json.loads((ROOT/'edit.json').read_text()); fps=edit['fps']
    # Fail early, before any export, if an entered source is missing/too short.
    for sc in edit['scenes']:
        if sc.get('endcard'): continue
        if args.final and (not sc.get('source') or not sc.get('verified')):
            sys.exit(f"Final blocked: {sc['id']} needs real media and verified:true.")
        if sc.get('source'):
            path=ROOT/sc['source']
            if not path.is_file(): sys.exit(f'Missing media: {path}')
            if path.suffix.lower() not in ('.png','.jpg','.jpeg'):
                length=float(probe(path)['format']['duration'])
                if length+0.02 < sc.get('start',0)+sc['duration']: sys.exit(f"Too short: {path}")
    formats=[('wide',(1920,1080)),('square',(1080,1080))] if args.format=='both' else [(args.format,(1920,1080) if args.format=='wide' else (1080,1080))]
    for name,size in formats:
        W,H=size; tag='final' if args.final else 'animatic'
        out=ROOT/f'output/dogbar-{tag}-{name}.mp4'; out.parent.mkdir(exist_ok=True)
        silent=out.with_name(out.stem+'-silent.mp4') if edit.get('music') else out
        cmd=['ffmpeg','-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(fps),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(silent)]
        enc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
        try:
            for idx,sc in enumerate(edit['scenes']):
                print(name,sc['id'],flush=True); decoder=None; still=None; frames=round(sc['duration']*fps)
                if sc.get('source'):
                    path=ROOT/sc['source']
                    if path.suffix.lower() in ('.png','.jpg','.jpeg'): still=Image.open(path).convert('RGB')
                    else:
                        # Contain the complete screen; crop must be done deliberately upstream.
                        decoder=subprocess.Popen(['ffmpeg','-v','error','-ss',str(sc.get('start',0)),'-i',str(path),'-vf',f'fps={fps},scale={W}:{H}:force_original_aspect_ratio=decrease,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2','-frames:v',str(frames),'-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
                try:
                    for n in range(frames):
                        media=still
                        if decoder:
                            buf=decoder.stdout.read(W*H*3)
                            if len(buf)!=W*H*3: raise RuntimeError(f"Decode ended early: {sc['id']}")
                            media=Image.frombytes('RGB',size,buf)
                        frame=make_frame(size,sc,idx,n/fps,sc['duration'],media,args.final)
                        enc.stdin.write(frame.tobytes())
                finally:
                    if decoder:
                        decoder.stdout.close()
                        if decoder.wait()!=0: raise RuntimeError('Source decoder failed')
            enc.stdin.close()
            if enc.wait()!=0: raise RuntimeError('Encode failed')
        except BaseException:
            enc.kill(); enc.wait(); raise
        if edit.get('music'):
            music=ROOT/edit['music']
            if not music.is_file(): sys.exit(f'Missing music: {music}')
            length=sum(s['duration'] for s in edit['scenes'])
            subprocess.run(['ffmpeg','-v','error','-y','-i',str(silent),'-stream_loop','-1','-i',str(music),'-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a','aac','-af',f'volume=0.18,afade=t=in:d=0.5,afade=t=out:st={length-1.5}:d=1.5','-t',str(length),'-movflags','+faststart',str(out)],check=True)
            silent.unlink()
        print(out,flush=True)
if __name__=='__main__': main()

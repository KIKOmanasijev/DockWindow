#!/usr/bin/env python3
"""Decode one frame per second and build review sheets; verify technical delivery."""
import json, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
edit=json.loads((ROOT/'edit.json').read_text()); expected=sum(s['duration'] for s in edit['scenes'])
reports=[]
for video in sorted((ROOT/'output').glob('dogbar-*.mp4')):
    if '-silent' in video.stem: continue
    info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(video)]))
    stream=next(s for s in info['streams'] if s['codec_type']=='video')
    assert abs(float(info['format']['duration'])-expected)<0.1
    assert stream['codec_name']=='h264' and stream['pix_fmt']=='yuv420p'
    assert (stream['width'],stream['height']) in [(1920,1080),(1080,1080)]
    assert stream['avg_frame_rate']==f"{edit['fps']}/1"
    frames=ROOT/'output'/f'{video.stem}-frames'; frames.mkdir(exist_ok=True)
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(video),'-vf','fps=1,scale=320:-1',str(frames/'%02d.jpg')],check=True)
    files=sorted(frames.glob('*.jpg')); assert len(files)==expected
    th=Image.open(files[0]).height; cellh=th+26
    sheet=Image.new('RGB',(320*8,cellh*5),'#211434'); d=ImageDraw.Draw(sheet)
    for i,p in enumerate(files):
        x=i%8*320; y=i//8*cellh
        sheet.paste(Image.open(p),(x,y)); d.text((x+8,y+th+4),f'{i:02d}s',fill='white')
    sheet.save(ROOT/'output'/f'{video.stem}-contact.jpg')
    reports.append({'file':video.name,'seconds':expected,'size':[stream['width'],stream['height']],'fps':stream['avg_frame_rate'],'codec':stream['codec_name'],'pixel_format':stream['pix_fmt'],'frames_reviewed_at_1fps':len(files)})
assert reports, 'Render first'
(ROOT/'output/qa.json').write_text(json.dumps(reports,indent=2)+'\n')
print(json.dumps(reports,indent=2))

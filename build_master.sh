#!/bin/bash
# Upload-ready master: 1080p, burned captions (per-block Whisper), plus thumbnail.
# Requires env: VIDEO_URL (PUT target for final_master.mp4), THUMB_URL (PUT target for thumbnail.jpg)
set -e
RAW=https://raw.githubusercontent.com/josephgshamoon/yt/claude/video-script-analysis-1hqa4f
KF105="https://d8j0ntlcm91z4.cloudfront.net/user_3CTWkaWL57cqtPY0K9yR9Fc5srU/hf_20260809_102108_7b2045ce-db33-4d14-80dd-1092beb24e34.png"
curl -fsSL $RAW/clips.txt -o clips.txt
curl -fsSL $RAW/voices_rough.txt -o voices.txt
mkdir -p b v s c
i=0; while read -r u; do i=$((i+1)); n=$(printf '%02d' $i); [ -s b/$n.mp4 ] || curl -fsSL --retry 3 "$u" -o b/$n.mp4; done < clips.txt
echo "CLIPS_FETCHED"
i=0; while read -r u; do i=$((i+1)); n=$(printf '%02d' $i); [ -s v/$n.wav ] || curl -fsSL --retry 3 "$u" -o v/$n.wav; done < voices.txt
echo "VOICES_FETCHED"
python3 - <<'PYEOF'
from faster_whisper import WhisperModel
import os
model = WhisperModel("base", device="cpu", compute_type="int8")
def fmt(t):
    t += 0.2
    h=int(t//3600); m=int(t%3600//60); s=int(t%60); ms=int((t-int(t))*1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
for i in range(1,61):
    n=f"{i:02d}"
    segs,_ = model.transcribe(f"v/{n}.wav", language="en", vad_filter=True)
    lines=[]
    for k,seg in enumerate(segs,1):
        lines.append(f"{k}\n{fmt(seg.start)} --> {fmt(seg.end)}\n{seg.text.strip()}\n")
    open(f"c/{n}.srt","w").write("\n".join(lines))
    print("SRT",n,len(lines),flush=True)
PYEOF
echo "CAPTIONS_DONE"
: > list_gen.txt
STYLE="FontName=Montserrat,FontSize=15,Bold=1,PrimaryColour=&H00FFFFFF,OutlineColour=&HA0000000,Outline=1.6,Shadow=0,MarginV=34"
for i in $(seq 1 60); do
  n=$(printf '%02d' $i)
  vd=$(ffprobe -v error -show_entries format=duration -of csv=p=0 v/$n.wav)
  t=$(python3 -c "print(round(max(10.0, float('$vd') + 0.6), 2))")
  SUB=""
  [ -s c/$n.srt ] && SUB=",subtitles=c/$n.srt:force_style='$STYLE'"
  ffmpeg -y -loglevel error -i b/$n.mp4 -i v/$n.wav -filter_complex "[0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=25,tpad=stop_mode=clone:stop_duration=15,trim=0:$t,setpts=PTS-STARTPTS$SUB[v];[1:a]adelay=200|200,apad[a]" -map "[v]" -map "[a]" -t $t -c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p -c:a aac -b:a 160k -ar 44100 -ac 2 s/$n.ts
  echo "file 's/$n.ts'" >> list_gen.txt
  echo "SEG $n done t=$t"
done
ffmpeg -y -loglevel error -f concat -safe 0 -i list_gen.txt -c copy -movflags +faststart final_master.mp4
echo "FINAL_DURATION $(ffprobe -v error -show_entries format=duration -of csv=p=0 final_master.mp4)"
curl -f -X PUT --upload-file final_master.mp4 -H "Content-Type: video/mp4" "$VIDEO_URL" && echo "VIDEO_UPLOADED"
curl -fsSL "$KF105" -o kf105.png
FONT=$(fc-list | grep -io 'montserrat[^:]*bold[^:]*' | head -1 || true)
convert kf105.png -resize 1280x720^ -gravity center -extent 1280x720 \
  \( -size 1280x720 gradient:none-black -alpha set -channel A -evaluate multiply 0.75 \) -gravity south -composite \
  -gravity south -font DejaVu-Sans-Bold -pointsize 92 -stroke black -strokewidth 7 -fill white -annotate +0+52 "HE NEVER TOLD ANYONE." \
  -stroke none -fill white -annotate +0+52 "HE NEVER TOLD ANYONE." \
  -quality 90 thumbnail.jpg
curl -f -X PUT --upload-file thumbnail.jpg -H "Content-Type: image/jpeg" "$THUMB_URL" && echo "THUMB_UPLOADED"
echo "ALL_DONE"

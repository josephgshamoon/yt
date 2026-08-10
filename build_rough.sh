#!/bin/bash
# Rough-cut assembler for video #1 preview — 720p, voice-led block lengths.
set -e
RAW=https://raw.githubusercontent.com/josephgshamoon/yt/claude/video-script-analysis-1hqa4f
KF102="https://d8j0ntlcm91z4.cloudfront.net/user_3CTWkaWL57cqtPY0K9yR9Fc5srU/hf_20260809_102323_55421999-ac72-4a71-a17a-83f7c313c0ac.png"
KF106="https://d8j0ntlcm91z4.cloudfront.net/user_3CTWkaWL57cqtPY0K9yR9Fc5srU/hf_20260809_102108_bdd293b3-337b-4034-8124-64c6a8f16c55.png"
curl -fsSL $RAW/clips.txt -o clips.txt
curl -fsSL $RAW/voices_rough.txt -o voices.txt
mkdir -p b v s
i=0
while read -r u; do
  i=$((i+1)); n=$(printf '%02d' $i)
  case "$u" in
    MISSING_BLOCK_2) [ -s b/$n.png ] || curl -fsSL "$KF102" -o b/$n.png ;;
    MISSING_BLOCK_6) [ -s b/$n.png ] || curl -fsSL "$KF106" -o b/$n.png ;;
    *) [ -s b/$n.mp4 ] || curl -fsSL --retry 3 "$u" -o b/$n.mp4 ;;
  esac
done < clips.txt
echo "CLIPS_FETCHED"
i=0
while read -r u; do i=$((i+1)); n=$(printf '%02d' $i); [ -s v/$n.wav ] || curl -fsSL --retry 3 "$u" -o v/$n.wav; done < voices.txt
echo "VOICES_FETCHED"
: > list_gen.txt
for i in $(seq 1 60); do
  n=$(printf '%02d' $i)
  vd=$(ffprobe -v error -show_entries format=duration -of csv=p=0 v/$n.wav)
  t=$(python3 -c "print(round(max(10.0, float('$vd') + 0.6), 2))")
  if [ -f b/$n.png ]; then
    ffmpeg -y -loglevel error -loop 1 -i b/$n.png -i v/$n.wav -filter_complex "[0:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=25[v];[1:a]adelay=200|200,apad[a]" -map "[v]" -map "[a]" -t $t -c:v libx264 -preset ultrafast -crf 26 -pix_fmt yuv420p -c:a aac -b:a 128k -ar 44100 -ac 2 s/$n.ts
  else
    ffmpeg -y -loglevel error -i b/$n.mp4 -i v/$n.wav -filter_complex "[0:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=25,tpad=stop_mode=clone:stop_duration=15,trim=0:$t,setpts=PTS-STARTPTS[v];[1:a]adelay=200|200,apad[a]" -map "[v]" -map "[a]" -t $t -c:v libx264 -preset ultrafast -crf 26 -pix_fmt yuv420p -c:a aac -b:a 128k -ar 44100 -ac 2 s/$n.ts
  fi
  echo "file 's/$n.ts'" >> list_gen.txt
  echo "SEG $n done t=$t"
done
ffmpeg -y -loglevel error -f concat -safe 0 -i list_gen.txt -c copy -movflags +faststart rough_cut.mp4
echo "FINAL_DURATION $(ffprobe -v error -show_entries format=duration -of csv=p=0 rough_cut.mp4)"
curl -f -X PUT --upload-file rough_cut.mp4 -H "Content-Type: video/mp4" "$UPLOAD_URL" && echo "UPLOADED_OK"

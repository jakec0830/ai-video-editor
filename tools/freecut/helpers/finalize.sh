#!/usr/bin/env bash
# finalize.sh — mix BGM under a rendered video and produce the final deliverable.
#
# The last pipeline step, after hyperframes render. Video stream is COPIED
# (no re-encode, ~1s), so run this freely after every re-render.
#
# What it does:
#   - loops the BGM to cover the full video (no dead silence anywhere)
#   - fades BGM in (1.0s) and out (1.5s), volume default 0.18 (under the voice)
#   - mixes voice + BGM, limits peaks at 0.97 to prevent clipping
#
# Usage:
#   bash finalize.sh <video.mp4> <bgm.mp3> <output.mp4> [bgm_volume]
#
#   bgm_volume: 0.15-0.25 sits under speech (default 0.18)
#
# Remember: re-run this after EVERY re-render — the mix lives only in the
# output file, not in the hyperframes project.
set -euo pipefail

if [ $# -lt 3 ]; then
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -18
  exit 1
fi

VIDEO="$1"; BGM="$2"; OUT="$3"; VOL="${4:-0.18}"

DUR=$(ffprobe -v error -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 "$VIDEO")
FADE_OUT_START=$(python3 -c "print(max(0, $DUR - 1.6))")

ffmpeg -y -i "$VIDEO" -stream_loop -1 -i "$BGM" -filter_complex "
[1:a]atrim=0:${DUR},afade=t=in:st=0:d=1.0,afade=t=out:st=${FADE_OUT_START}:d=1.5,volume=${VOL}[bgm];
[0:a][bgm]amix=inputs=2:normalize=0[mix];[mix]alimiter=limit=0.97[aout]
" -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k "$OUT"

echo ""
echo "done: $OUT ($(ffprobe -v error -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 "$OUT")s, bgm vol ${VOL})"

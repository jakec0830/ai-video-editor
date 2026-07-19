#!/usr/bin/env python3
"""
xref_silence.py — cross-reference a word-level transcript against real audio silence.

Whisper collapses repeated words and merges trailing pauses into a word's end
time. This script finds those lies BEFORE the first cut by comparing each
transcript word span against ffmpeg silencedetect ground truth.

Flags:
  MERGE   — a single word token contains a real silence >= gap threshold
            (likely repeated words collapsed, or dead air stuck on the word end)
  LONG    — word duration is abnormally long for its character count
            (a short word holding a long timestamp = suspicious)

Usage: python3 xref_silence.py <video> <transcript.json> [--noise -30] [--gap 0.30]
"""
import argparse, json, subprocess, re, sys

def silence_windows(video, noise_db, min_sil):
    cmd = ["ffmpeg", "-i", video, "-af",
           f"silencedetect=noise={noise_db}dB:d={min_sil}", "-f", "null", "-"]
    out = subprocess.run(cmd, capture_output=True, text=True).stderr
    starts = [float(m) for m in re.findall(r"silence_start: ([\d.]+)", out)]
    ends   = [float(m) for m in re.findall(r"silence_end: ([\d.]+)", out)]
    return list(zip(starts, ends))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("transcript")
    ap.add_argument("--noise", default="-30", help="silence threshold dB (default -30)")
    ap.add_argument("--gap", type=float, default=0.30,
                    help="min silence inside a word to flag MERGE (default 0.30s)")
    ap.add_argument("--long", type=float, default=0.35,
                    help="seconds-per-character over which a word is flagged LONG (default 0.35)")
    a = ap.parse_args()

    words = [w for w in json.load(open(a.transcript))["words"] if w.get("type") == "word"]
    sils = silence_windows(a.video, a.noise, 0.10)  # detect gaps >=100ms, filter later

    flags = []
    for w in words:
        s, e, t = w["start"], w["end"], w["text"]
        dur = e - s
        # MERGE: a real silence >= gap sits INSIDE this word's span
        inside = [(ss, se) for (ss, se) in sils
                  if se - ss >= a.gap and ss > s + 0.02 and se < e - 0.02]
        if inside:
            gaps = ", ".join(f"{ss:.2f}-{se:.2f}" for ss, se in inside)
            flags.append((s, e, t, "MERGE", f"{dur:.2f}s span, real silence(s) inside: {gaps}"))
            continue
        # LONG: suspiciously long for char count (CJK: 1 char ~= 1 syllable)
        nchars = len(re.sub(r"[^\w]", "", t)) or 1
        if dur / nchars > a.long and dur > 0.6:
            flags.append((s, e, t, "LONG", f"{dur:.2f}s for {nchars} char(s) = {dur/nchars:.2f}s/char"))

    print(f"words: {len(words)}  silence gaps>=100ms: {len(sils)}  flags: {len(flags)}\n")
    if not flags:
        print("No transcript/audio disagreements. First cut can trust the transcript timing.")
        return
    print(f"{'time':>16}  {'flag':6} {'word':10} detail")
    print("-" * 78)
    for s, e, t, kind, detail in flags:
        print(f"{s:7.2f}-{e:6.2f}  {kind:6} {t:10} {detail}")
    print("\n→ For each flagged region: generate a zoomed waveform view "
          "(timeline_view.py) and place cuts on the visible silence, NOT the word timing.")

if __name__ == "__main__":
    main()

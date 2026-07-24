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
  GAP     — a wide space BETWEEN two transcript words that is mostly NOT silence,
            i.e. there is audible speech the transcript has no word for. This is the
            classic Whisper blind spot: a half-said word / false start / repeat that
            Whisper swallowed. It never appears as a token, so nothing downstream sees
            it — only this cross-check against real audio does. Almost every "the cut
            keeps dropping the wrong syllable" case lives in a GAP region.

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
    ap.add_argument("--gap-span", type=float, default=0.30,
                    help="min space between two words to consider for a GAP flag (default 0.30s)")
    ap.add_argument("--gap-voice", type=float, default=0.20,
                    help="min non-silent (voiced) seconds inside that space to flag GAP (default 0.20s)")
    ap.add_argument("--gap-noise", default="-35",
                    help="silence threshold dB for GAP detection only — MORE sensitive than "
                         "--noise so a quietly-mumbled half word still reads as voiced, not "
                         "silence. -30 misses them. (default -35)")
    a = ap.parse_args()

    words = [w for w in json.load(open(a.transcript))["words"] if w.get("type") == "word"]
    sils = silence_windows(a.video, a.noise, 0.10)  # detect gaps >=100ms, filter later
    # Separate, more sensitive silence pass for GAP: a swallowed half-word is often
    # quiet enough that the -30dB pass calls it silence. MERGE/LONG keep the -30 pass.
    sils_gap = silence_windows(a.video, a.gap_noise, 0.05) if a.gap_noise != a.noise else sils

    def _overlap(s, e, windows):
        cov = 0.0
        for ss, se in windows:
            lo, hi = max(s, ss), min(e, se)
            if hi > lo:
                cov += hi - lo
        return cov

    flags = []
    # GAP: audible speech BETWEEN two transcript words with no word token for it.
    for w1, w2 in zip(words, words[1:]):
        gs, ge = w1["end"], w2["start"]
        span = ge - gs
        if span < a.gap_span:
            continue
        voiced = span - _overlap(gs, ge, sils_gap)
        if voiced >= a.gap_voice:
            flags.append((gs, ge, f"{w1['text']}⋯{w2['text']}", "GAP",
                          f"{span:.2f}s space, ~{voiced:.2f}s of it is voiced "
                          f"(sound with no word — likely a swallowed half/repeat)"))
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

    flags.sort(key=lambda f: f[0])
    ngap = sum(1 for f in flags if f[3] == "GAP")
    print(f"words: {len(words)}  silence gaps>=100ms: {len(sils)}  "
          f"flags: {len(flags)} ({ngap} GAP)\n")
    if not flags:
        print("No transcript/audio disagreements. First cut can trust the transcript timing.")
        return
    print(f"{'time':>16}  {'flag':6} {'word':12} detail")
    print("-" * 82)
    for s, e, t, kind, detail in flags:
        print(f"{s:7.2f}-{e:6.2f}  {kind:6} {t:12} {detail}")
    print("\n→ MERGE / LONG: generate a zoomed waveform (timeline_view.py) + split_blobs "
          "and place cuts on the visible silence, NOT the word timing.")
    print("→ GAP: there is speech here with no transcript word. Pull the waveform and "
          "split_blobs to see what it is. If you cannot tell what was said, ASK the user "
          "'X.X-X.X has sound but no word — what did you say here?' — do NOT cut around it "
          "blind. This is exactly where 'the cut keeps eating the wrong syllable' comes from.")

if __name__ == "__main__":
    main()

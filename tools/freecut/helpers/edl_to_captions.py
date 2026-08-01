#!/usr/bin/env python3
"""
edl_to_captions.py — map a word-level transcript through an EDL onto the output
timeline and group the surviving words into caption lines.

This replaces the ad-hoc remapping the AI used to rewrite every session. It does
the deterministic plumbing; the AI (or user) then only does the judgment work:
fixing mishears, adjusting breaks, picking highlight keywords.

What it does:
  1. Keeps only words whose start falls inside an EDL range (minus a 30ms edge
     guard that matches render.py's audio fades — boundary false-starts drop out)
  2. Maps each kept word to output-timeline seconds (monotonic; word ends are
     clamped to the next word's start so cuts can't create overlaps)
  3. Merges consecutive Latin fragments Whisper split ("any"+"ways" → "anyways")
  4. Applies an optional mishear-fix dictionary (see --fixes)
  5. Groups into caption lines: break on a real pause in the ORIGINAL audio
     (default >= 0.30s) or when a line reaches max display width; absorbs
     orphan fragments (<= 2 CJK chars) into the previous line

Output: captions.json — [{"start": s, "end": s, "text": "..."}, ...]
        Times are OUTPUT-timeline seconds, ready for data-start/data-duration.

The fixes file (--fixes) is a JSON object {"wrong": "right", ...}. Multi-token
errors are matched on the joined line text after grouping, single tokens at the
word level. Keep a per-user dictionary in 我的剪輯偏好.md and pass it here.

Usage:
  python3 edl_to_captions.py <transcript.json> <edl.json> [-o captions.json]
      [--fixes fixes.json] [--gap 0.30] [--max-width 26]

  --max-width counts CJK chars as 2, ASCII as 1 (26 ≈ 13 個中文字).

After every EDL change, RE-RUN this from scratch. Never arithmetic-shift old
caption times — that is exactly the bug this script exists to prevent.
"""
import argparse, json, re, sys
from pathlib import Path

EDGE_GUARD = 0.03   # matches render.py's 30ms audio fades

ASCII_RE = re.compile(r"[A-Za-z]+$")


def display_width(s):
    return sum(2 if ord(c) > 0x2E80 else 1 for c in s)


def load_words(transcript_path):
    data = json.loads(Path(transcript_path).read_text(encoding="utf-8"))
    words = data["words"] if isinstance(data, dict) else data
    out = []
    for w in words:
        t = (w.get("word", "") or w.get("text", "")).strip()
        if t:
            out.append({"text": t, "start": w["start"], "end": w["end"]})
    return out


def map_to_output(words, ranges):
    offsets, cum = [], 0.0
    for r in ranges:
        offsets.append(cum)
        cum += r["end"] - r["start"]

    # Whisper 字級時間普遍比實際發聲早 0.2-0.5 秒。舊判斷「w.start 落在 range 內」
    # 會把剪點邊界的字整個丟掉:聲音在、字幕沒字、零警告,下游(verify_cut)也看不出來
    # — 十份學員回報同一個坑。改成「字的區間與 range 有重疊就保留」:取重疊最大的
    # range,對映時間 clamp 進 range,跨過剪點起點的字印一行讓 AI 看得到。
    kept = []
    for w in words:
        best = None
        for r, off in zip(ranges, offsets):
            lo = max(w["start"], r["start"])
            hi = min(w["end"], r["end"] - EDGE_GUARD)
            ov = hi - lo
            if ov > 0 and (best is None or ov > best[0]):
                best = (ov, r, off, lo, hi)
        if best is None:
            continue
        ov, r, off, lo, hi = best
        if w["start"] < r["start"] - 0.001:
            print(f"  邊界字保留:「{w['text']}」start {w['start']:.2f} 早於剪點 "
                  f"{r['start']:.2f}(Whisper 時間偏早),已對齊剪點", file=sys.stderr)
        kept.append({
            "os": round(off + (lo - r["start"]), 3),
            "ov": round(ov, 3),
            "text": w["text"],
            "s": w["start"], "e": w["end"],
        })
    kept.sort(key=lambda k: k["os"])

    # monotonic clamp: a word may not extend past the next word's output start
    for i, k in enumerate(kept):
        natural = k["os"] + k.pop("ov")   # clamped span = audible portion in this range
        k["oe"] = min(natural, kept[i + 1]["os"]) if i + 1 < len(kept) else natural
    return kept


def merge_latin(kept, max_gap=0.12):
    merged = []
    for k in kept:
        if (merged and ASCII_RE.match(k["text"]) and ASCII_RE.match(merged[-1]["text"])
                and (k["s"] - merged[-1]["e"]) < max_gap):
            merged[-1]["text"] += k["text"]
            merged[-1]["e"] = k["e"]
            merged[-1]["oe"] = k["oe"]
        else:
            merged.append(dict(k))
    return merged


# 斷行偏好:語氣詞後面、連接詞前面,都是自然句界。
# 學員回報(七份):舊版只看寬度硬切,詞被切兩半(「拒/絕」)、跨句硬切,
# 幾乎每支片的字幕都要人工全部重排。寬度只當上限,句界優先。
BREAK_AFTER = set("了嗎吧呢啊喔嘛耶啦囉唷哦呀")
BREAK_BEFORE = ("但是", "但", "所以", "因為", "然後", "如果", "可是", "而且",
                "還有", "接下來", "結果", "其實", "後來")


def best_break(cur, max_width):
    """寬度到上限要斷行時,回頭在這行裡挑「最像句界」的位置,不要在講到一半硬切。
    評分 = 原始音訊的停頓長度 + 語氣詞/連接詞加成;位置至少要過 40% 寬,行不會太短。"""
    total, widths = 0, []
    for x in cur:
        total += display_width(x["text"])
        widths.append(total)
    best_i, best_score = None, 0.0
    for i in range(len(cur) - 1):
        if widths[i] < max_width * 0.4:
            continue
        gap = max(0.0, cur[i + 1]["s"] - cur[i]["e"])   # pause in ORIGINAL audio
        score = min(gap, 1.0)
        if cur[i]["text"] and cur[i]["text"][-1] in BREAK_AFTER:
            score += 0.25
        if any(cur[i + 1]["text"].startswith(p) for p in BREAK_BEFORE):
            score += 0.15
        if score >= best_score:   # 同分取後面的(行比較滿)
            best_i, best_score = i, score
    return best_i if best_score > 0.02 else None


def group_lines(words, gap_break, max_width):
    lines, cur = [], []
    for w in words:
        if cur:
            gap = w["s"] - cur[-1]["e"]          # pause in ORIGINAL audio
            width = sum(display_width(x["text"]) for x in cur)
            if width >= max_width * 0.6 and gap >= gap_break:
                lines.append(cur)
                cur = []
            elif width >= max_width:
                bi = best_break(cur, max_width)
                if bi is not None and bi < len(cur) - 1:
                    lines.append(cur[:bi + 1])
                    cur = cur[bi + 1:]
                else:
                    lines.append(cur)
                    cur = []
        cur.append(w)
    if cur:
        lines.append(cur)

    # absorb orphans (tiny fragments) into the previous line
    i = 1
    while i < len(lines):
        w = sum(display_width(x["text"]) for x in lines[i])
        close = (lines[i][0]["s"] - lines[i - 1][-1]["e"]) < 0.6
        if w <= 4 and close:
            lines[i - 1] += lines[i]
            del lines[i]
        else:
            i += 1
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    ap.add_argument("edl")
    ap.add_argument("-o", "--output", default="captions.json")
    ap.add_argument("--fixes", help="JSON dict of mishear fixes {wrong: right}")
    ap.add_argument("--gap", type=float, default=0.30,
                    help="original-audio pause (s) that allows a line break")
    ap.add_argument("--max-width", type=int, default=26,
                    help="max display width per line (CJK=2, ASCII=1)")
    args = ap.parse_args()

    ranges = json.loads(Path(args.edl).read_text(encoding="utf-8"))["ranges"]
    fixes = json.loads(Path(args.fixes).read_text(encoding="utf-8")) if args.fixes else {}

    words = merge_latin(map_to_output(load_words(args.transcript), ranges))

    # single-token fixes before grouping
    for w in words:
        w["text"] = fixes.get(w["text"], w["text"])

    lines = group_lines(words, args.gap, args.max_width)

    caps = []
    for ln in lines:
        text = "".join(x["text"] for x in ln)
        for wrong, right in fixes.items():      # multi-token fixes on joined text
            text = text.replace(wrong, right)
        caps.append({
            "start": round(ln[0]["os"], 2),
            "end": round(ln[-1]["oe"], 2),
            "text": text,
        })

    overlaps = [i for i in range(1, len(caps))
                if caps[i]["start"] < caps[i - 1]["end"] - 0.001]
    if overlaps:
        sys.exit(f"BUG: overlapping captions at indexes {overlaps} — report this")

    Path(args.output).write_text(
        json.dumps(caps, ensure_ascii=False, indent=1), encoding="utf-8")
    for i, c in enumerate(caps):
        print(f"{i:3} {c['start']:7.2f}-{c['end']:7.2f}  {c['text']}")
    print(f"\n{len(caps)} lines → {args.output}  (no overlaps)")


if __name__ == "__main__":
    main()

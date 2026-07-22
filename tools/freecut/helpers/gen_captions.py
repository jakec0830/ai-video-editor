"""gen_captions.py — turn a captions JSON into a lint-safe HyperFrames index.html.

Why this exists: writing the subtitle composition by hand re-discovers the same
traps every time (video needs data-start; subtitles need a high z-index or they
render BEHIND the video; each timed element needs class="clip" + data-* + a
unique id; the font needs an @font-face or it silently falls back to 黑體).
This generator bakes all of those in. The engineering that must not break is
fixed; the creative — phrasing, which words to highlight, and whatever effects /
sprites / b-roll you add — stays free.

Input: a captions JSON, a list of
    {"start": float, "end": float, "text": str, "hl": "substring"?}
`hl` is optional; that substring is painted yellow (colour only, same font).

The emitted index.html has clearly-marked CREATIVE LAYER / CREATIVE TIMELINE
slots. Add title cards, pixel sprites, b-roll cutaways, camera moves there, then
`npx hyperframes lint` (should pass clean) and render.

Usage:
    python helpers/gen_captions.py captions.json \
        --video preview_v7.mp4 --w 1080 --h 1920 --duration 84.63 \
        --font 宋體 -o index.html

Fonts (two presets — pick by 中文 name):
    宋體  → "Source Han Serif TC VF"  (襯線, 文青; 繁中一定要 TC)
    黑體  → "PingFang TC" weight 700   (無襯線, 短影音最常見)
"""

from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path

FONTS = {
    "宋體": {"family": "Source Han Serif TC VF", "weight": 600, "src": 'local("Source Han Serif TC VF")'},
    "黑體": {"family": "PingFang TC", "weight": 700, "src": 'local("PingFang TC")'},
}


def hl_html(text: str, hl: str | None) -> str:
    t = html.escape(text)
    if hl:
        h = html.escape(hl)
        if h in t:
            t = t.replace(h, f'<span class="kw">{h}</span>', 1)
    return t


def build(captions: list[dict], video: str, w: int, h: int,
          duration: float, font_key: str) -> str:
    f = FONTS[font_key]
    fam = f["family"]

    subs = []
    for i, c in enumerate(captions):
        dur = round(float(c["end"]) - float(c["start"]), 2)
        subs.append(
            f'      <div id="sub-{i}" class="clip sub" data-start="{c["start"]}" '
            f'data-duration="{dur}" data-track-index="5">'
            f'<span class="sub-inner">{hl_html(c["text"], c.get("hl"))}</span></div>'
        )
    subs_html = "\n".join(subs)

    return f'''<!doctype html>
<html lang="zh-Hant">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width={w}, height={h}" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
    <style>
      /* @font-face is REQUIRED even for a system font — the declaration alone
         stops the renderer falling back to a generic face. */
      @font-face {{ font-family:"{fam}"; src: {f["src"]}; }}
      * {{ margin:0; padding:0; box-sizing:border-box; }}
      html, body {{ width:{w}px; height:{h}px; overflow:hidden; background:#000; }}
      #root {{ position:absolute; inset:0; }}

      /* subtitles: white text on a black box. z-index MUST beat the a-roll
         (a-roll is z-index:1) or captions render behind the video and vanish. */
      .sub {{
        position:absolute; left:50%; bottom:230px; transform:translateX(-50%);
        width:auto; max-width:{int(w*0.86)}px; text-align:center; z-index:20;
        font-family:"{fam}",sans-serif; font-weight:{f["weight"]};
        font-size:56px; line-height:1.32; color:#fff; white-space:nowrap;
      }}
      .sub-inner {{
        display:inline-block; padding:10px 26px; border-radius:14px;
        background:rgba(0,0,0,0.72); box-shadow:0 4px 18px rgba(0,0,0,0.35);
        -webkit-box-decoration-break:clone; box-decoration-break:clone;
      }}
      .kw {{ color:#FFD400; }}   /* keyword highlight — colour only, never a different font */

      /* ==== CREATIVE LAYER styles: add your title-card / sprite / b-roll / callout CSS here ==== */

    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="{duration}"
         data-width="{w}" data-height="{h}">

      <!-- a-roll: data-start="0" is REQUIRED (untimed media diverges preview vs render) -->
      <video id="a-roll" class="clip" src="{video}" muted playsinline
             data-start="0" data-duration="{duration}" data-track-index="0"
             style="position:absolute; inset:0; width:100%; height:100%; object-fit:cover; z-index:1;"></video>
      <audio id="a-roll-audio" src="{video}" data-start="0" data-duration="{duration}"
             data-track-index="2" data-volume="1"></audio>

      <!-- ==== CREATIVE LAYER: title cards, pixel sprites, b-roll cutaways, callouts, montage ====
           Rules that keep lint + render happy:
             - every timed element: class="clip" + data-start + data-duration + data-track-index + a unique id
             - b-roll <video> is its OWN clip (never nested in a timed <div>); unique id; muted
             - overlays that must sit above the video need z-index > 1 (subtitles use 20; keep captions on top)
             - camera moves = GSAP transform on #a-roll (transform-origin ~ "50% 42%" for a centred face)
           Add elements here. -->

      <!-- subtitles -->
{subs_html}
    </div>

    <script>
      window.__timelines = window.__timelines || {{}};
      const tl = gsap.timeline({{ paused: true }});
      gsap.set("#a-roll", {{ transformOrigin: "50% 42%" }});

      /* ==== CREATIVE TIMELINE: add GSAP tweens at absolute output seconds ====
         Only deterministic animation (no Math.random / Date.now / infinite repeat).
         Examples:
           tl.to("#a-roll", {{ scale:1.12, duration:0.28 }}, 65.5);   // punch-in
           tl.to("#a-roll", {{ scale:1.0,  duration:0.5  }}, 67.1);
      */

      window.__timelines["main"] = tl;
    </script>
  </body>
</html>
'''


def main() -> None:
    ap = argparse.ArgumentParser(description="captions.json → lint-safe HyperFrames index.html")
    ap.add_argument("captions", type=Path, help="captions JSON: [{start,end,text,hl?}, ...]")
    ap.add_argument("--video", required=True, help="a-roll filename (relative to index.html)")
    ap.add_argument("--w", type=int, default=1080)
    ap.add_argument("--h", type=int, default=1920)
    ap.add_argument("--duration", type=float, required=True, help="ffprobe duration of the a-roll")
    ap.add_argument("--font", choices=list(FONTS), default="宋體")
    ap.add_argument("-o", "--out", type=Path, required=True)
    args = ap.parse_args()

    if not args.captions.exists():
        sys.exit(f"captions not found: {args.captions}")
    captions = json.loads(args.captions.read_text())
    if not isinstance(captions, list) or not captions:
        sys.exit("captions JSON must be a non-empty list of {start,end,text}")

    html_out = build(captions, args.video, args.w, args.h, args.duration, args.font)
    args.out.write_text(html_out, encoding="utf-8")
    print(f"wrote {args.out}  ({len(captions)} subtitles, font={args.font})")
    print("next: add creative layers in the marked slots → npx hyperframes lint → render")


if __name__ == "__main__":
    main()

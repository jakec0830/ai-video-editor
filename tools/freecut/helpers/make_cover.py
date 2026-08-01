#!/usr/bin/env python3
"""make_cover.py — 從成品抽一格 + 疊鉤子大字,產出社群封面圖(IG/Reels 用)。

為什麼需要:鉤子卡通常 data-start 不是 0,IG 縮圖抓第 0 格 → 封面一片空
(學員實測中招)。封面要自己做,不能指望第 0 格。

用法:
    python3 make_cover.py <影片> --title "鉤子第一行" [--line2 "第二行"] \
        [--time 秒數] [--font 宋體|黑體] [-o 封面.jpg]

    --time   抽哪一秒的畫面(預設 0.5;挑一格使用者本人表情好的)
    --title  封面大字(8 個中文字以內最好,太長自動縮小)

安全區:文字自動放在畫面高度 25%-75% 之間 — IG 九宮格裁切、Reels 上下 UI
都吃不到的區域。產完把圖丟進對話給使用者看,不滿意就換 --time 或改字。
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("需要 pillow(setup 有裝;venv 外跑的話:pip install pillow)")

FONT_CANDIDATES = {
    "宋體": [
        Path.home() / "Library/Fonts/SourceHanSerif-VF.otf.ttc",          # Mac
        Path.home() / "AppData/Local/Microsoft/Windows/Fonts/SourceHanSerifTC-Bold.otf",  # Win
        Path.home() / "AppData/Local/Microsoft/Windows/Fonts/SourceHanSerifTC-Heavy.otf",
    ],
    "黑體": [
        Path("/System/Library/Fonts/PingFang.ttc"),                        # Mac
        Path("C:/Windows/Fonts/msjh.ttc"),                                 # Win 正黑體
        Path("C:/Windows/Fonts/msjhbd.ttc"),
    ],
}


def find_font(name: str) -> Path:
    for p in FONT_CANDIDATES[name]:
        if p.exists():
            return p
    sys.exit(f"找不到{name}的字型檔(思源宋體沒裝?重跑 setup)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--title", required=True)
    ap.add_argument("--line2", default="")
    ap.add_argument("--time", type=float, default=0.5)
    ap.add_argument("--font", default="宋體", choices=list(FONT_CANDIDATES))
    ap.add_argument("-o", "--output", default="封面.jpg")
    args = ap.parse_args()

    font_path = find_font(args.font)

    with tempfile.TemporaryDirectory() as td:
        frame = Path(td) / "frame.png"
        r = subprocess.run(
            ["ffmpeg", "-y", "-hide_banner", "-ss", str(args.time),
             "-i", args.video, "-frames:v", "1", str(frame)],
            capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode != 0 or not frame.exists():
            sys.exit(f"抽影格失敗:{r.stderr.strip().splitlines()[-1] if r.stderr else '?'}")
        img = Image.open(frame).convert("RGB")

    W, H = img.size
    draw = ImageDraw.Draw(img, "RGBA")

    lines = [args.title] + ([args.line2] if args.line2 else [])
    # 字級:最長行塞進 86% 寬;太長的字自動縮小,最小不低於畫寬 1/18
    longest = max(len(ln) for ln in lines)
    size = max(W // 18, min(int(W * 0.86 / max(longest, 1)), W // 6))
    font = ImageFont.truetype(str(font_path), size=size)

    line_h = int(size * 1.25)
    block_h = line_h * len(lines)
    # 安全區:高度 25%-75%(IG 九宮格裁切 + Reels 上下 UI 都閃開),置中偏上
    y0 = max(int(H * 0.25), int(H * 0.40) - block_h // 2)
    if y0 + block_h > int(H * 0.75):
        y0 = int(H * 0.75) - block_h

    # 文字底下壓一層半透明漸暗,亮背景也讀得清
    pad = int(size * 0.6)
    draw.rectangle([0, y0 - pad, W, y0 + block_h + pad], fill=(0, 0, 0, 110))

    stroke = max(2, size // 14)
    for i, ln in enumerate(lines):
        tw = draw.textlength(ln, font=font)
        draw.text(((W - tw) // 2, y0 + i * line_h), ln, font=font,
                  fill=(255, 255, 255), stroke_width=stroke, stroke_fill=(0, 0, 0))

    img.save(args.output, quality=92)
    print(f"[OK] 封面 → {args.output}({W}x{H},文字在 y {y0}-{y0+block_h},安全區內)")
    print("     丟進對話給使用者看;要換畫面改 --time,要換字改 --title。")


if __name__ == "__main__":
    main()

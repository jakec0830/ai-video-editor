#!/usr/bin/env python3
"""make_cover.py — 從影片抽一格 + 疊封面標題,產出社群封面圖(IG/Reels 用)。

為什麼需要:鉤子卡通常 data-start 不是 0,IG 縮圖抓第 0 格 → 封面一片空
(學員實測中招)。封面要自己做,不能指望第 0 格。

版型(2026-11-17 Jake 定:舊版「灰底條 + 白字」被說「太醜」,換成婉芬-03 過關的這款):
    上方膠囊(選配,步驟/系列)→ 大字(黃色 3D,放品牌名或關鍵字)→ 第二行白色粗字(問句)
    文字那一側壓一層梅紫漸層,亮背景也讀得清。問號自動染黃。

用法:
    python3 make_cover.py <影片> --title "天麗" --line2 "到底要怎麼擦？" \
        [--chips "敷完推開,眼周,6A 防曬"] [--time 秒數] [--font 黑體|宋體] \
        [--pos top|middle|bottom] [-o 封面.png]

    --title  大字(1-4 個字最好看,例:品牌名、關鍵字;太長自動縮小)
    --line2  第二行(問句/鉤子,9 個字以內)
    --chips  上方小膠囊,逗號分開(步驟、集數、系列名);不給就不畫
    --time   抽哪一秒的畫面(預設 0.5;挑一格本人表情好的,有產品就挑拿著產品那格)
    --pos    文字放哪(預設 top:臉通常在畫面中間,頭上方最安全)
    --font   預設黑體(粗黑);要文青感用宋體(思源宋體 Heavy)
    <影片>   用還沒燒字幕的 工作檔/preview_vN.mp4,不然封面會帶到一句不相干的字幕。

安全區:文字都在 IG 九宮格 4:5 裁切線裡面(直式約 y 15%-85%),Reels 上下 UI 也閃開。
產完把圖丟進對話給使用者看,不滿意就換 --time 或改字。
"""
from __future__ import annotations

import argparse
import glob
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("需要 pillow(setup 有裝;venv 外跑的話:pip install pillow)")

HOME = Path.home()
SERIF_VF = [HOME / "Library/Fonts/SourceHanSerif-VF.otf.ttc"]   # setup 一定會裝;index 3 = TC,可調到 Heavy

# (路徑 or glob, 字型裡要的名字)— 依序找,找到第一個能用的
HEAVY_SANS = [
    ("/System/Library/AssetsV2/com_apple_MobileAsset_Font*/*/AssetData/Lantinghei.ttc", ("Lantinghei TC", "Heavy")),
    ("/System/Library/AssetsV2/com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc", ("PingFang TC", "Semibold")),
    ("/System/Library/Fonts/PingFang.ttc", ("PingFang TC", "Semibold")),
    ("C:/Windows/Fonts/msjhbd.ttc", None),                       # Windows 微軟正黑體 粗
    ("/System/Library/Fonts/STHeiti Medium.ttc", None),
]
SERIF_FILES = [HOME / "AppData/Local/Microsoft/Windows/Fonts/SourceHanSerifTC-Heavy.otf",
               HOME / "AppData/Local/Microsoft/Windows/Fonts/SourceHanSerifTC-Bold.otf",
               HOME / "Library/Fonts/SourceHanSerifTC-Bold.otf"]

YELLOW = (255, 212, 0)
YELLOW_DEPTH = [(217, 168, 0), (201, 151, 0), (184, 138, 0), (148, 111, 0), (112, 84, 0)]
PLUM = (34, 14, 30)


def _ttc_face(path: str, want) -> int | None:
    for i in range(24):
        try:
            name = ImageFont.truetype(path, 20, index=i).getname()
        except Exception:
            return None
        if want is None or name == want:
            return i
    return None


def _serif_heavy(size: int):
    for p in SERIF_VF:
        if p.exists():
            f = ImageFont.truetype(str(p), size, index=3)
            try:
                f.set_variation_by_name("Heavy")
            except Exception:
                pass
            return f
    for p in SERIF_FILES:
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return None


def load_font(name: str, size: int):
    if name == "黑體":
        for pat, want in HEAVY_SANS:
            for p in sorted(glob.glob(pat)):
                idx = _ttc_face(p, want)
                if idx is not None:
                    return ImageFont.truetype(p, size, index=idx)
    f = _serif_heavy(size)          # 宋體,或找不到黑體時退回思源宋體 Heavy(至少是粗的)
    if f is None:
        sys.exit("找不到可用的粗中文字型(思源宋體沒裝?重跑 setup)")
    return f


def text_w(draw, s, font):
    return draw.textlength(s, font=font)


def shadow_layer(size, draw_fn, blur):
    lay = Image.new("RGBA", size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(lay))
    return lay.filter(ImageFilter.GaussianBlur(blur))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--title", required=True)
    ap.add_argument("--line2", default="")
    ap.add_argument("--chips", default="")
    ap.add_argument("--time", type=float, default=0.5)
    ap.add_argument("--font", default="黑體", choices=["黑體", "宋體"])
    ap.add_argument("--pos", default="top", choices=["top", "middle", "bottom"])
    ap.add_argument("-o", "--output", default="封面.png")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as td:
        frame = Path(td) / "frame.png"
        r = subprocess.run(
            ["ffmpeg", "-y", "-hide_banner", "-ss", str(args.time),
             "-i", args.video, "-frames:v", "1", str(frame)],
            capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode != 0 or not frame.exists():
            sys.exit(f"抽影格失敗:{r.stderr.strip().splitlines()[-1] if r.stderr else '?'}")
        img = Image.open(frame).convert("RGBA")

    W, H = img.size
    u = W / 1080                                     # 所有尺寸以 1080 寬為基準
    probe = ImageDraw.Draw(img)

    # ---- 字級:大字 1-2 字 250px,字多就縮到塞得進 88% 寬 ----
    def fit(text, base, minimum):
        size = int(base * u)
        while size > minimum * u:
            if text_w(probe, text, load_font(args.font, size)) <= W * 0.88:
                break
            size -= 6
        return load_font(args.font, size), size

    f1, s1 = fit(args.title, 250, 90)
    f2, s2 = fit(args.line2, 128, 60) if args.line2 else (None, 0)
    chips = [c.strip() for c in args.chips.split(",") if c.strip()]
    fc = load_font(args.font, int(40 * u))

    chip_h = int(64 * u) if chips else 0
    gap1 = int(26 * u) if chips else 0
    depth = int(15 * u)
    gap2 = int(34 * u)
    block_h = chip_h + gap1 + s1 + depth + (gap2 + s2 if args.line2 else 0)

    # ---- 位置:九宮格 4:5 裁切線內 ----
    crop_top = max(int((H - W * 1.25) / 2), int(H * 0.08))
    crop_bot = H - crop_top
    pad = int(30 * u)
    if args.pos == "top":
        y0 = crop_top + pad
    elif args.pos == "bottom":
        y0 = crop_bot - pad - block_h
    else:
        y0 = (H - block_h) // 2

    # ---- 梅紫漸層壓暗文字那一側 ----
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    if args.pos == "top":
        solid, fade = y0 + block_h, y0 + block_h + int(H * 0.12)
        for y in range(0, fade):
            a = 225 if y < solid * 0.6 else int(225 * max(0, (fade - y) / (fade - solid * 0.6)))
            gd.line([(0, y), (W, y)], fill=PLUM + (a,))
    elif args.pos == "bottom":
        start = y0 - int(H * 0.12)
        for y in range(max(0, start), H):
            a = int(225 * min(1, (y - start) / (int(H * 0.12) + block_h * 0.4)))
            gd.line([(0, y), (W, y)], fill=PLUM + (a,))
    else:
        top, bot = y0 - int(H * 0.08), y0 + block_h + int(H * 0.08)
        mid = (top + bot) / 2
        for y in range(max(0, top), min(H, bot)):
            a = int(200 * (1 - abs(y - mid) / ((bot - top) / 2)) ** 0.6)
            gd.line([(0, y), (W, y)], fill=PLUM + (a,))
    img = Image.alpha_composite(img, grad)
    d = ImageDraw.Draw(img)

    y = y0
    # ---- 膠囊 ----
    if chips:
        arrow_w = int(40 * u)
        widths = [int(text_w(d, c, fc) + 52 * u) for c in chips]
        total = sum(widths) + arrow_w * (len(chips) - 1)
        x = (W - total) // 2
        # 半透明要畫在另一層再疊上去(直接畫在 RGBA 上是「取代」不是「混合」,會變成實心白)
        pills = Image.new("RGBA", img.size, (0, 0, 0, 0))
        pd = ImageDraw.Draw(pills)
        xx = x
        for w in widths:
            pd.rounded_rectangle([xx, y, xx + w, y + chip_h], radius=chip_h // 2,
                                 fill=(255, 255, 255, 36), outline=(255, 255, 255, 110), width=max(2, int(2 * u)))
            xx += w + arrow_w
        img = Image.alpha_composite(img, pills)
        d = ImageDraw.Draw(img)
        for i, (c, w) in enumerate(zip(chips, widths)):
            d.text((x + w / 2, y + chip_h / 2), c, font=fc, fill=(255, 255, 255), anchor="mm")
            x += w
            if i < len(chips) - 1:
                cx, cy, r = x + arrow_w / 2, y + chip_h / 2, 9 * u   # 自己畫三角形:粗黑字型常沒有「›」這個字
                d.polygon([(cx - r * 0.6, cy - r), (cx + r * 0.8, cy), (cx - r * 0.6, cy + r)], fill=YELLOW)
                x += arrow_w
        y += chip_h + gap1

    # ---- 大字:黃色 3D(往下疊 5 層深色 + 模糊陰影)----
    tw = text_w(d, args.title, f1)
    x1 = (W - tw) / 2
    img = Image.alpha_composite(img, shadow_layer(img.size, lambda g: g.text(
        (x1, y + depth + int(10 * u)), args.title, font=f1, fill=(0, 0, 0, 170)), int(18 * u)))
    d = ImageDraw.Draw(img)
    for k, col in reversed(list(enumerate(YELLOW_DEPTH, start=1))):
        d.text((x1, y + k * depth / len(YELLOW_DEPTH)), args.title, font=f1, fill=col)
    d.text((x1, y), args.title, font=f1, fill=YELLOW)
    y += s1 + depth + gap2

    # ---- 第二行:白色粗字 + 梅紫硬陰影;問號染黃 ----
    if args.line2:
        body, tail = args.line2, ""
        if body[-1:] in "？?!！":
            body, tail = body[:-1], body[-1]
        full_w = text_w(d, body + tail, f2)
        x2 = (W - full_w) / 2
        img = Image.alpha_composite(img, shadow_layer(img.size, lambda g: g.text(
            (x2, y + int(10 * u)), body + tail, font=f2, fill=(0, 0, 0, 160)), int(16 * u)))
        d = ImageDraw.Draw(img)
        d.text((x2, y + int(5 * u)), body + tail, font=f2, fill=(58, 31, 51))
        d.text((x2, y), body, font=f2, fill=(255, 255, 255))
        if tail:
            d.text((x2 + text_w(d, body, f2), y), tail, font=f2, fill=YELLOW)

    out = Path(args.output)
    if out.suffix.lower() in (".jpg", ".jpeg"):
        img.convert("RGB").save(out, quality=93)
    else:
        img.convert("RGB").save(out)
    print(f"[OK] 封面 → {out}({W}x{H},文字在 y {y0}-{y0 + block_h},九宮格 4:5 裁切線 {crop_top}-{crop_bot} 內)")
    print("     丟進對話給使用者看;換畫面改 --time(有產品挑拿著產品那格),蓋到臉改 --pos。")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""eyes_mask.py — 把影片裡某個人的眼睛打馬賽克(選配:使用者要求才做,不是預設)。

為什麼有這支(婉芬-03,2026-11-18):示範保養的影片要遮客人的眼睛。Apple Vision 只抓得到
58% 的格(側臉、被手擋、在畫面邊緣就抓不到),剩下的要人工標。第一次用整張小縮圖標,
位置差了 70-140px;改用「臉附近放大的格線小圖」才標準 —— gaps 子指令就是做這個的。

只能在 Mac 跑(用 Apple Vision 找臉,要有 swiftc = Xcode 命令列工具)。

流程(對「還沒加特效的 preview」做,不要對成品做):
  1. detect  <video>                          逐格找臉 → <video>.faces.jsonl
  2. gaps    <video> --who right -o <資料夾>    列出抓不到那個人的時段 + 產放大格線圖給你標
       看圖把每張小圖裡眼睛的位置(小圖座標 0-240)照順序寫進 readings.txt(一行「lx ly」,
       看不到眼睛/人不在畫面就寫「-」),再:
     kp      <資料夾>/crops.txt readings.txt -o kp.txt    換算成畫面座標
  3. apply   <in> <out> --who right [--manual kp.txt] [--debug]
       --debug 畫紅框不打碼,先拿來看框對不對
  4. check   <out> -o <資料夾> [--crop x,y,w,h]   每秒一格拼成檢查圖,逐張看眼睛有沒有蓋到

--who:right = 畫面右邊那個人(取最右邊的臉),left = 左邊那個人,all = 每張偵測到的臉都打
      (all 不能補人工點,偵測不到的格就不會打 —— 一定要 check)。
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
CACHE = Path.home() / ".cache" / "ai-edit"


# ---------- 共用 ----------
def probe(video: str):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets",
                          "-show_entries", "stream=width,height,r_frame_rate,nb_read_packets",
                          "-of", "json", video], capture_output=True, text=True, check=True).stdout
    s = json.loads(out)["streams"][0]
    num, den = s["r_frame_rate"].split("/")
    return int(s["width"]), int(s["height"]), float(num) / float(den), int(s["nb_read_packets"])


def faces_path(video: str) -> Path:
    return Path(str(video) + ".faces.jsonl")


def load_faces(video: str):
    p = faces_path(video)
    if not p.exists():
        sys.exit(f"✗ 找不到 {p.name},先跑:eyes_mask.py detect {video}")
    return [json.loads(l) for l in p.read_text().splitlines() if l.strip()]


def eye_of(f):
    pts = f["le"] + f["re"]
    if not pts:
        return None
    a = np.array(pts)
    return a[:, 0].mean(), a[:, 1].mean(), max(np.ptp(a[:, 0]), f["box"][2] * 0.45)


def pick(frame, who: str, W: int):
    """回傳這一格要打碼的眼睛 [(cx, cy, span), ...]"""
    fs = [f for f in frame["faces"] if f["le"] or f["re"]]
    cen = lambda f: f["box"][0] + f["box"][2] / 2
    if who == "all":
        return [e for e in map(eye_of, fs) if e]
    if who == "right":
        fs = [f for f in fs if cen(f) > W * 0.59]
        fs = [max(fs, key=cen)] if fs else []
    else:
        fs = [f for f in fs if cen(f) < W * 0.41]
        fs = [min(fs, key=cen)] if fs else []
    return [e for e in map(eye_of, fs) if e]


# ---------- detect ----------
def cmd_detect(a):
    if platform.system() != "Darwin":
        sys.exit("✗ 只能在 Mac 跑(用的是 Apple Vision 找臉)。")
    if not shutil.which("swiftc"):
        sys.exit("✗ 找不到 swiftc。要先裝 Xcode 命令列工具(Mac 會跳視窗,點安裝),或改成全部人工標。")
    src, binp = HERE / "faces.swift", CACHE / "faces"
    if not binp.exists() or binp.stat().st_mtime < src.stat().st_mtime:
        CACHE.mkdir(parents=True, exist_ok=True)
        print("編譯找臉工具(只有第一次)…")
        r = subprocess.run(["swiftc", "-O", str(src), "-o", str(binp)], capture_output=True, text=True)
        if r.returncode:
            sys.exit("✗ 編譯失敗:\n" + r.stderr[-1500:])
    out = faces_path(a.video)
    with open(out, "w") as fh:
        r = subprocess.run([str(binp), a.video], stdout=fh, stderr=subprocess.DEVNULL)
    if r.returncode:
        sys.exit("✗ 找臉失敗(影片讀不到?)")
    L = load_faces(a.video)
    W, H, fps, n = probe(a.video)
    for who in ("right", "left"):
        hit = sum(1 for x in L if pick(x, who, W))
        print(f"  {who:5s}:{hit}/{len(L)} 格抓得到({hit * 100 // max(len(L), 1)}%)")
    print(f"[OK] {out}")


# ---------- gaps ----------
def spans_missing(L, who, W, min_len=0.4):
    out, s = [], None
    for i, x in enumerate(L):
        miss = not pick(x, who, W)
        if miss and s is None:
            s = i
        if not miss and s is not None:
            out.append((L[s]["t"], L[i]["t"])); s = None
    if s is not None:
        out.append((L[s]["t"], L[-1]["t"]))
    return [(a, b) for a, b in out if b - a > min_len]


def cmd_gaps(a):
    if a.who == "all":
        sys.exit("✗ --who all 不能補人工點;gaps 只支援 right / left。")
    L = load_faces(a.video)
    W, H, fps, n = probe(a.video)
    sp = spans_missing(L, a.who, W)
    det = [(x["t"], pick(x, a.who, W)[0]) for x in L if pick(x, a.who, W)]
    print(f"抓不到 {a.who} 那個人超過 0.4 秒的時段 {len(sp)} 段,共 {sum(b - a for a, b in sp):.1f} 秒:")
    for s, e in sp:
        print(f"  {s:7.2f} – {e:7.2f}  ({e - s:.2f}s)")
    if not sp:
        return
    outd = Path(a.out); outd.mkdir(parents=True, exist_ok=True)
    for old in outd.glob("crop_*.png"):
        old.unlink()
    # 每張裁 C x 1.6C(直的),縮成 240x384 小圖。2 秒內有偵測到 → C=480(小圖 1px = 原畫面 2px,夠準);
    # 附近都沒偵測(長時段)→ 裁大、放那一側、上下涵蓋大半個畫面,免得臉在框外(婉芬-03 開頭 21 秒就是這樣)
    rows = []
    for s, e in sp:
        t = max(0.0, s - 0.1)
        while t <= e + 0.1:
            near = min(det, key=lambda d: abs(d[0] - t)) if det else None
            if near and abs(near[0] - t) <= 2:
                C, gx, gy = 480, near[1][0], near[1][1]
            else:
                C = int(min(W * 0.6, H * 0.6 / 1.6))
                gx, gy = (W - C / 2 if a.who == "right" else C / 2), H * 0.5
            C = int(min(C, W, H / 1.6)); CH = int(C * 1.6)
            X = int(min(max(gx - C / 2, 0), W - C)); Y = int(min(max(gy - CH / 2, 0), H - CH))
            rows.append((round(t, 2), X, Y, C))
            t += 0.5
    for i, (t, X, Y, C) in enumerate(rows):
        g = int(C / 8)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(t), "-i", a.video, "-frames:v", "1", "-vf",
                        f"crop={C}:{int(C * 1.6)}:{X}:{Y},drawgrid=w={g}:h={g}:t=1:c=yellow@0.6,scale=240:384,"
                        f"pad=246:390:3:3:black", str(outd / f"crop_{i:03d}.png")], check=True)
    (outd / "crops.txt").write_text("".join(f"{t} {X} {Y} {C}\n" for t, X, Y, C in rows))
    nsheet = (len(rows) + 15) // 16
    for s in range(nsheet):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-start_number", str(s * 16), "-i", str(outd / "crop_%03d.png"),
                        "-vf", "tile=8x2:color=black", "-frames:v", "1", "-update", "1",
                        str(outd / f"sheet_{s}.png")], check=True)
    print(f"\n[OK] {len(rows)} 張放大圖拼成 {nsheet} 張 {outd}/sheet_N.png(每張 8x2,由左到右、上到下)")
    print("  每張小圖的格子都是正方形(橫 8 格)。看每張小圖裡眼睛在哪(小圖座標 x 0-240、y 0-384,扣掉 3px 黑邊),")
    print("  照順序一行寫「lx ly」進 readings.txt,看不到就寫「-」;再跑:")
    print(f"  eyes_mask.py kp {outd}/crops.txt readings.txt -o kp.txt")


def cmd_kp(a):
    crops = [l.split() for l in Path(a.crops).read_text().splitlines() if l.strip()]
    reads = [l.split() for l in Path(a.readings).read_text().splitlines() if l.strip()]
    if len(crops) != len(reads):
        sys.exit(f"✗ crops.txt 有 {len(crops)} 行,readings 有 {len(reads)} 行,要一樣多(看不到寫「-」)")
    out = []
    for row, r in zip(crops, reads):
        t, X, Y = row[:3]; k = (int(row[3]) if len(row) > 3 else 480) / 240   # 小圖 1px = 原畫面 k px
        if r[0] == "-":
            continue
        out.append(f"{t} {int(X) + k * float(r[0]):.0f} {int(Y) + k * float(r[1]):.0f}\n")
    Path(a.out).write_text("".join(out))
    print(f"[OK] {a.out}({len(out)} 個人工點)")


# ---------- apply ----------
def smooth(v, k):
    pad = np.pad(v, (k // 2, k // 2), mode="edge")
    return np.convolve(pad, np.ones(k) / k, mode="valid")


def cmd_apply(a):
    L = load_faces(a.input)
    W, H, fps, n = probe(a.input)
    u = W / 1080
    k = max(3, int(round(fps * 0.23)) | 1)        # 30fps → 7 格平滑
    boxes = [[] for _ in range(n)]                 # 每格要打碼的框 (x0,y0,x1,y1)
    def box(cx, cy, s, minw):
        bw = max(s * 2.2, minw * u); bh = max(bw * 0.62, 150 * u)
        return (int(cx - bw / 2), int(cy - bh / 2), int(cx + bw / 2), int(cy + bh / 2))

    if a.who == "all":
        for x in L:
            f = int(round(x["t"] * fps))
            for g in range(f - 3, f + 4):          # 前後各撐 3 格,偶爾漏抓不會閃
                if 0 <= g < n:
                    boxes[g] += [box(cx, cy, s, 230) for cx, cy, s in pick(x, "all", W)]
        manual_n = 0
    else:
        det = {}
        for x in L:
            e = pick(x, a.who, W)
            if e:
                det[int(round(x["t"] * fps))] = e[0]
        keys = dict(det)
        if a.manual:
            for l in Path(a.manual).read_text().splitlines():
                if not l.strip():
                    continue
                t, mx, my = map(float, l.split()[:3])
                f = int(round(t * fps))
                if not any(abs(f - d) <= 3 for d in det):
                    keys[f] = (mx, my, 200 * u)
        if not keys:
            sys.exit("✗ 這個人一格都沒抓到,也沒有人工點;先跑 gaps 標位置")
        ks = sorted(keys); arr = np.array([keys[q] for q in ks]); fr = np.arange(n)
        cx, cy, sp = (smooth(np.interp(fr, ks, arr[:, j]), k) for j in range(3))
        dk = np.array(sorted(det)) if det else np.array([-10 ** 9])
        manual = np.array([np.min(np.abs(dk - f)) > 3 for f in fr])
        manual_n = int(manual.sum())
        for f in range(n):
            boxes[f].append(box(cx[f], cy[f], sp[f], 300 if manual[f] else 230))

    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", a.input, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                           stdout=subprocess.PIPE)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                            "-r", f"{fps}", "-i", "-", "-i", a.input, "-map", "0:v", "-map", "1:a?", "-c:v", "libx264",
                            "-crf", "16", "-preset", "fast", "-pix_fmt", "yuv420p", "-c:a", "copy", "-shortest", a.output],
                           stdin=subprocess.PIPE)
    B = max(8, int(22 * u)); T = max(3, int(6 * u)); i = 0
    while True:
        buf = dec.stdout.read(W * H * 3)
        if len(buf) < W * H * 3:
            break
        img = np.frombuffer(buf, np.uint8).reshape(H, W, 3).copy()
        for x0, y0, x1, y1 in boxes[min(i, n - 1)]:
            x0, y0, x1, y1 = max(0, x0), max(0, y0), min(W, x1), min(H, y1)
            if x1 - x0 < 4 or y1 - y0 < 4:
                continue
            if a.debug:
                img[y0:y0 + T, x0:x1] = img[y1 - T:y1, x0:x1] = (255, 0, 0)
                img[y0:y1, x0:x0 + T] = img[y0:y1, x1 - T:x1] = (255, 0, 0)
                continue
            reg = img[y0:y1, x0:x1].astype(np.float32); h, w = reg.shape[:2]
            gh, gw = -(-h // B), -(-w // B)
            p = np.pad(reg, ((0, gh * B - h), (0, gw * B - w), (0, 0)), mode="edge")
            blk = p.reshape(gh, B, gw, B, 3).mean(axis=(1, 3))
            img[y0:y1, x0:x1] = np.repeat(np.repeat(blk, B, 0), B, 1)[:h, :w].astype(np.uint8)
        enc.stdin.write(img.tobytes()); i += 1
    enc.stdin.close(); enc.wait(); dec.wait()
    if enc.returncode:
        sys.exit("✗ 輸出影片失敗")
    print(f"[OK] {a.output}({i} 格;偵測 {n - manual_n} 格、人工點內插 {manual_n} 格)")
    print("  接著一定要跑 check 看圖,不要只看這行就說全部蓋到了。")


# ---------- check ----------
def cmd_check(a):
    W, H, fps, n = probe(a.video)
    outd = Path(a.out); outd.mkdir(parents=True, exist_ok=True)
    for old in list(outd.glob("chk_*.png")) + list(outd.glob("check_*.png")):
        old.unlink()
    crop = a.crop or f"{W}:{H}:0:0"
    if a.crop:
        x, y, w, h = a.crop.split(","); crop = f"{w}:{h}:{x}:{y}"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a.video, "-vf",
                    f"fps=1,crop={crop},scale=200:-2,pad=204:ih+4:2:2:black", str(outd / "chk_%03d.png")], check=True)
    m = len(list(outd.glob("chk_*.png")))
    for s in range((m + 19) // 20):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-start_number", str(s * 20 + 1), "-i", str(outd / "chk_%03d.png"),
                        "-vf", "tile=10x2:color=black", "-frames:v", "1", "-update", "1",
                        str(outd / f"check_{s}.png")], check=True)
    for p in outd.glob("chk_*.png"):
        p.unlink()
    print(f"[OK] {m} 秒拼成 {(m + 19) // 20} 張 {outd}/check_N.png(第 N 張 = 第 N*20 秒起,每張 20 秒)")
    print("  每張都要看;側臉、被手擋的地方再單獨放大確認。回報時講清楚怎麼檢查的,不要說「每一格都蓋到」。")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("detect"); p.add_argument("video"); p.set_defaults(fn=cmd_detect)
    p = sub.add_parser("gaps"); p.add_argument("video"); p.add_argument("--who", choices=["right", "left", "all"], required=True)
    p.add_argument("-o", "--out", required=True); p.set_defaults(fn=cmd_gaps)
    p = sub.add_parser("kp"); p.add_argument("crops"); p.add_argument("readings"); p.add_argument("-o", "--out", required=True)
    p.set_defaults(fn=cmd_kp)
    p = sub.add_parser("apply"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--who", choices=["right", "left", "all"], required=True)
    p.add_argument("--manual"); p.add_argument("--debug", action="store_true"); p.set_defaults(fn=cmd_apply)
    p = sub.add_parser("check"); p.add_argument("video"); p.add_argument("-o", "--out", required=True)
    p.add_argument("--crop", help="x,y,w,h 只看這塊(例:右半邊 440,560,640,900)"); p.set_defaults(fn=cmd_check)
    a = ap.parse_args(); a.fn(a)


if __name__ == "__main__":
    main()

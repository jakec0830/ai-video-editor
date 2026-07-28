#!/usr/bin/env python3
"""
sound_map.py — 印出某個區間「實際有哪些聲音、各在第幾秒」的時間表。

為什麼需要這支:**特效要對某個聲音(彈指、拍手、敲桌、笑聲)時,時間點不能用
逐字稿或 EDL 推算出來。** 實測踩過:算出來的彈指位置 14.19,實際量是 14.45
(差 0.26 秒,使用者一聽就說「太快」);同一段的字幕也偏了 0.5 秒。逐字稿的
字級時間在「合併過的剪接段落」裡特別不準,而且它根本不記錄非語音的聲音。

跟 split_blobs.py 的差別:
  split_blobs  用 ffmpeg silencedetect 切區塊,回答「這裡有幾段聲音」。
  sound_map    自己算 10ms 的音量包絡,多回答「每段多大聲」,並且會把
               **短促又孤立的爆音**(彈指/拍手這種 0.05-0.2 秒的聲音)標出來 —
               那種聲音用預設門檻掃常常整個看不到,正是「音效沒對上」的兇手。

也可以拿來對字幕:講話段落之間的低谷就是句子邊界,比逐字稿的字級時間可靠。

用法:
    python3 sound_map.py <影片/音檔> <start> <end> [--floor auto|-38] [--rel]

    <start> <end>   要看的區間(秒)。可以是原始影片,也可以是 render 完的輸出檔。
    --floor         音量門檻 dB。auto(預設)= 這段自己的底噪 + --offset。
    --offset        auto 門檻要比底噪高幾 dB(預設 8)。抓不到小聲的就調小。
    --rel           另外印出「相對於 start 的秒數」— 拿小樣給使用者聽時用這個對位。
"""
import argparse
import array
import subprocess
import sys

SR = 8000          # 8kHz 單聲道就夠找聲音邊界了,而且很快(10 秒 = 8 萬個取樣點)
WIN = 0.010        # 10ms 一格


def pcm(path: str, start: float, end: float) -> array.array:
    """把指定區間解成 8kHz 單聲道 16-bit PCM。

    -ss/-t 放在 -i **後面**(輸出端 seek)= 取樣級精準;放前面是快速 seek,會落在
    keyframe 上。-vn 不解影像,所以就算從頭 demux,4K 素材也很快。

    ★ 量音量請一律走這條原始 PCM 的路,不要用 `ffmpeg -af volumedetect` 去量
    某個小區間 — 實測 `-i x -ss 14.2 -t 0.7 -af volumedetect` report 出 143 萬個
    取樣點(約 15 秒),也就是它**根本沒有只量那 0.7 秒**,量出來的數字是錯的。
    """
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-vn",
           "-ss", f"{start}", "-t", f"{end - start}",
           "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"]
    out = subprocess.run(cmd, capture_output=True).stdout
    a = array.array("h")
    a.frombytes(out[: len(out) // 2 * 2])
    return a


def envelope(samples: array.array) -> list[float]:
    """每 10ms 一格的峰值,換成 dBFS。"""
    n = int(SR * WIN)
    out = []
    for i in range(0, len(samples) - n + 1, n):
        peak = 0
        for v in samples[i:i + n]:
            if v < 0:
                v = -v
            if v > peak:
                peak = v
        out.append(20 * __import__("math").log10(peak / 32768) if peak else -120.0)
    return out


def find_transients(env, floor_db, spike_db, max_len, t0, segs, margin=0.08):
    """找「彈指/拍手/敲桌」這種爆音。

    ★ 不能用絕對音量門檻找。實測:成品經過響度正規化後房間底噪高到 -20dB,
    彈指峰值 -9.1dB,而語音是 -3dB — 用絕對門檻的話,彈指跟語音分不開,
    彈指還會因為只有 10-30ms 被 --min-sound 直接濾掉(第一版就是這樣整個抓不到)。

    爆音真正的特徵是「**又短、又是局部突起**」:
      1. 比「附近 ±0.3 秒的背景中位數」高 spike_db 以上
      2. 那個背景本身很安靜(接近底噪)— 否則是講話講到一半的爆破音
      3. 突起持續很短 — 語音起音會連續響 100ms 以上,彈指只有 1-3 格
      4. ★ 落在「語音段落之間的安靜」裡,不在任何語音段落內。中文每個字的起音
         在 10ms 解析度下跟彈指長得幾乎一樣(實測光靠 1-3 條件會把每個字頭都報成
         爆音),真正分得開的是「它出現在照理該安靜的地方」。
    """
    import statistics
    n, half = len(env), int(0.30 / WIN)
    pad = int(margin / WIN)
    in_speech = [False] * n
    for s0, s1 in segs:
        for k in range(max(0, s0 - pad), min(n, s1 + pad)):
            in_speech[k] = True
    out, i = [], 0
    while i < n:
        if in_speech[i]:
            i += 1
            continue
        near = env[max(0, i - half):i + half + 1]
        base = statistics.median(near)
        if env[i] - base >= spike_db and base <= floor_db + 6:
            j = i
            while j + 1 < n and env[j + 1] >= env[i] - 6:
                j += 1
            if (j - i + 1) * WIN <= max_len:          # 夠短才是爆音,不是語音起音
                out.append((t0 + i * WIN, env[i] - base, env[i]))
                i = j + int(0.10 / WIN)               # 同一個爆音不重複報
                continue
        i += 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("media")
    ap.add_argument("start", type=float)
    ap.add_argument("end", type=float)
    ap.add_argument("--floor", default="auto",
                    help="音量門檻 dB;auto(預設)= 這段底噪 + --offset")
    ap.add_argument("--offset", type=float, default=8.0,
                    help="auto 門檻比底噪高幾 dB(預設 8)")
    ap.add_argument("--min-sound", type=float, default=0.04,
                    help="短於這個秒數的聲音不列(預設 0.04s)")
    ap.add_argument("--min-gap", type=float, default=0.06,
                    help="短於這個秒數的安靜不算斷開(預設 0.06s)")
    ap.add_argument("--transient", type=float, default=0.05,
                    help="爆音的突起最長幾秒(預設 0.05)。這條就是把彈指跟「語音起音」"
                         "分開的關鍵:彈指 1-3 格(10-30ms)就掉回背景,講話的爆破音會"
                         "連續響 100ms 以上。放寬到 0.1 以上會開始把每個字的開頭都當爆音。")
    ap.add_argument("--spike", type=float, default=8.0,
                    help="爆音判定:比「附近的背景」高這麼多 dB 才算(預設 8)。"
                         "抓不到就調小,雜訊太多就調大。")
    ap.add_argument("--rel", action="store_true", help="加印相對於 start 的秒數")
    a = ap.parse_args()

    if a.end <= a.start:
        print("[X] end 要大於 start")
        return 1
    samples = pcm(a.media, a.start, a.end)
    if not samples:
        print(f"[X] 讀不到音訊:{a.media}")
        return 1
    env = envelope(samples)
    if not env:
        print("[X] 區間太短")
        return 1

    quiet = sorted(env)
    floor_db = quiet[max(0, int(len(quiet) * 0.10) - 1)]      # 第 10 百分位 = 底噪
    thr = floor_db + a.offset if a.floor == "auto" else float(a.floor)

    # 依門檻切出聲音段落
    loud = [v > thr for v in env]
    segs, i, n = [], 0, len(loud)
    while i < n:
        if not loud[i]:
            i += 1
            continue
        j = i
        while j < n and loud[j]:
            j += 1
        segs.append([i, j])
        i = j
    # 合併中間太短的安靜
    merged = []
    for s in segs:
        if merged and (s[0] - merged[-1][1]) * WIN < a.min_gap:
            merged[-1][1] = s[1]
        else:
            merged.append(s)
    segs = [s for s in merged if (s[1] - s[0]) * WIN >= a.min_sound]

    print(f"區間 {a.start:.2f}-{a.end:.2f}({a.end - a.start:.2f}s) · "
          f"底噪 {floor_db:.1f}dB · 門檻 {thr:.1f}dB · {len(segs)} 段聲音\n")
    if not segs:
        print("這段沒有超過門檻的聲音(整段安靜)。門檻太嚴的話調 --offset 小一點。")
        return 0

    hdr = f"{'#':>3}  {'開始':>8} {'結束':>8} {'長度':>7} {'峰值':>9}"
    if a.rel:
        hdr += f"  {'小樣內':>8}"
    print(hdr + "   判讀")
    print("-" * (len(hdr) + 30))

    marks = find_transients(env, floor_db, a.spike, a.transient, a.start, segs)

    for k, (i0, i1) in enumerate(segs, 1):
        s = a.start + i0 * WIN
        e = a.start + i1 * WIN
        dur = e - s
        peak = max(env[i0:i1])
        note = "語音"
        row = f"{k:>3}  {s:8.2f} {e:8.2f} {dur:6.2f}s {peak:8.1f}dB"
        if a.rel:
            row += f"  {s - a.start:7.2f}s"
        print(row + f"   {note}")

    gaps = []
    for x, y in zip(segs, segs[1:]):
        g0, g1 = a.start + x[1] * WIN, a.start + y[0] * WIN
        if g1 - g0 >= 0.15:
            gaps.append(f"{g0:.2f}-{g1:.2f}({g1 - g0:.2f}s)")
    if gaps:
        print("\n安靜區間(句子邊界多半落在這些地方):")
        print("  " + " · ".join(gaps))
    if marks:
        print(f"\n★ 爆音(彈指/拍手/敲擊之類 — 特效跟音效要對的多半是這個):")
        for s, rise, peak in marks:
            rel = f"  小樣內 {s - a.start:.2f}s" if a.rel else ""
            print(f"    {s:.2f}s   峰值 {peak:.1f}dB,比附近背景高 {rise:.1f}dB{rel}")
        print("  → 直接用這個秒數,不要用逐字稿或 EDL 推算(實測會差 0.2-0.3 秒)。")
    else:
        print("\n(沒找到爆音。抓不到就把 --spike 調小,例如 --spike 6)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

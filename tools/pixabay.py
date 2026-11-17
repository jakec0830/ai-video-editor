#!/usr/bin/env python3
"""
pixabay.py — 從 Pixabay 找素材(圖片/影片),先「看過再挑」,不是盲抽一張。

為什麼要這支:HeyGen 素材庫一次只回一個結果、看不到還有什麼、也沒有去背篩選、
授權條款也不清楚。Pixabay 三個都解決了:
  - `colors=transparent` 可以只找去背 PNG
  - Pixabay Content License:商用免費、免標註
  - 每張都有 pageURL / 作者,來源可追

★ 找去背素材的正確搜法:`--transparent --type photo`
    只加 --transparent 的話,結果會偏成**卡通/向量圖**(捲軸、笑臉、卡通狗)——
    因為照片本來就很少帶 alpha,「有去背」這個條件本身就篩掉了大部分照片。
    加上 --type photo 才會拿到「真的照片去背」的撕邊紙、破洞、便條紙。
    背景紋理類不用去背,直接 --type photo 不要加 --transparent。

用法(兩步:先看,再挑):
    # 1. 搜尋 → 會產一張縮圖總覽 + 編號清單
    python3 tools/pixabay.py search "torn paper" --transparent -n 20

    # 2. 看完挑編號 → 下載進素材庫(會一起記來源)
    python3 tools/pixabay.py get 3 --name 撕邊紙-A --dir 素材庫/圖片/collage

    # 影片素材
    python3 tools/pixabay.py search "paper texture" --video -n 12

API key 怎麼設(★ 不要貼在聊天視窗給 AI):
    自己在終端機跑一次:
        mkdir -p ~/.config/pixabay && nano ~/.config/pixabay/key
    把 key 貼進去存檔即可。或設環境變數 PIXABAY_API_KEY。
    key 在 https://pixabay.com/api/docs/ 登入後看得到。

Pixabay 規定(這支已經照做):
  - 回應必須快取 24 小時 → 存在 ~/.cache/pixabay/
  - 不可以 hotlink → 一律下載到本機才用
  - 顯示搜尋結果時要標明來源 → 清單跟 contact sheet 都會印 Pixabay + 作者
"""
import argparse, hashlib, json, os, pathlib, subprocess, sys, time
import urllib.parse, urllib.request

API_IMG = "https://pixabay.com/api/"
API_VID = "https://pixabay.com/api/videos/"
CACHE = pathlib.Path.home() / ".cache" / "pixabay"
CACHE_TTL = 24 * 3600          # Pixabay 要求:快取 24 小時
STATE = CACHE / "_last_search.json"


def api_key() -> str:
    k = os.environ.get("PIXABAY_API_KEY", "").strip()
    if k:
        return k
    f = pathlib.Path.home() / ".config" / "pixabay" / "key"
    if f.exists():
        k = f.read_text(encoding="utf-8").strip()
        if k:
            return k
    sys.exit(
        "找不到 Pixabay API key。\n"
        "  自己在終端機跑(不要把 key 貼給 AI):\n"
        "    mkdir -p ~/.config/pixabay && nano ~/.config/pixabay/key\n"
        "  或 export PIXABAY_API_KEY=...\n"
        "  key 在 https://pixabay.com/api/docs/ 登入後可看到。"
    )


def fetch(url: str, params: dict) -> dict:
    """帶 24 小時快取的 GET(Pixabay ToS 要求快取)。快取檔名不含 key。"""
    CACHE.mkdir(parents=True, exist_ok=True)
    safe = {k: v for k, v in params.items() if k != "key"}
    tag = hashlib.sha256(
        (url + json.dumps(safe, sort_keys=True)).encode()).hexdigest()[:20]
    cf = CACHE / f"{tag}.json"
    if cf.exists() and (time.time() - cf.stat().st_mtime) < CACHE_TTL:
        return json.loads(cf.read_text(encoding="utf-8"))
    full = url + "?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(full, timeout=30) as r:
            body = r.read().decode("utf-8")
            rem = r.headers.get("X-RateLimit-Remaining")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:200]
        sys.exit(f"Pixabay API 錯誤 {e.code}: {detail}\n"
                 f"(429 = 超過每分鐘 100 次上限,等一下再試)")
    cf.write_text(body, encoding="utf-8")
    if rem is not None:
        print(f"  (這分鐘還可以問 {rem} 次)")
    return json.loads(body)


def download(url: str, dest: pathlib.Path) -> pathlib.Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "ai-video-editor/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as f:
        f.write(r.read())
    return dest


def cmd_search(a):
    key = api_key()
    is_vid = a.video
    params = {"key": key, "q": a.query[:100], "per_page": max(3, min(a.number, 200)),
              "safesearch": "true", "order": a.order}
    if not is_vid:
        params["image_type"] = a.type
        if a.transparent:
            params["colors"] = "transparent"
        if a.min_width:
            params["min_width"] = a.min_width
    if a.category:
        params["category"] = a.category

    data = fetch(API_VID if is_vid else API_IMG, params)
    hits = data.get("hits", [])
    if not hits:
        print(f"「{a.query}」沒有結果。"
              + ("(去背素材本來就比較少,可以拿掉 --transparent 再試)" if a.transparent else ""))
        return
    print(f'\n「{a.query}」共 {data.get("totalHits", 0)} 筆可取,顯示前 {len(hits)} 筆')
    print("來源:Pixabay(Pixabay Content License,商用免費、免標註)\n")

    tmp = CACHE / "thumbs"
    if tmp.exists():
        for p in tmp.glob("*"):
            p.unlink()
    tmp.mkdir(parents=True, exist_ok=True)

    rows, tiles = [], []
    for i, h in enumerate(hits, 1):
        if is_vid:
            v = h["videos"].get("small") or h["videos"].get("tiny")
            thumb, w, hh = v["thumbnail"], v["width"], v["height"]
            size = f'{w}x{hh} {h.get("duration","?")}s'
        else:
            thumb = h["previewURL"]
            size = f'{h.get("imageWidth")}x{h.get("imageHeight")}'
        rows.append((i, h["id"], size, h.get("user", "?"), h.get("tags", "")[:44]))
        try:
            p = tmp / f"{i:02d}.jpg"
            download(thumb, p)
            tiles.append(p)
        except Exception:
            pass

    print(f'{"#":<4}{"pixabay id":<12}{"尺寸":<18}{"作者":<18}標籤')
    print("-" * 96)
    for r in rows:
        print(f"{r[0]:<4}{r[1]:<12}{r[2]:<18}{r[3]:<18}{r[4]}")

    STATE.write_text(json.dumps(
        {"query": a.query, "video": is_vid, "hits": hits}, ensure_ascii=False),
        encoding="utf-8")

    if tiles:
        sheet = CACHE / "contact-sheet.png"
        cols = 5
        # 有些 ffmpeg 沒編進 drawtext(要 libfreetype),沒有就不畫編號,不要整張掛掉
        has_dt = subprocess.run(["ffmpeg", "-hide_banner", "-filters"],
                                capture_output=True, text=True
                                ).stdout.find(" drawtext ") >= 0
        # ★ 去背圖一定要「疊在灰底上」,不能只用 pad ——
        #   pad 只加外框,圖裡面的透明區會變成純黑,根本看不出哪裡是去背的。
        def tile(i):
            s = (f"color=c=0x8A8A8A:s=270x270[bg{i}];"
                 f"[{i}]scale=260:260:force_original_aspect_ratio=decrease,"
                 f"format=rgba[fg{i}];"
                 f"[bg{i}][fg{i}]overlay=(W-w)/2:(H-h)/2")
            if has_dt:
                s += (f",drawtext=text='{i+1}':x=8:y=6:fontsize=30:fontcolor=yellow"
                      f":box=1:boxcolor=black@0.75:boxborderw=5")
            return s + f"[t{i}]"
        pad = [tile(i) for i in range(len(tiles))]
        # ★ 最後一排如果不滿 cols 張,要 pad 到同寬 —— vstack 要求每一排寬度一樣,
        #   不 pad 的話張數不是 cols 的倍數時(例如 12 張分 5/5/2)整張會產不出來。
        rowspec, n = [], len(tiles)
        for s in range(0, n, cols):
            grp = [f"[t{j}]" for j in range(s, min(s + cols, n))]
            spec = "".join(grp) + f"hstack=inputs={len(grp)}"
            if len(grp) < cols:
                spec += f",pad={cols*270}:270:0:0:color=0x8A8A8A"
            rowspec.append(spec + f"[r{s//cols}]")
        stack = "".join(f"[r{i}]" for i in range(len(rowspec)))
        fc = ";".join(pad + rowspec)
        if len(rowspec) > 1:
            fc += f";{stack}vstack=inputs={len(rowspec)}"
        cmd = ["ffmpeg", "-v", "error"]
        for p in tiles:
            cmd += ["-i", str(p)]
        cmd += ["-filter_complex", fc, "-frames:v", "1", "-update", "1", "-y", str(sheet)]
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            print(f"\n縮圖總覽 → {sheet}")
            if not has_dt:
                print(f"  (你的 ffmpeg 沒有 drawtext,圖上沒有編號 —"
                      f" 順序是左到右、上到下,每排 {cols} 張,對照上面的清單)")
        else:
            print("\n(縮圖總覽產生失敗,清單還是可以用)")
    print(f'\n挑好之後:python3 tools/pixabay.py get <#> --name <檔名> --dir <資料夾>')


def cmd_get(a):
    if not STATE.exists():
        sys.exit("還沒搜尋過。先跑 search。")
    st = json.loads(STATE.read_text(encoding="utf-8"))
    hits = st["hits"]
    if not (1 <= a.index <= len(hits)):
        sys.exit(f"編號要在 1..{len(hits)}")
    h = hits[a.index - 1]
    out = pathlib.Path(a.dir)
    name = a.name or f'pixabay-{h["id"]}'

    if st["video"]:
        v = h["videos"].get("large") or h["videos"].get("medium") or h["videos"]["small"]
        url, ext = v["url"], ".mp4"
        detail = f'{v["width"]}x{v["height"]}'
    else:
        # imageURL / fullHDURL 要「full API access」核准才有,一般帳號用 largeImageURL(<=1280px)
        url = h.get("imageURL") or h.get("fullHDURL") or h["largeImageURL"]
        cap = "原圖" if h.get("imageURL") else ("FullHD" if h.get("fullHDURL") else "1280px")
        ext = ".png" if ".png" in url.lower() else ".jpg"
        detail = f'{h.get("imageWidth")}x{h.get("imageHeight")} (實際下載:{cap})'

    dest = out / f"{name}{ext}"
    download(url, dest)
    print(f"已下載 → {dest}  ({detail})")

    # 來源一定要記下來(HeyGen 那邊就是因為沒有這個,事後查不到授權)
    log = out / "來源.md"
    if not log.exists():
        log.write_text("# 素材來源\n\n來自 Pixabay,授權:Pixabay Content License"
                       "(商用免費、免標註)。\n", encoding="utf-8")
    with open(log, "a", encoding="utf-8") as f:
        f.write(f'\n## {dest.name}\n'
                f'- Pixabay id: {h["id"]}\n'
                f'- 來源頁: {h["pageURL"]}\n'
                f'- 作者: {h.get("user","?")}\n'
                f'- 搜尋詞: {st["query"]}\n'
                f'- 標籤: {h.get("tags","")}\n'
                f'- 下載日期: {time.strftime("%Y-%m-%d")}\n')
    print(f"來源已記錄 → {log}")


def main():
    ap = argparse.ArgumentParser(
        description="從 Pixabay 找素材 — 先看縮圖總覽再挑",
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("search", help="搜尋並產生縮圖總覽")
    s.add_argument("query")
    s.add_argument("-n", "--number", type=int, default=20, help="幾筆(3-200,預設 20)")
    s.add_argument("--transparent", action="store_true", help="只找去背 PNG")
    s.add_argument("--type", default="all", choices=["all", "photo", "illustration", "vector"])
    s.add_argument("--category", default=None)
    s.add_argument("--min-width", type=int, default=0)
    s.add_argument("--order", default="popular", choices=["popular", "latest"])
    s.add_argument("--video", action="store_true", help="找影片不是圖片")
    s.set_defaults(func=cmd_search)

    g = sub.add_parser("get", help="下載剛才搜尋結果裡的第 N 筆")
    g.add_argument("index", type=int)
    g.add_argument("--name", default=None, help="存成什麼檔名(不用副檔名)")
    g.add_argument("--dir", default="素材庫/圖片", help="存到哪個資料夾")
    g.set_defaults(func=cmd_get)

    a = ap.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""產生「開始審片.html」— 免拖檔的審片頁。

把 KIT/審片.html 複製一份到專案的 審片區/,並把影片檔名 + 字幕 JSON 內嵌進去。
使用者雙擊 審片區/開始審片.html 就直接開審,不用再拖兩個檔案。
每輪出新 preview 後重跑一次(直接覆蓋舊的)。

用法:
    python3 make_review_page.py <審片區資料夾> <影片檔名> [字幕.json路徑]

    <影片檔名>   審片區裡那支影片的「檔名」(相對路徑,不是完整路徑)
    [字幕路徑]   預設用 <審片區>/字幕.json
"""
import json
import sys
from pathlib import Path

MARKER_START = "<!-- __審片AUTO__"
MARKER_END = "-->"


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    review_dir = Path(sys.argv[1])
    video_name = sys.argv[2]
    subs_path = Path(sys.argv[3]) if len(sys.argv) > 3 else review_dir / "字幕.json"

    kit = Path(__file__).resolve().parents[3]   # helpers/ → freecut/ → tools/ → KIT
    template = kit / "審片.html"
    if not template.exists():
        print(f"[X] 找不到 {template}")
        return 1
    if not (review_dir / video_name).exists():
        print(f"[X] 審片區裡沒有 {video_name} — 先把影片複製進去再產生這頁")
        return 1

    html = template.read_text(encoding="utf-8")
    start = html.find(MARKER_START)
    if start < 0:
        print("[X] 審片.html 裡找不到 __審片AUTO__ 標記(舊版?先更新工具包)")
        return 1
    end = html.index(MARKER_END, start) + len(MARKER_END)

    subs_txt = "null"
    if subs_path.exists():
        # 先 parse 再 dump:確認是合法 JSON,也把內容壓成一行安全內嵌
        subs_txt = json.dumps(json.loads(subs_path.read_text(encoding="utf-8")),
                              ensure_ascii=False)
    inject = ("<script>window.__審片AUTO = "
              + json.dumps({"video": video_name}, ensure_ascii=False)[:-1]
              + f', "subs": {subs_txt}}};</script>')

    out = review_dir / "開始審片.html"
    out.write_text(html[:start] + inject + html[end:], encoding="utf-8")
    n = "?" if subs_txt == "null" else len(json.loads(subs_txt))
    print(f"[OK] 產生 {out}(影片 {video_name},字幕 {n} 句)— 雙擊即審,免拖檔")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

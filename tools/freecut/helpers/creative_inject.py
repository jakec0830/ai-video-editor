#!/usr/bin/env python3
"""creative_inject.py — creative.py 把特效層塞進 base.tpl、寫出 index.html 的共用函式。

為什麼要它(婉芬-03 2026-11-17 實測):creative.py 在 Python 裡定義時間點(D0 = 21.44),
JS 裡也寫了 shrinkIn(D0),但 JS 根本沒有 D0 → 瀏覽器一載入就 "D0 is not defined",
整條特效時間軸沒跑,**所有特效、推鏡、連字幕隱藏都不見**。lint 0 error、snapshot 也照拍
(只是拍到沒特效的畫面),只有 `hyperframes check` 的 runtime 會報 page_error。

用法(creative.py 裡):
    from creative_inject import write_index
    T = {"D0": 21.44, "D1": 27.02}            # Python 跟 JS 共用的時間點,只寫這一次
    write_index("base.tpl", "index.html", css=CSS, html=HTML, js=JS, consts=T,
                root_duration=106.616)          # root_duration 選填:片尾要比影片長時用
JS 裡直接用 D0、D1(自動在最前面宣告成 const)。

它會:
  1. 把 consts 宣告成 JS const,放在特效 JS 最前面
  2. 掃 JS 裡「全大寫的名字」(D0、VID_END…),沒宣告、也不是 JS 內建的 → 直接報錯停下
  3. 注入 CSS / HTML / JS 三個插槽,寫出 index.html
寫完照樣要跑 `npx hyperframes check`(runtime 那段看有沒有 page_error),再 snapshot。
"""
from __future__ import annotations

import re
import sys

SLOT_CSS = "      /* ==== CREATIVE LAYER styles: add your title-card / sprite / b-roll / callout CSS here ==== */"
SLOT_HTML = "      <!-- subtitles -->"
SLOT_JS = '      window.__timelines["main"] = tl;'

JS_BUILTIN = {"AR", "NaN", "JSON", "Math", "PI", "E", "SVG", "DOM", "URL", "API", "HTML", "CSS", "RGB", "ID"}


def _undeclared(js: str, consts: dict) -> list[str]:
    code = re.sub(r"//[^\n]*", "", js)
    code = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`', '""', code)   # 字串內的字不算
    used = set(re.findall(r"(?<![\w.$#-])([A-Z][A-Z0-9_]*)(?![\w$])", code))
    declared = set(consts)
    for stmt in re.findall(r"\b(?:const|let|var)\s+([^;\n]+)", code):      # const A = 1, B = 2 → A、B 都算
        declared |= set(re.findall(r"([A-Z][A-Z0-9_]*)\s*=(?!=)", stmt))
    for params in re.findall(r"\(([^)]*)\)\s*=>", code):                 # 箭頭函式參數 (A, B) => 也算宣告
        declared |= set(re.findall(r"[A-Z][A-Z0-9_]*", params))
    return sorted(n for n in used - declared - JS_BUILTIN if len(n) > 1)


def write_index(base_path: str, out_path: str, *, css: str = "", html: str = "", js: str = "",
                consts: dict | None = None, root_duration: float | None = None) -> str:
    consts = consts or {}
    missing = _undeclared(js, consts)
    if missing:
        sys.exit(f"✗ 特效 JS 用到沒宣告的名字:{', '.join(missing)}\n"
                 f"  → 把它們加進 write_index(consts={{...}}),或在 JS 裡 const 宣告。"
                 f"(沒宣告的話整條特效時間軸不會跑,畫面上什麼特效都沒有)")
    s = open(base_path, encoding="utf-8").read()
    for slot in (SLOT_CSS, SLOT_HTML, SLOT_JS):
        if slot not in s:
            sys.exit(f"✗ {base_path} 找不到插槽:{slot.strip()}(是不是拿已經注入過的 index.html 當底稿?要用 gen_captions 產的 base.tpl)")
    if root_duration is not None:
        s, n = re.subn(r'(data-composition-id="main"[^>]*?data-duration=")[\d.]+(")', rf"\g<1>{root_duration}\g<2>", s, count=1)
        if not n:
            sys.exit("✗ 找不到 root 的 data-duration,沒辦法改片長")
    decl = "".join(f"      const {k} = {v!r};\n" for k, v in consts.items())
    s = s.replace(SLOT_CSS, "      /* ==== CREATIVE LAYER styles ==== */" + css)
    s = s.replace(SLOT_HTML, html + "\n\n" + SLOT_HTML)
    s = s.replace(SLOT_JS, decl + js + "\n" + SLOT_JS)
    open(out_path, "w", encoding="utf-8").write(s)
    print(f"wrote {out_path}(宣告了 {len(consts)} 個共用時間點)— 接著跑 npx hyperframes check,runtime 不能有 page_error")
    return s

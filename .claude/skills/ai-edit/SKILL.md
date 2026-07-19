---
name: ai-edit
description: 用對話幫使用者從頭到尾剪一支口播影片 — 本機轉逐字稿、剪掉 NG 跟停頓、上繁體中文字幕、加特效音效背景音樂,最後輸出成品 MP4。當使用者丟進口播原始影片說要剪片時使用。涵蓋完整流程(本機 Whisper 剪接層 + HyperFrames 字幕特效層),包含避免 Whisper 時間軸出錯的驗證工具。也管理使用者的素材庫跟剪輯偏好。
---

# ai-edit — AI 剪輯流程

這份給 AI 讀。任何有終端機 + 檔案工具的 coding agent(Claude Code、Codex、Cursor)都能照著做。指令是純 shell,程式碼、路徑、技術名詞保留原文,說明用繁體中文。

**所有路徑相對於「工具包根目錄」**(有 `setup.sh`、`tools/`、`素材庫/`、`我的影片/` 的那層,以下叫 `KIT`)。深入技術參考見 `KIT/PIPELINE-NOTES.md`。

**適用範圍:** 這個流程是給「口播影片」的(有人對著鏡頭講話)。剪接靠語音逐字稿,所以沒有講話的素材(純空景配樂那種)這個流程剪不了。底層的 HyperFrames 其實能做更多類型(產品片、解說片、動態圖文等),想延伸的話用 `npx hyperframes` 直接做 — 但那不走這個技能。

「問使用者」= 用你的介面能問就問;完全自動跑的話,選合理預設並在結尾說明。

---

## 開場:檢查更新 + 讀偏好檔(學習循環的起點)

每次開始前做兩件事:

1. **檢查有沒有新版本**(只有當 `KIT/.git` 存在,也就是用 git clone 下載的才做)。跑 `git -C KIT fetch --quiet`,再看 `git -C KIT rev-list HEAD..@{u} --count`。結果 > 0 代表 Jake 出了新版 → 問使用者「有新版本,幫你更新嗎?」,說好就跑 `bash KIT/update.sh`(等同 `git -C KIT pull`)。使用者的影片、素材、偏好都不會被動到(那些沒進 git)。如果不是 git 資料夾(ZIP 下載的),**跳過這步,不要報錯**。
2. **讀 `KIT/我的剪輯偏好.md`**。裡面是這位使用者過去累積的習慣(字幕風格、愛用音樂、剪接節奏等)。照著走,不要每次重問已經講過的偏好。收尾時你會更新它(見文末)。若這個檔不存在(第一次跑),從 `KIT/我的剪輯偏好.範本.md` 複製一份(`setup.sh` 會自動做)。

---

## 第一次設定 — 帶著使用者一步一步裝,不要只列清單

使用者說「幫我安裝」「幫我設定」或這是第一次跑時,主動一個一個幫他把缺的東西裝好。不要丟一份清單就走。學員是新手。

1. 在 KIT 根目錄跑 `bash setup.sh`,讀它的輸出。它會自動建好 Python 環境 + whisper 引擎,並把每個外部工具標成 `[OK]`、`[!]`、`[X]`。
2. 每個 `[X]`(缺)或 `[!]`(要處理)的,互動式處理:
   - 判斷平台(`uname -s` / `uname -m`),挑對的安裝指令。
   - **先用一句話說你要裝什麼、為什麼**,再跑。Claude Code 可能會跳權限確認,正常。
   - 每裝完一個,再跑一次 `setup.sh` 確認變成 `[OK]` 再繼續。
3. 常見安裝(依平台):
   - ffmpeg — Mac `brew install ffmpeg` · Windows `choco install ffmpeg`(要系統管理員 PowerShell)· Linux `sudo apt install ffmpeg`
   - Node >= 22 — Mac `brew install node` · 其他到 nodejs.org 下載安裝
   - Homebrew(Mac,若沒 `brew`)— 官方 `curl ... install.sh | bash`;**會要輸入電腦密碼,這步交給使用者,你打不了密碼**
   - 思源宋體 — Mac `brew install --cask font-source-han-serif-vf` · 其他到 github.com/adobe-fonts/source-han-serif 下載,使用者自己雙擊安裝
   - heygen(選配)— `curl -fsSL https://static.heygen.ai/cli/install.sh | bash` 再 `heygen auth login --oauth`(**會開瀏覽器登入他自己的帳號,交給使用者**)

**這些你做不到,交回給使用者:** 任何要密碼／sudo／系統管理員權限的、任何瀏覽器 OAuth 登入的、任何要點視窗的圖形安裝(尤其 Windows 上的 Node／字型)。清楚說「這步換你做:要做什麼、為什麼」,等他做完再繼續。Windows 沒 bash 的話 `setup.sh` 跑不了,改照 README 的「手動安裝」一條一條帶。

**底線:** Claude Code 本身的安裝跟登入是在這個技能能跑之前就完成的(不然使用者沒辦法跟你講話)。永遠不要嘗試從這裡安裝 Claude Code。

**轉逐字稿是跨平台的。** `transcribe.py` 會自動判斷:Apple Silicon 用 `mlx-whisper`(最快),其他(Windows／Intel／Linux,CPU 或 NVIDIA)用 `faster-whisper`。同樣的模型、同樣會有重複字出錯的問題,所以下面的 xref／波形驗證步驟兩邊都一樣重要。

設定好之後,下面簡寫:`PY="$KIT/tools/freecut/.venv/bin/python3"`、`H="$KIT/tools/freecut/helpers"`。

---

## 資料夾結構與清理 — 幫新手保持整齊

**一支影片一個資料夾**,放在 `KIT/我的影片/` 底下。使用者開始時,建好這個結構並用一句話跟他說明:

```
KIT/我的影片/<專案名>/
  <原始影片檔>        原檔,絕不動它
  成品.mp4            完成的影片 — 他要的就這一個
  工作檔/             其他全部丟這:逐字稿、edl.json、preview_v*、字幕專案、擷取的畫面、下載的音檔
```

紀律(照做,他的硬碟才不會爆):
- 每個中間檔都放 `工作檔/` 底下。絕不把 preview、render、擷取的 PNG、試聽的音檔散在最上層或旁邊的資料夾。
- 舊的 preview 邊做邊刪 — 有了 `preview_v2` 就刪掉 `preview_v1`。只留最新的 preview + `edl.json`。
- 擷取的畫面 PNG、試聽下載的音檔是用完即丟:看完馬上刪。
- **一次工作結束時,主動問要不要清理:**「要不要幫你清一下工作檔?我會留下你的原始影片跟成品.mp4,清掉 工作檔/(大約 X MB)。」顯示大小,等他說好。**絕不刪原始影片或成品.mp4。**
- 使用者說「清理」「太亂了」時,跑 `bash cleanup.sh <專案資料夾>`(安全 — 會先顯示要刪什麼並要你確認,而且只動 `工作檔/`)。

---

## 素材庫與 b-roll — 建議循環

`KIT/素材庫/` 是跨專案共用的可重複素材:`背景音樂/`、`音效/`、`b-roll/`、`圖片/`。詳見 `KIT/素材庫/說明.md`。

- 剪片要用音樂／音效／圖片／b-roll 時,**先看素材庫有沒有現成的**,有就直接用,不要重新下載。
- 使用者這次帶進來或下載了新的音樂／音效／圖片/b-roll,用完後**主動問**:「要不要把這個存進素材庫,下次可以重複用?」說要就幫他放進對的子資料夾。
- **b-roll**(補充畫面)放 `素材庫/b-roll/`:空景、產品特寫、示範操作畫面,任何口播中間想切過去的畫面。剪片時遇到適合插 b-roll 的段落(例如講到某個具體東西),**主動提醒**:「這裡可以插一段畫面,你素材庫裡有沒有相關的?或想拍一段?」這是**建議**,放哪、放不放由使用者決定,不要自動塞。實際怎麼合成見流程「5.5 插 b-roll(選配)」。

---

## 剪輯流程

在 `<專案>/工作檔/` 裡作業(就是下面的 `--edit-dir`)。最後成品輸出到 `<專案>/成品.mp4`。

### 1. 轉逐字稿 + 交叉比對(剪之前先做)

```bash
$PY $H/transcribe.py <影片> --backend whisper --language zh --edit-dir <專案>/工作檔
$PY $H/xref_silence.py <影片> <專案>/工作檔/transcripts/<名稱>.json
```

每個 MERGE 標記,跑 `$PY $H/split_blobs.py <影片> <start> <end>`,在剪之前把真正的語音區塊show給使用者看。MERGE 區是 Whisper 出錯的地方(重複字被併成一個 token、贅字被吃進字的時間裡)。絕不在被標記的區域裡只憑逐字稿時間做細剪。

### 2. 結構剪接(第一輪 — 依逐字稿)

先用白話提案:哪個 take 留、哪些 NG／重拍刪、哪些停頓修短。**句間留白不要整支固定同一個值** — 短影音從約 250ms 起跳,要衝節奏就收到 150ms,關鍵句／轉折前放到 400ms 以上讓它喘一口。太緊(130ms 以下)會很躁,太鬆(400ms+ 全程)會拖。等使用者確認,再寫 `工作檔/edl.json`:

```json
{"version":1,"sources":{"NAME":"/abs/path.MOV"},
 "ranges":[{"source":"NAME","start":1.53,"end":7.54,"beat":"HOOK","quote":"...","reason":"..."}],
 "grade":"none","overlays":[],"subtitles":null,"total_duration_s":0}
```

range 的時間全部用**原始影片的秒數**。輸出:`$PY $H/render.py 工作檔/edl.json -o 工作檔/preview_v1.mp4 --preview --no-subtitles`

### 3. 細剪(第二輪 — 使用者主導,用波形當真相)

使用者用耳朵聽 preview。任何要修的地方:
- 跑 `$PY $H/timeline_view.py <原始影片> <start> <end> --n-frames 20 -o wave.png` 給他看 — 使用者從波形的時間軸讀出精確秒數。
- 修正一律用**原始影片時間**(重剪也不會跑掉)。輸出時間軸的秒數每次重剪都會位移 — 絕不拿舊數字去加減offset。
- 你聽不到聲音。字到底是什麼字,由使用者的耳朵或波形決定,不要重跑 Whisper(換大模型不會解決重複字問題)。

### 4. 字幕(HyperFrames 輕量路線 — 不做去背)

```bash
mkdir <專案>/工作檔/captions && cd 進去
npx hyperframes init . --non-interactive --video ../preview_vN.mp4
```

直接寫 `index.html`(用它產生的骨架 + 這些規則):
- 畫布 + 影片元素尺寸對齊素材(直式 = 1080x1920;骨架預設橫式 — 一定要改)
- `lang="zh-Hant"`,字型 `"Source Han Serif VF"`,用 `@font-face { src: local("Source Han Serif VF"); }`
- 把逐字稿的字對應到輸出時間軸,要走一遍 EDL 重算(每次剪接改動後**從頭重算**,絕不拿舊數字加減)
- 分成自然的句子長度(8-10 字一組)。上字幕前把分組清單當文字給使用者看,讓他重新斷句
- 只做句子層級的字幕框,連續講話時要接續不斷(不要有空掉的空檔)。**不做逐字 highlight** — Whisper 的逐字時間不夠準,量產會出包
- 每個有時間的元素:`class="clip"` + `data-start` + `data-duration` + `data-track-index`;一條暫停的 GSAP timeline 掛在 `window.__timelines["main"]`;只能用確定性的動畫(不能用 Math.random／Date.now／無限重複)
- **`data-duration` 用 ffprobe 實際量到的剪好檔案長度,絕不用 EDL 加總**(loudnorm 會多約 0.2 秒;用 EDL 數字會把最後一個字截掉)

每次改完一定 `npx hyperframes lint` → 修掉 error → 才 render。(想要更多特效技能:`npx hyperframes skills update` 拉官方 HyperFrames 技能。)

### 5. 特效(選配)

GSAP 疊層,跟字幕同一個 composition:
- 對手勢／動作的特效,「放哪」「什麼時候」是**視覺問題**:擷取影格(`ffmpeg -ss T -i vid -vframes 1 f.png`)去看,把元素放在手／動作的位置。逐字稿沒辦法告訴你手在哪、手指什麼時候彈。
- 用真的品牌素材,不要自己畫(catalog 沒有的使用者自己給 — 資料庫有缺是正常的)
- 只用有限次重複、cubic easing,重疊的 tween 加 `overwrite:"auto"`

### 5.5 插 b-roll(選配)

補充畫面。放哪由使用者／建議決定(見上面「素材庫與 b-roll」),不自動放。跟字幕特效同一個 composition,b-roll 就是**在主影片上面多疊一個 `<video>`**,主影片的人聲繼續播(音訊是獨立的 track)。兩種模式:

- **整段切換(cutaway)**:b-roll 蓋滿整個畫面(full canvas, `z-index` 蓋過主影片),在那幾秒把人臉整個換掉,聲音照播。
- **畫中畫(PiP)**:b-roll 縮成角落小窗(定位 + `border-radius` + 陰影),人臉留在後面。

驗證過的三個坑(踩到 render 會出錯或畫面凍住):
1. b-roll 的 `<video>` 要**自己當一個 clip**(直接掛 `data-start`/`data-duration`/`class="clip"`),**不要包在另一個有 `data-start` 的 `<div>` 裡** — 巢狀 render 會把它凍住。樣式(圓角、陰影、full/角落)直接寫在 `<video>` 上。
2. 每個 `<video>` 要有**唯一 id**,不然 render 找不到會凍住。
3. `data-track-index` 是**時間軌不是圖層**:host 跟它的媒體如果時間重疊,就不能同一個 track;前後圖層用 CSS `z-index` 控。想切片段用 `data-media-start` 挑素材的起點。

改完照樣 `npx hyperframes lint` → 修 error → render。

### 6. 輸出來看

```bash
npx hyperframes render --quality standard --output <專案>/成品.mp4
```

`--quality draft` 輸出的 codec 只能給 AI 自己擷取影格檢查用 — 在播放器裡會播不完整。**任何要給使用者看的一定要 `standard`。** render 完用 ffprobe 確認長度;擷取 3-5 張影格自己看過,再跟使用者說做好了。

### 7. 聲音(音效 + 背景音樂)— 一次 ffmpeg 混音,影片複製不重壓

搜資料庫(要 heygen 登入):`heygen audio sounds list --type sound_effects --query "..." --min-score 0.4 --limit 6`(音樂用 `--type music`)。下載幾個候選讓**使用者用耳朵挑** — 語意分數不是耳朵。用 `ffmpeg -i f.mp3 -af volumedetect -f null -` 看音量,太小聲的檔要放大(峰值 -18dB 的音效大概要 6 倍才聽得到)。

```bash
ffmpeg -y -i video.mp4 -i sfx1.mp3 -i bgm.mp3 -filter_complex "
[1:a]aformat=channel_layouts=stereo,volume=0.55,adelay=MS|MS[s1];
[2:a]atrim=0:DUR,afade=t=in:st=0:d=0.9,afade=t=out:st=END:d=1.4,volume=0.2[bgm];
[0:a][s1][bgm]amix=inputs=3:normalize=0[mix];[mix]alimiter=limit=0.97[aout]
" -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k <專案>/成品.mp4
```

背景音樂音量約 0.15-0.25(壓在人聲下面);短的曲子用 `-stream_loop` 循環。音效時間點用輸出時間軸的字詞秒數。用完問使用者要不要存進素材庫(見上面建議循環)。

---

## 收尾:更新偏好檔(學習循環的終點)

一支影片做完後,把這次學到的關於這位使用者的東西寫進 `KIT/我的剪輯偏好.md` 的對應段落:字幕風格(字型、大小、位置)、愛用的音樂調性、剪接節奏習慣、常用的特效／品牌素材、任何他重複要求或明確不要的東西。簡短、具體、覆蓋掉「尚未記錄」。這樣下次一開場讀它,就越來越懂他。

---

## 出錯回報 — 幫學員把問題傳給 Jake

碰到你(AI)自己修不掉的錯誤,或使用者明顯卡住時,不要讓新手自己想辦法,幫他產一份報告寄給 Jake:

1. 寫一份報告到 `KIT/錯誤回報/<YYYY-MM-DD-HHMM>.md`,內容要讓 Jake 不用來回問就看得懂:
   - 發生時間
   - 卡在哪一步(轉逐字稿／剪接／字幕／特效／音效／輸出)
   - 你實際跑的指令
   - **完整的錯誤訊息**(原封不動貼,不要摘要)
   - 環境快照:`uname -a`、`python3 --version`、`node --version`、`ffmpeg -version` 第一行、Whisper 引擎(mlx / faster-whisper)、思源宋體有沒有裝
   - 使用者用白話描述他想做什麼、看到什麼
2. 然後照這樣告訴使用者:
   > 我把錯誤報告存在 `錯誤回報/<檔名>.md` 了。請加入頭家校院 LINE 官方帳號 **@headhomeuni**(連結:https://lin.ee/oozBXeG),把這個檔案傳過去,訊息寫:
   > 「呼叫Jake, 我的影片剪輯有錯誤,報告在這邊謝謝」
3. 使用者也可以隨時說「回報問題」,你就當場產一份同樣格式的報告給他傳。

---

## 互動原則(為什麼流程能又快又順)

1. 提案 → 確認 → 執行 → 給他看 → 修。絕不憑對聲音內容的猜測就重剪。
2. 使用者的耳朵 = 聲音的真相;波形 = 兩人共用的「指這裡」工具;原始影片時間 = 共用的座標系。
3. 使用者回報你驗證不了的東西(某個字重複了、音效沒對上),先用工具查(split_blobs、擷取影格)再改數字。
4. 輸出檔案編版本(`preview_v1..vN`),EDL 當唯一真相,舊 render 邊做邊刪。

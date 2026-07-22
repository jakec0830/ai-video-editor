# AI 剪輯工具包（ai-edit-kit）

用 AI 幫你剪口播影片。你錄一段對著鏡頭講話的影片，AI 幫你剪掉 NG 跟停頓、上字幕、加特效跟音效、配背景音樂，最後輸出成品。

這個工具包已經在真實影片上完整跑通過一次。

## 這個工具包做什麼

一句話：你講話，AI 剪片。具體流程：

1. 轉逐字稿（本機跑，免費）
2. 剪掉 NG、重拍、停頓
3. 上繁體中文字幕
4. 加特效（例如你的手指一比，畫面就出現東西）
5. 加音效跟背景音樂
6. 輸出成品 MP4

這個工具包是給「口播影片」用的（有人對著鏡頭講話）。它底層用的工具（HyperFrames）其實能做更多類型的影片（產品介紹、解說片、動態圖文），等你上手了想玩更多，可以直接用 `npx hyperframes`。但這個工具包的自動流程專注在把口播影片剪好。

## 資料夾長怎樣

裝好之後，你平常只會用到這幾個：

```
ai-video-editor/
  審片.html          雙擊打開，審片用
  我的影片/          你的影片專案（每支一個資料夾，裡面有 審片區/ 可以看）
  素材庫/            音樂／音效／b-roll，可重複用
  我的剪輯偏好.md    AI 記住的你的習慣，想看/改都可以
  錯誤回報/          回報跟復盤的存檔
```

其他像 `tools/`、`setup.sh`、`README.md` 是工具包內部運作用的，平常不用點開，交給 AI 處理就好。

## 安裝

新手建議用 **Claude 桌面版 App**：有畫面、不用碰終端機。習慣打指令的人看下面「進階：用終端機」。

### 用桌面版 App（推薦，最適合新手）

**一、先備好（你自己做）**

- 到 claude.ai 開通 **Claude 訂閱（Pro 或 Max）**，整個流程靠這個，課前先備好。
- 下載安裝 **Claude 桌面版 App**（到 claude.ai 下載 Mac / Windows 版），一般安裝、登入。它本身就內建 Claude Code，你不用另外裝 Node 或 CLI。
- **Windows** 要另外裝 **Git for Windows**（git-scm.com/downloads/win），裝完把 App 重開。Mac 通常內建 git。

**二、下載工具包**

1. 打開 App，點上面的 **Code** 分頁。
2. 環境選 **Local**（在你自己電腦上跑，才能處理你的影片）。
3. 先隨便選一個資料夾（例如「文件」），在對話框打：

   > 幫我把這個 clone 下來：https://github.com/jakec0830/ai-video-editor.git

   它會下載成一個 `ai-video-editor` 資料夾。

**三、開始設定**

4. 用 **Select folder（選資料夾）** 選剛剛那個 `ai-video-editor` 資料夾。
5. 在對話框打：

   > 幫我一步一步安裝設定

6. 照它說的做。它會檢查你缺什麼（Node、ffmpeg、字型等）一個一個幫你裝。有幾步要你自己動手（輸入電腦密碼、瀏覽器登入 heygen），它會停下來明確告訴你「這步換你做」，你做完它接著走。

裝好後把口播影片丟進去，說「幫我剪這支影片」。

### 進階：用終端機 CLI（習慣打指令的人）

```
# 1. 裝 Claude Code
curl -fsSL https://claude.ai/install.sh | bash      # Mac / Linux
# Windows（PowerShell）: irm https://claude.ai/install.ps1 | iex
# 2. 登入
claude
# 3. 下載工具包（會自動建 ai-video-editor 資料夾）
git clone https://github.com/jakec0830/ai-video-editor.git
# 4. 進資料夾、開 Claude Code
cd ai-video-editor
claude
# 5. 在裡面打：幫我一步一步安裝設定
```

### 如果你想自己裝（不想讓 AI 代勞）

一鍵安裝腳本：

- **Mac / Linux**：在資料夾裡跑 `bash setup.sh`。
- **Windows**：在 PowerShell 裡跑 `powershell -ExecutionPolicy Bypass -File .\setup.ps1`。它會用 winget 幫你把 Python、Node、ffmpeg 都裝好，再裝字型、建環境。

需要的東西一覽（腳本都會幫你處理，這裡列給你知道）：

- **Node.js（22 以上）** — 字幕跟特效用。Mac `brew`，Windows winget `OpenJS.NodeJS.LTS`，或 nodejs.org 下載。
- **ffmpeg** — 影音核心。Mac `brew install ffmpeg`，Windows winget `Gyan.FFmpeg`，Linux `apt install ffmpeg`。
- **思源宋體（Source Han Serif TC）** — 字幕字型。Mac `brew install --cask font-source-han-serif-vf`，Windows 跑 `scripts\windows\install-font.ps1`（`setup.ps1` 會自動叫它），Linux 到 github.com/adobe-fonts/source-han-serif 下載。
- **heygen CLI（選配）** — 只有要用音效／背景音樂資料庫才需要。`curl -fsSL https://static.heygen.ai/cli/install.sh | bash`，再 `heygen auth login --oauth`。不裝就自己準備音檔丟進來。

### 手動安裝（腳本失敗時）

```
# 1. 建 Python 環境（在 tools/freecut/ 底下）
python3 -m venv tools/freecut/.venv

# 2. 啟動環境並裝套件
#    Mac/Linux:  source tools/freecut/.venv/bin/activate
#    Windows:    tools\freecut\.venv\Scripts\activate
pip install requests pillow numpy opencc-python-reimplemented

# 3. 裝轉逐字稿引擎（看你的系統）
pip install mlx-whisper      # 只有 Apple Silicon Mac 用這個（最快）
pip install faster-whisper   # Intel Mac / Linux 用這個
#   Windows：見下面「Windows 疑難排解」，pip 版通常會被系統安全防護擋掉，
#            要改用 Faster-Whisper-XXL 獨立版。
```

其餘（Node、ffmpeg、字型、heygen）照上面裝。

### Windows 疑難排解

Windows 全新機器最容易撞到的坑（都已知，照做即可）：

**1. 逐字稿引擎被擋（最重要）。** 症狀：`pip install faster-whisper` 明明成功，但一用就出現
「**應用程式控制原則已封鎖此檔案**」。原因是 Windows 11 內建的 **Smart App Control（智慧型應用程式控制）** 把 faster-whisper 依賴套件裡的未簽章 DLL 擋掉了。

**不要為了這個去關掉 Smart App Control**（關掉是不可逆的，要重灌才能開回來）。正解是改用不會被擋的獨立版：

1. 到 https://github.com/Purfview/whisper-standalone-win/releases 下載 **Faster-Whisper-XXL** 的 Windows 版。
2. 解壓縮，把整個資料夾放進 `tools/whisper-xxl/`（裡面要有 `faster-whisper-xxl.exe`）。或設環境變數 `WHISPER_XXL_EXE` 指到那個 exe。
3. 之後轉逐字稿會自動用它。它產出的是簡體字，工具包會用 OpenCC 自動轉成繁體（`setup` 已幫你裝 opencc）。

注意這個獨立版比較大（下載約 1.4GB、解壓約 4.4GB），下載要等幾分鐘，屬正常。

**2. Python 是「空殼」。** 全新 Windows 打 `python` 會跳出 Microsoft Store，那代表 Python 其實沒裝。用 `winget install Python.Python.3.12`（或 `setup.ps1`）裝好，把終端機關掉重開再重跑。

**3. 終端機噴一堆 `UnicodeEncodeError` / `cp950`。** 這只是繁中主控台的顯示編碼問題，通常不代表安裝失敗，可忽略。想看清楚訊息就用 PowerShell 先跑 `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` 再重試。

## 怎麼用

1. 用 Claude Code（或 Codex）打開這個工具包資料夾。裡面的 `ai-edit` 技能會自動載入。
2. 把你的影片檔給它，說「幫我剪這支影片」。
3. 它會幫你在 `我的影片/` 底下開一個專案資料夾，然後一步一步走：先轉逐字稿，提議怎麼剪，你確認，再上字幕、加特效音樂。

重點：**用你的耳朵當裁判**。AI 聽不到聲音，它只看得到時間軸。哪裡剪得不對、音效沒對上，你直接講，它會用波形圖跟你對時間點。

**審片（一次改完，不要一句一句回）**：AI 給你 preview 後，與其一句一句回「這裡改那裡改」，不如用審片工具一次收齊。打開你專案裡的 `審片區/` 資料夾，把裡面**兩個檔一起**拖進 `審片.html`（影片 + 字幕檔）：

- 右邊會列出所有字幕句，點句子影片跳過去、影片上也會即時顯示字幕，方便你判斷長短要不要合併/拆開。
- **改錯字**：雙擊字幕句直接改。**斷句**：改字時打「/」分成兩句。**合併**：滑過句子按「併下句」。**塗黃關鍵字**：反白詞語，跳出「塗黃這個詞」按鈕。
- **剪接**：下面拖一段區間（或按「✂ 從這裡」「到這裡」），要剪掉按「剪掉這段」，想蓋補充畫面按「加 b-roll」。
- 想標「位置」（字幕擺哪、東西放哪），開「✎ 畫筆」（快速鍵 P）直接在畫面上圈。
- 全部標完按「複製全部」，整段貼回給 AI，它一次改完再重出一版。這樣快、也省 token。改錯了 Ctrl+Z 可以復原。

## 檔案怎麼放（AI 會幫你整理，你大概知道就好）

一支影片一個資料夾，放在 `我的影片/` 底下：

```
我的影片/
  我的第一支/
    原始影片.mov      你錄的原檔，不會被動到
    成品.mp4          完成品，你要的就這個
    審片區/           要審片時，這裡的檔案拖進 審片.html 就對了
    工作檔/           所有中間檔（逐字稿、剪接配方等），清理只刪大檔案不刪配方
```

還有一個跨影片共用的**素材庫**，放你會重複用的東西：

```
素材庫/
  背景音樂/  音效/  b-roll/  圖片/
```

- 剪片用到新的音樂／音效／圖，AI 會問你「要不要存進素材庫下次重複用」。說要它就幫你放好。
- **b-roll** 是你口播講到一半插進來的補充畫面（空景、產品特寫、示範畫面）。放進 `素材庫/b-roll/`，AI 在適合的段落會提醒你插畫面。詳見 `素材庫/說明.md`。

**AI 越用越懂你**：每次做完，AI 會把學到的你的習慣（字幕風格、愛用音樂、剪接節奏）寫進 `我的剪輯偏好.md`，下次一開始先讀。你也可以自己改這份。

**清理**：工作檔會越積越多。跟 AI 說「清理」它就幫你清，只刪大媒體檔，配方文字檔都會留著，你的原始影片跟成品也都會留著。或自己跑 `bash tools/cleanup.sh 我的影片/某專案`。

## 如何更新（拿到 Jake 的最新版）

工具包會一直改進。**你不用自己記著更新** — 每次打開，AI 會自動看有沒有新版，有的話問你「要更新嗎？」，說好它就幫你拉下來。

想自己更新也可以：在資料夾裡跑 `bash tools/update.sh`。

你的影片、素材、剪輯偏好都不會被更新蓋掉（那些沒有進 git）。

前提：你是用 `git clone` 下載的（正常那種）。如果是下載 ZIP，就沒辦法自動更新，要更新請重新下載。

## 幾個一定要知道的坑（不然會踩）

- **要看成品，一定用 standard 品質輸出**。有個 draft 快速模式是給 AI 自己檢查用的，那個檔案在播放器裡會播不完整、看起來像被截斷。不是壞掉，是用錯模式。
- **Whisper 轉重複字會出錯**。如果你連講三次「不知道」，它常常只認到一次，時間也會抓歪。這是所有 Whisper 的通病，換大模型不會好。工具包裡有波形工具（`xref_silence.py`、`split_blobs.py`）專門抓這種地方，AI 會在剪之前先標出來給你看。
- **音效／音樂資料庫不一定有你要的**。例如煞車聲、某些特定音效，資料庫可能沒有。這很正常，不是失敗。沒有就自己找一個檔案丟進來，AI 幫你混進去。

## 出錯了怎麼辦

卡住或出現你看不懂的錯誤，直接跟 AI 說「回報問題」。它會把發生什麼、完整錯誤、你的電腦環境整理成一份報告，存在 `錯誤回報/` 資料夾裡。接著加入頭家校院 LINE 官方帳號 **@headhomeuni**（連結：https://lin.ee/oozBXeG），把那個檔案傳過去，訊息寫：

> 呼叫Jake, 我的影片剪輯skill有錯誤，報告在這邊謝謝

Jake 看報告就能幫你修，不用你自己解。

## 關於 Clawd 吉祥物

Clawd 是 Anthropic（Claude 的公司）的官方吉祥物。課堂 demo 用沒問題，但如果要放到你對外的行銷影片上當品牌，要注意：把別人家的吉祥物放在你的行銷上，可能會讓人誤會你跟 Anthropic 有官方合作。要用的話用「Claude 標誌」比較安全，表示「這是 Claude 剪的」，而不是拿吉祥物當你自己的品牌。

## 內容清單

**平常會用到的：**
- `審片.html` — 審片工具（瀏覽器打開，收齊要改的地方一次貼回 AI）
- `我的影片/` — 你的影片專案放這
- `素材庫/` — 可重複用的音樂／音效／b-roll／圖片（含 `預設包/` 起手式音效音樂）
- `我的剪輯偏好.md` — AI 記住的你的習慣
- `錯誤回報/` — 回報跟復盤的存檔

**工具包內部運作用的（一般不用點開）：**
- `.claude/skills/ai-edit/` — AI 剪輯技能（Claude/Codex 讀這個知道怎麼做）
- `tools/freecut/helpers/` — 剪接、轉逐字稿、波形檢查、字幕產生的腳本
- `setup.sh` — 一鍵安裝，Mac / Linux（下載完第一個要跑的，所以留在最外層）
- `setup.ps1` — 一鍵安裝，Windows（用 winget；同樣留在最外層）
- `scripts/windows/install-font.ps1` — Windows 思源宋體安裝（setup.ps1 會自動叫它）
- `tools/update.sh` — 更新到最新版
- `tools/cleanup.sh` — 清理工作檔
- `tools/我的剪輯偏好.範本.md` — 偏好檔範本（setup.sh 會複製成你自己的 `我的剪輯偏好.md`）
- `tools/PIPELINE-NOTES.md` — 完整技術筆記（進階參考，一般用不到）

## 授權與致謝

- 這個工具包整體採 **MIT 授權**（見 `LICENSE`）。Copyright (c) 2026 Jake, 頭家校院。你可以自由使用、修改、散布。
- `tools/freecut/` 底下的剪接／轉逐字稿腳本改編自開源專案 **video-use**（browser-use 團隊，MIT 授權）。原始授權保留在 `tools/freecut/LICENSE`，Copyright (c) 2026 Browser Use。感謝他們。
- 其中 `helpers/xref_silence.py` 跟 `helpers/split_blobs.py` 是這個工具包原創（抓 Whisper 時間軸出錯用的波形工具），一樣走 MIT。
- 字幕／特效用的 **HyperFrames**（heygen 團隊）透過 `npx hyperframes` 呼叫官方發布版，本工具包沒有夾帶它的原始碼。

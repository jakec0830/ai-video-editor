# env.sh — 讓 AI 的每個 shell 都找得到工具,不管是怎麼裝的。
#
# 為什麼需要這支:實測(2026-07-22 學員回報)發現,安裝時寫進 ~/.zshenv 的 PATH,
# 「當下已經開著」的 Claude Code session 吃不到(環境是 session 開始時快照的),
# 於是明明裝好了,AI 每個指令都 command not found。
# 解法:AI 在每個 session 開頭 source 這支,當場把該有的路徑補進 PATH。
# 冪等 — 重複 source 不會讓 PATH 越長越長。
#
# 用法(SKILL.md 的開場步驟): source "KIT/tools/env.sh"

# 家目錄安裝(免密碼路線): ~/.local/bin
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) [ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Homebrew(Apple Silicon 預設位置)— 新裝好 brew 但 shell 設定還沒重讀時
case ":$PATH:" in
  *":/opt/homebrew/bin:"*) ;;
  *) [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)" ;;
esac

# Homebrew(Intel Mac 位置)
case ":$PATH:" in
  *":/usr/local/bin:"*) ;;
  *) [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)" ;;
esac

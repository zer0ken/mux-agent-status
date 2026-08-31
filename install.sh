#!/usr/bin/env bash
# tmux-agent-status 설치. Claude Code 훅은 쓰지 않으므로 넣을 것이 없다.
# 이전 판이 ~/.claude/settings.json 에 넣어 둔 훅이 있으면 걷어낸다.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

if [ -f "$SETTINGS" ] && grep -q "agent-hook.sh" "$SETTINGS" 2>/dev/null; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  python3 - "$SETTINGS" <<'@INNER@'
import json, sys
path = sys.argv[1]
d = json.load(open(path, encoding="utf-8"))
h = d.get("hooks", {})
removed = 0
for ev in list(h):
    keep = []
    for grp in h[ev]:
        hooks = [x for x in grp.get("hooks", [])
                 if "agent-hook.sh" not in str(x.get("command", ""))]
        removed += len(grp.get("hooks", [])) - len(hooks)
        if hooks:
            grp["hooks"] = hooks
            keep.append(grp)
    if keep:
        h[ev] = keep
    else:
        del h[ev]
json.dump(d, open(path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print("이전 판의 훅 %d개를 걷어냈다" % removed)
@INNER@
fi

cat <<@MSG@
tmux.conf 에 아래 한 줄이 필요하다.

  run-shell "$DIR/tmux/agent-status.tmux"

배지는 쓰던 상태바 포맷에 끼워 넣는다.

  set -g window-status-format "#I #{E:@agent_win_badge}#W"
  set -wg pane-border-format  "#{pane_index} #{E:@agent_badge_pane}#{pane_title}"
@MSG@

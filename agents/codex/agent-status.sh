#!/usr/bin/env bash
# codex 세션의 상태를 파일 하나에 쓴다. mux-agent-status 의 소비자가 그 파일을 읽어
# 각자의 상태바에 표시한다.
#
# codex 는 세션의 상태를 파일로 내보내지 않는다. Claude Code 의
# ~/.claude/sessions/<pid>.json 에 해당하는 것이 없어서 이 스크립트가 대신 쓴다.
# codex 는 훅을 부를 때 자기 환경을 물려주므로 mux 가 심어 둔 환경변수로 pane 을
# 알 수 있고, 훅의 부모가 codex 프로세스라서 PPID 가 그 세션의 pid 다.
#
# 파일: $TMPDIR/mux-agent-status-<uid>/<mux>/codex-<pane>
# 내용: "<상태> <pid>"
#
# mux 는 codex 프로세스 환경에서 판별한다. tmux 와 그 별칭(psmux 포함)은
# TMUX_PANE 을, zellij 는 ZELLIJ_PANE_ID 를 심어 두므로 어느 것이 있는지로
# 정하고, pane id 표기는 그 mux 가 원래 쓰는 그대로 남긴다(tmux 계열은 %
# 를 뗀 숫자, zellij 는 ZELLIJ_PANE_ID 값 그대로).
#
# 인자로 상태를 받는다. 어느 훅이 부르는지는 hooks.json 이 정한다.
#   busy    돌고 있다
#   idle    끝났다, 사용자 차례
#   remove  세션이 끝났다
set -u

if [ -n "${TMUX_PANE:-}" ]; then
  mux=tmux
  pane=${TMUX_PANE#%}
elif [ -n "${ZELLIJ_PANE_ID:-}" ]; then
  mux=zellij
  pane=$ZELLIJ_PANE_ID
else
  exit 0   # 알려진 mux 밖에서는 표시할 곳이 없다
fi

dir="${TMPDIR:-/tmp}/mux-agent-status-$(id -u)/$mux"
file="$dir/codex-$pane"

case "${1:-}" in
  busy|idle) mkdir -p "$dir" && printf '%s %s\n' "$1" "$PPID" > "$file" ;;
  remove)    rm -f "$file" ;;
esac

exit 0   # 상태 파일을 못 써도 codex 는 그대로 돈다

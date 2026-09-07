#!/usr/bin/env bash
# codex 세션의 상태를 파일 하나에 쓴다. mux-agent-status 의 소비자가 그 파일을 읽어
# 각자의 상태바에 표시한다.
#
# codex 는 세션의 상태를 파일로 내보내지 않는다. Claude Code 의
# ~/.claude/sessions/<pid>.json 에 해당하는 것이 없어서 이 스크립트가 대신 쓴다.
# codex 는 훅을 부를 때 자기 환경을 물려주므로 mux 가 심어 둔 환경변수로 pane 을
# 알 수 있다.
#
# 파일에 적는 pid 는 세션을 가진 codex 프로세스다. 부모를 거슬러 올라가며 이름이
# codex 인 프로세스를 찾는다. 훅의 직계 부모는 codex 가 훅을 띄울 때만 쓰고 턴이
# 끝나면 버리는 프로세스라서, 그 pid 를 적으면 소비자가 생존 검사에서 죽은 것으로
# 보고 파일을 지운다. 조상에서 codex 를 찾지 못하면 0 을 적고, 소비자는 0 을 보면
# 생존 검사를 건너뛰고 파일을 그대로 둔다.
#
# 파일: $TMPDIR/mux-agent-status[-<uid>]/<mux>/<세션>/codex-<pane>
# 내용: "<상태> <pid>"
#
# mux 는 codex 프로세스 환경에서 판별한다. tmux 와 그 별칭(psmux 포함)은
# TMUX_PANE 을, zellij 는 ZELLIJ_PANE_ID 를 심어 두므로 어느 것이 있는지로
# 정하고, pane id 표기는 그 mux 가 원래 쓰는 그대로 남긴다(tmux 계열은 %
# 를 뗀 숫자, zellij 는 ZELLIJ_PANE_ID 값 그대로).
#
# psmux 는 window_id 와 pane_id 를 세션마다 따로 채번해서, 서로 다른
# 세션이 같은 pane 번호를 가질 수 있다. 세션 이름까지 넣어야 그 둘을
# 가른다. tmux 는 pane_id 가 이미 서버 전체 고유라 세션 서브디렉터리가
# 없어도 됐지만, 모든 mux 에 공통으로 두면 소비자 쪽 코드가 mux 마다
# 갈리지 않는다.
#
# 인자로 상태를 받는다. 어느 훅이 부르는지는 hooks.json 이 정한다.
#   busy    돌고 있다
#   idle    끝났다, 사용자 차례
#   remove  세션이 끝났다
set -u

if [ -n "${TMUX_PANE:-}" ]; then
  mux=tmux
  pane=${TMUX_PANE#%}
  session=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null) || exit 0
elif [ -n "${ZELLIJ_PANE_ID:-}" ]; then
  mux=zellij
  pane=$ZELLIJ_PANE_ID
  session=${ZELLIJ_SESSION_NAME:-}
else
  exit 0   # 알려진 mux 밖에서는 표시할 곳이 없다
fi
[ -n "$session" ] || exit 0   # 세션을 모르면 다른 세션의 pane 과 가를 수 없다

# Windows 의 임시 디렉터리는 이미 사용자마다 갈라져 있어 경로에 uid 를 넣지
# 않는다. POSIX 는 /tmp 를 공용으로 쓰므로 uid 로 갈라 둔다. Node 는 Windows
# 에서 process.getuid 를 제공하지 않아 pi 확장이 bash 의 id -u 와 같은 값을 낼
# 수 없으니, 쓰는 쪽과 읽는 쪽이 OS 로 갈라 같은 경로를 만든다.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
  *)                    IS_WINDOWS= ;;
esac
if [ -n "$IS_WINDOWS" ]; then
  STATE_ROOT="${TMPDIR:-/tmp}/mux-agent-status"
else
  STATE_ROOT="${TMPDIR:-/tmp}/mux-agent-status-$(id -u)"
fi
dir="$STATE_ROOT/$mux/$session"
file="$dir/codex-$pane"

# 조상을 훑어 codex 를 찾는다. ps 로 묻는 것은 /proc 이 없는 POSIX(macOS 등)
# 에서도 같은 코드가 돌기 때문이다. comm 이 경로로 오는 구현이 있어 마지막
# 경로 요소만 본다. init(1) 에 닿거나 깊이를 넘기면 찾기를 그만둔다.
AGENT_PROCESS=codex
MAX_DEPTH=8

pid=0
cur=$PPID
depth=0
while [ "$depth" -lt "$MAX_DEPTH" ] && [ -n "$cur" ] && [ "$cur" -gt 1 ] 2>/dev/null; do
  name=$(ps -o comm= -p "$cur" 2>/dev/null | tr -d ' 	')
  name=${name##*/}
  if [ "$name" = "$AGENT_PROCESS" ]; then
    pid=$cur
    break
  fi
  cur=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' 	')
  depth=$((depth + 1))
done

case "${1:-}" in
  busy|idle) mkdir -p "$dir" && printf '%s %s\n' "$1" "$pid" > "$file" ;;
  remove)    rm -f "$file" ;;
esac

exit 0   # 상태 파일을 못 써도 codex 는 그대로 돈다

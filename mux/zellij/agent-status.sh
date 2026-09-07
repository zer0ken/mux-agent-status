#!/usr/bin/env bash
# agent-status.sh - 에이전트 상태를 zellij 탭 이름에 밀어 넣는 티커.
#
# zellij 는 상태바를 플러그인으로 그리고, 그 플러그인이 읽는 사용자 정의 옵션이
# 없다. tmux 처럼 집계를 옵션에 두고 포맷에서 참조하게 할 자리가 없어서, 이
# 티커는 mux/psmux 와 같이 완성된 집계 문자열을 탭 이름 뒤에 직접 붙인다.
# 탭은 `rename-tab-by-id` 로 지정한다. 포커스를 옮기지 않고 탭마다 따로 이름을
# 줄 수 있는 유일한 명령이다.
#
# 상태는 에이전트가 스스로 쓴 것을 읽는다. pi 와 codex 는 이 저장소가 담은
# 확장과 훅이 $TMPDIR/mux-agent-status[-<uid>]/zellij/<세션>/<에이전트>-<pane>
# 을 갱신한다. Claude Code 는 세션 파일에 zellij 의 pane 을 적지 않아서 이
# 티커가 읽을 것이 없다.
#
# pane 은 $ZELLIJ_PANE_ID 를 그대로 쓴다. zellij 는 터미널 pane 과 플러그인
# pane 의 id 를 각각 1부터 채번해서 둘이 겹치므로, 상태를 맞출 때 터미널
# pane 만 고른다. 플러그인 pane 에는 에이전트가 뜨지 않는다.
#
# 어휘는 claude-session-manager 와 같다.
#   waiting  입력이 필요하다
#   idle     끝났다, 사용자 차례
#   busy     돌고 있다
#
# 탭마다 속한 pane 을 상태별로 세어 `waiting idle busy` 고정 순서로 marker 와
# 개수를 늘어놓고, 탭 이름 뒤에 붙인다. 원래 이름은 탭마다 한 번만 기억해 두고,
# 매 틱마다 "원래 이름 + 집계" 로 다시 조립한다. 집계할 것이 없어지면 원래
# 이름으로 되돌린다.
#
# 이 티커 하나가 그 기계의 zellij 세션을 모두 맡는다. tmux 와 psmux 는 서버가
# 티커를 띄워 주지만 zellij 에는 설정에서 명령을 돌리는 자리가 없어서, 티커를
# 세션 밖에서 띄우고 세션 목록을 스스로 훑는다.
set -uo pipefail

INTERVAL=1
STARTUP_TRIES=30
ZELLIJ_BIN="${ZELLIJ_BIN:-zellij}"

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
STATE_DIR="$STATE_ROOT/zellij"

# zellij 의 탭 이름은 탭 바 플러그인이 글자로만 그린다. tmux 의 포맷
# 이스케이프에 해당하는 것이 없어서 색을 실을 자리가 없다. 그래서 marker 는
# 상태마다 다른 글리프로 가른다. 환경변수로 값을 미리 채워 두면 이 기본값
# 대신 그 값을 쓴다.
MARKER_WAITING="${MARKER_WAITING:-?}"
MARKER_IDLE="${MARKER_IDLE:-✓}"
MARKER_BUSY="${MARKER_BUSY:-↻}"
ORDER=(waiting idle busy)

# 상태 파일에 적힌 프로세스가 살아 있는지 본다. kill -0 은 MSYS 가 매긴 PID 만
# 알아보고, pi 확장이 적는 Node 의 process.pid 는 Windows 네이티브 PID 라서 Git
# Bash 에서는 언제나 실패한다. 그 경우 ps -W 가 보고하는 WINPID 로 다시 본다.
# WINPID 목록은 $WINPID_TTL 초마다 한 번만 읽는다.
WINPID_TTL=5
declare -A live_winpid=()
winpids_at=0
read_winpids() {
  live_winpid=()
  local a b c w
  while read -r a b c w _; do
    [ -n "$w" ] && live_winpid[$w]=1
  done < <(ps -W 2>/dev/null)
  winpids_at=${EPOCHSECONDS:-0}
}
pid_alive() {
  kill -0 "$1" 2>/dev/null && return 0
  [ -n "$IS_WINDOWS" ] || return 1
  # ps -W 는 프로세스를 모두 훑어 Windows 에서 값이 비싸다. 신선한 목록에 이미
  # 있으면 그것으로 끝내고, 없을 때만 다시 읽는다. 방금 뜬 프로세스를 죽은
  # 것으로 오판하지 않으려면 목록에 없을 때는 반드시 다시 읽어야 한다.
  local fresh=$(( ${EPOCHSECONDS:-0} - winpids_at < WINPID_TTL ))
  [ -n "${live_winpid[$1]:-}" ] && [ "$fresh" = 1 ] && return 0
  read_winpids
  [ -n "${live_winpid[$1]:-}" ]
}

# 탭 이름 뒤에 붙은 집계를 뗀 것을 STRIPPED 에 남긴다. 이 티커가 방금 붙인
# 것만 떼면, 앞서 돌던 티커가 남긴 집계를 원래 이름으로 오인해 그 뒤에 또
# 붙는다. 티커가 다시 뜰 때마다 이름이 늘어나므로, 집계의 모양을 알아보고 뗀다.
# marker 는 사용자가 정할 수 있어서 정규식 메타문자가 들어올 수 있다. 시작할
# 때 한 번 escape 해 패턴을 만들어 둔다.
ere_quote() { printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'; }
STRIP_RE=" ($(ere_quote "$MARKER_WAITING")|$(ere_quote "$MARKER_IDLE")|$(ere_quote "$MARKER_BUSY")) [0-9]+$"
strip_aggregate() {
  STRIPPED=$1
  while [[ $STRIPPED =~ ^(.*)$STRIP_RE ]]; do
    STRIPPED=${BASH_REMATCH[1]}
  done
}

ready=""
for _ in $(seq "$STARTUP_TRIES"); do
  if "$ZELLIJ_BIN" list-sessions -s >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ -n "$ready" ] || exit 0

lock_dir="${TMPDIR:-/tmp}/agent-status-zellij-$(id -u).lockdir"
mkdir "$lock_dir" 2>/dev/null || exit 0    # 이미 돌고 있으면 끝낸다
trap 'rmdir "$lock_dir" 2>/dev/null' EXIT

# 세션이 한 번도 일한 적 없으면 집계에 넣지 않는다. 띄워만 두고 아무 작업도
# 하지 않은 세션과 방금 응답을 마친 세션이 둘 다 idle 이기 때문이다.
declare -A worked=() base_name=() prev_suffix=()
shopt -s nullglob

# 탭마다 pane 을 세어 집계를 다시 붙인다. 인자는 세션 이름이다.
update_session() {
  local sess=$1
  local f base pane pst pid st tab n m
  local -A state=() count=() tab_name=()

  # ── 확장과 훅이 쓴 상태 파일. 프로세스가 죽었으면 파일을 치운다 ──
  # 경로: $STATE_DIR/<세션>/pi-<pane> 또는 codex-<pane>
  for f in "$STATE_DIR/$sess"/pi-* "$STATE_DIR/$sess"/codex-*; do
    base=${f##*/}
    pane=${base#*-}
    read -r pst pid 2>/dev/null < "$f" || continue
    if [ -n "${pid:-}" ] && [ "$pid" != 0 ] && ! pid_alive "$pid"; then
      rm -f "$f" 2>/dev/null; continue
    fi
    case "$pst" in idle|busy|waiting) state[$pane]=$pst ;; esac
  done

  # 상태 파일도 없고 앞서 붙여 둔 집계도 없으면 이 세션에 물어볼 것이 없다.
  # zellij 는 명령마다 프로세스를 띄우므로 물어보는 것 자체가 값이 든다.
  if [ ${#state[@]} -eq 0 ] && [ -z "${session_touched[$sess]:-}" ]; then
    return 0
  fi

  # 탭 이름은 list-tabs 로 얻는다. 앞의 두 칸이 숫자고 나머지가 이름이라 이름에
  # 무엇이 들어 있어도 가를 수 있다.
  local tid tpos tname
  while read -r tid tpos tname; do
    case "$tid" in ''|*[!0-9]*) continue ;; esac
    tab_name[$tid]=$tname
  done < <("$ZELLIJ_BIN" --session "$sess" action list-tabs 2>/dev/null)
  [ ${#tab_name[@]} -gt 0 ] || return 0

  # pane 과 탭의 맵핑은 JSON 으로 받는다. 표 출력은 탭 이름이 가운데 칸에 있어
  # 이름에 칸 구분과 같은 공백이 들어가면 갈라지지 않는다. 필요한 값은 pane id
  # 와 플러그인 여부와 탭 id 세 개뿐이라, 객체마다 그 세 줄만 골라 읽는다.
  local pid_ tb
  while read -r tb pid_; do
    pane=$pid_
    st=${state[$pane]:-}
    case "$st" in
      busy|waiting) worked[$sess/$pane]=1 ;;
      idle) [ -n "${worked[$sess/$pane]:-}" ] || st="" ;;
    esac
    [ -n "$st" ] && count[$tb/$st]=$(( ${count[$tb/$st]:-0} + 1 ))
  done < <("$ZELLIJ_BIN" --session "$sess" action list-panes -t -j 2>/dev/null | awk '
    /^[ \t]*\{/                     { id=""; plug=""; tab=""; next }
    /^[ \t]*"id"[ \t]*:/            { gsub(/[^0-9]/, ""); id = $0; next }
    /^[ \t]*"is_plugin"[ \t]*:/     { plug = ($0 ~ /true/) ? "1" : "0"; next }
    /^[ \t]*"tab_id"[ \t]*:/        { gsub(/[^0-9]/, ""); tab = $0; next }
    /^[ \t]*\}/                     { if (id != "" && plug == "0" && tab != "") print tab, id; next }
  ')

  local key suffix new_name any_suffix=""
  for tid in "${!tab_name[@]}"; do
    key="$sess/$tid"
    strip_aggregate "${tab_name[$tid]}"
    if [ -z "${base_name[$key]:-}" ] || [ "$STRIPPED" != "${base_name[$key]}" ]; then
      base_name[$key]=$STRIPPED
    fi

    suffix=""
    for st in "${ORDER[@]}"; do
      n=${count[$tid/$st]:-0}
      [ "$n" -gt 0 ] || continue
      case "$st" in
        waiting) m=$MARKER_WAITING ;;
        idle)    m=$MARKER_IDLE ;;
        busy)    m=$MARKER_BUSY ;;
      esac
      suffix+="${m} ${n} "
    done
    suffix=${suffix% }

    [ -n "$suffix" ] && any_suffix=1

    [ "$suffix" = "${prev_suffix[$key]:-}" ] && continue

    new_name=${base_name[$key]}
    [ -n "$suffix" ] && new_name+=" $suffix"
    "$ZELLIJ_BIN" --session "$sess" action rename-tab-by-id "$tid" "$new_name" 2>/dev/null
    prev_suffix[$key]=$suffix
  done

  # 이 세션의 탭 가운데 하나라도 집계를 달고 있으면 다음 틱에도 물어봐야 한다.
  # 상태 파일이 사라져도 붙여 둔 집계를 떼려면 한 번 더 물어봐야 하기 때문이다.
  if [ -n "$any_suffix" ]; then session_touched[$sess]=1; else unset 'session_touched[$sess]'; fi
}

declare -A session_touched=()

while :; do
  declare -A alive_session=()
  while read -r sess; do
    [ -n "$sess" ] || continue
    alive_session[$sess]=1
    update_session "$sess"
  done < <("$ZELLIJ_BIN" list-sessions -s 2>/dev/null)

  # 끝난 세션의 기억을 버린다. 그러지 않으면 같은 이름으로 세션을 다시 만들 때
  # 지난 세션의 원래 탭 이름을 그 세션에 씌운다.
  for key in "${!base_name[@]}"; do
    [ -n "${alive_session[${key%%/*}]:-}" ] || unset 'base_name[$key]' 'prev_suffix[$key]'
  done
  for key in "${!worked[@]}"; do
    [ -n "${alive_session[${key%%/*}]:-}" ] || unset 'worked[$key]'
  done
  for key in "${!session_touched[@]}"; do
    [ -n "${alive_session[$key]:-}" ] || unset 'session_touched[$key]'
  done

  unset alive_session
  sleep "$INTERVAL"
done

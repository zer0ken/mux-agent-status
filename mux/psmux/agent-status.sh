#!/usr/bin/env bash
# agent-status.sh - 에이전트 상태를 window 이름에 밀어 넣는 티커.
#
# psmux 는 pane 과 window 스코프의 사용자 정의 옵션(@foo)을 저장하지 않는다.
# set-option -p 는 에러로 거부하고, set-option -w 는 조용히 버린다. 세션
# 스코프(-p 도 -w 도 없는 set-option)만 저장하고, window-status-format 에서
# #{@foo} 로 읽힌다. 그래서 이 티커는 mux/tmux 처럼 marker 문자열을 옵션에
# 조립해 두고 포맷에서 참조하게 하는 대신, 완성된 집계 문자열을 직접
# window 이름 뒤에 붙인다.
#
# 상태는 에이전트가 스스로 쓴 것을 읽는다. Claude Code 는 세션마다
# ~/.claude/sessions/<pid>.json 을 갱신하고, pi 와 codex 는 이 저장소가 담은
# 확장과 훅이 $TMPDIR/mux-agent-status-<uid>/tmux/<세션>/<에이전트>-<pane>
# 을 갱신한다. psmux 는 tmux CLI 의 별칭이라 TMUX_PANE 을 tmux 와 같은
# 포맷으로 물려주므로, codex 와 pi 는 이미 tmux 서브디렉터리에 쓴다. 이
# 티커는 그 tmux 서브디렉터리 아래를 세션별로 나눠 읽는다.
#
# psmux 는 #{pane_id}(%N) 도 세션마다 따로 1부터 채번해서, 서로 다른
# 세션이 같은 pane 번호를 가질 수 있다. "세션/pane" 을 키로 써서 상태를
# 가른다.
#
# 어휘는 claude-session-manager 와 같다.
#   waiting  입력이 필요하다
#   idle     끝났다, 사용자 차례
#   busy     돌고 있다
#
# window 마다 속한 pane 을 상태별로 세어 `waiting idle busy` 고정 순서로
# marker 와 개수를 늘어놓고, window 이름 뒤에 붙인다. 원래 이름은 window
# 마다 한 번만 기억해 두고, 매 틱마다 "원래 이름 + 집계" 로 다시 조립한다.
# 집계할 것이 없어지면 원래 이름으로 되돌린다.
#
# psmux 는 #{window_id}(@N) 를 세션마다 따로 1부터 채번해서, 서버 전체로는
# 겹칠 수 있다. window 를 가리키는 모든 곳에서 "세션 이름:창 인덱스" 형태의
# 정규 타겟만 쓴다. window_id 나 세션 없는 인덱스만으로 부르면 같은 번호를
# 쓰는 다른 세션의 창이 바뀐다.
set -uo pipefail

INTERVAL=1
STARTUP_TRIES=30

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
STATE_DIR="${TMPDIR:-/tmp}/mux-agent-status-$(id -u)/tmux"

# ANSI 8색 이름을 기본값으로 쓴다. 터미널 테마가 그 색을 정하므로, 이
# 스크립트는 어떤 RGB 값도 강제하지 않는다. 환경변수로 값을 미리 채워 두면
# 이 기본값 대신 그 값을 쓴다(psmux 는 이 값을 옵션으로 저장하지 못하니
# 개인 설정에서 값을 다르게 쓰려면 이 스크립트를 부르기 전에 환경변수로
# 넣어 둔다).
MARKER_WAITING="${MARKER_WAITING:-●}"
MARKER_IDLE="${MARKER_IDLE:-●}"
MARKER_BUSY="${MARKER_BUSY:-●}"
COLOR_WAITING="${COLOR_WAITING:-yellow}"
COLOR_IDLE="${COLOR_IDLE:-green}"
COLOR_BUSY="${COLOR_BUSY:-red}"
COLOR_TEXT="${COLOR_TEXT:-default}"
ORDER=(waiting idle busy)

ready=""
for _ in $(seq "$STARTUP_TRIES"); do
  if tmux list-panes -a -F '#{pane_id}' >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ -n "$ready" ] || exit 0

server_id=${TMUX%,*}; server_id=${server_id##*,}
[ -n "$server_id" ] || server_id=$(tmux display-message -p '#{pid}' 2>/dev/null)
[ -n "$server_id" ] || exit 0

lock_dir="${TMPDIR:-/tmp}/agent-status-psmux-$(id -u)-${server_id}.lockdir"
mkdir "$lock_dir" 2>/dev/null || exit 0    # 이미 돌고 있으면 조용히 끝낸다
trap 'rmdir "$lock_dir" 2>/dev/null' EXIT

# 세션이 한 번도 일한 적 없으면 집계에 넣지 않는다. 띄워만 두고 아무 작업도
# 하지 않은 세션과 방금 응답을 마친 세션이 둘 다 idle 이기 때문이다.
declare -A worked=() base_name=() prev_suffix=()
shopt -s nullglob

while :; do
  declare -A state=()

  # ── Claude Code 세션 파일 ──────────────────────────────────
  for f in "$CLAUDE_DIR"/*.json; do
    c=$(<"$f") || continue
    [[ $c =~ \"kind\":\"interactive\" ]] || continue
    [[ $c =~ \"tmux\":\"([^:\"]*):[^\"]*\.(%[0-9]+)\" ]] || continue
    csess=${BASH_REMATCH[1]}
    pane=${BASH_REMATCH[2]}
    [[ $c =~ \"status\":\"([a-z]+)\" ]] || continue
    st=${BASH_REMATCH[1]}
    case "$st" in waiting|idle|busy) ;; *) continue ;; esac
    state["$csess/$pane"]=$st
  done

  # ── 확장과 훅이 쓴 상태 파일. 프로세스가 죽었으면 파일을 치운다 ──
  # 경로: $STATE_DIR/<세션>/pi-<pane> 또는 codex-<pane>
  for f in "$STATE_DIR"/*/pi-* "$STATE_DIR"/*/codex-*; do
    base=${f##*/}
    fsess=${f%/*}; fsess=${fsess##*/}
    pane="%${base#*-}"
    read -r pst pid 2>/dev/null < "$f" || continue
    if [ -n "${pid:-}" ] && [ "$pid" != 0 ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$f" 2>/dev/null; continue
    fi
    case "$pst" in idle|busy|waiting) state["$fsess/$pane"]=$pst ;; esac
  done

  rows=$(tmux list-panes -a -F '#{pane_id}|#{session_name}|#{window_index}|#{window_name}' 2>/dev/null) || exit 0

  # psmux 는 window_id(@N)를 세션마다 따로 1부터 채번해서, 서버 전체에서 겹칠
  # 수 있다. 세션 이름과 창 인덱스를 합친 "session:index" 를 대신 키로 쓰고,
  # rename-window 도 이 완전한 타겟으로만 부른다. window_id 나 세션 없는 인덱스
  # 만으로 타겟을 지정하면 같은 번호를 쓰는 다른 세션의 창이 바뀔 수 있다.
  declare -A count=() seen=() window_name_now=()
  while IFS='|' read -r pane sname widx wname; do
    [ -n "$pane" ] || continue
    wid="${sname}:${widx}"
    seen[$wid]=1
    window_name_now[$wid]=$wname
    pkey="$sname/$pane"
    st=${state[$pkey]:-}

    case "$st" in
      busy|waiting) worked[$pkey]=1 ;;
      idle) [ -n "${worked[$pkey]:-}" ] || st="" ;;
    esac

    [ -n "$st" ] && count[$wid/$st]=$(( ${count[$wid/$st]:-0} + 1 ))
  done <<< "$rows"

  for wid in "${!seen[@]}"; do
    # window 이름이 바뀌었고, 그 변화가 이 티커 자신이 붙인 접미사를 뗀
    # 결과가 아니면(사용자나 automatic-rename 이 새 이름을 준 것이면),
    # 그 새 이름을 원래 이름으로 다시 채택한다.
    cur_name=${window_name_now[$wid]}
    stripped_of_prev_suffix=$cur_name
    if [ -n "${prev_suffix[$wid]:-}" ]; then
      stripped_of_prev_suffix=${cur_name%" ${prev_suffix[$wid]}"}
    fi
    if [ -z "${base_name[$wid]:-}" ] || [ "$stripped_of_prev_suffix" != "${base_name[$wid]}" ]; then
      base_name[$wid]=$stripped_of_prev_suffix
    fi

    suffix=""
    for s in "${ORDER[@]}"; do
      n=${count[$wid/$s]:-0}
      [ "$n" -gt 0 ] || continue
      case "$s" in
        waiting) m=$MARKER_WAITING; c=$COLOR_WAITING ;;
        idle)    m=$MARKER_IDLE;    c=$COLOR_IDLE ;;
        busy)    m=$MARKER_BUSY;    c=$COLOR_BUSY ;;
      esac
      suffix+="#[fg=$c]${m} ${n}#[fg=$COLOR_TEXT] "
    done
    suffix=${suffix% }

    [ "$suffix" = "${prev_suffix[$wid]:-}" ] && continue

    new_name=${base_name[$wid]}
    [ -n "$suffix" ] && new_name+=" $suffix"
    tmux rename-window -t "$wid" "$new_name" 2>/dev/null
    prev_suffix[$wid]=$suffix
  done

  unset count seen state window_name_now
  sleep "$INTERVAL"
done

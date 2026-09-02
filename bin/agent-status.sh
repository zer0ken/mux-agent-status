#!/usr/bin/env bash
# agent-status.sh - 에이전트 상태를 tmux 옵션으로 밀어 넣는 티커.
#
# 상태는 에이전트가 스스로 쓴 것을 읽는다. Claude Code 는 세션마다
# ~/.claude/sessions/<pid>.json 을 갱신하고, pi 와 codex 는 이 저장소가 담은
# 확장과 훅이 $TMPDIR/tmux-agent-status-<uid>/<에이전트>-<pane> 을 갱신한다.
# 프로세스 탐색은 필요 없다.
#
# 어휘는 claude-session-manager 와 같다.
#   waiting  입력이 필요하다
#   idle     끝났다, 사용자 차례
#   busy     돌고 있다
#
# 내보내는 것
#   @agent_pane_state        pane 하나의 상태 (pane 옵션)
#   @agent_clock             busy 로 있은 시간 (pane 옵션)
#   @agent_window_indicator  marker 와 counter 를 늘어놓은 문자열 (창 옵션)
set -uo pipefail

INTERVAL=1
STARTUP_TRIES=30

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
STATE_DIR="${TMPDIR:-/tmp}/tmux-agent-status-$(id -u)"

# window indicator 에 나오는 순서. 사용자가 먼저 봐야 하는 것이 왼쪽이다.
ORDER=(waiting idle busy)

# marker 의 색과 글리프는 상태마다 따로 정한다. counter 는 색을 비워 두면
# 자기 marker 의 색을 따른다. 매 틱마다 읽으므로 옵션을 바꾸면 바로 반영된다.
declare -A COLOR MARKER
read_options() {
  local v c_wait c_idle c_busy c_text m_wait m_idle m_busy
  v=$(tmux display-message -p '#{@agent_marker_color_waiting}|#{@agent_marker_color_idle}|#{@agent_marker_color_busy}|#{@agent_text_color}|#{@agent_marker_waiting}|#{@agent_marker_idle}|#{@agent_marker_busy}|#{@agent_counter_color}' 2>/dev/null) || return
  IFS='|' read -r c_wait c_idle c_busy c_text m_wait m_idle m_busy COUNTER_COLOR <<< "$v"
  COLOR=(  [waiting]="${c_wait:-#f9e2af}" [idle]="${c_idle:-#a6e3a1}" [busy]="${c_busy:-#f38ba8}" )
  MARKER=( [waiting]="${m_wait:-●}"       [idle]="${m_idle:-●}"       [busy]="${m_busy:-●}" )
  TEXT_COLOR="${c_text:-#cdd6f4}"
}

ready=""
for _ in $(seq "$STARTUP_TRIES"); do
  if tmux list-panes -a -F '#{pane_id}' >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ -n "$ready" ] || exit 0

server_id=${TMUX%,*}; server_id=${server_id##*,}
[ -n "$server_id" ] || server_id=$(tmux display-message -p '#{pid}' 2>/dev/null)
[ -n "$server_id" ] || exit 0

exec 9>"${TMPDIR:-/tmp}/agent-status-$(id -u)-${server_id}.lock" || exit 0
flock -n 9 || exit 0    # 이미 돌고 있으면 조용히 끝낸다

# 세션이 한 번도 일한 적 없으면 indicator 를 달지 않는다. 띄워만 두고 아무 작업도
# 하지 않은 세션과 방금 응답을 마친 세션이 둘 다 idle 이기 때문이다.
declare -A worked=() prev_ind=() since=()
shopt -s nullglob

while :; do
  now=$EPOCHSECONDS
  read_options
  declare -A state=() started=()

  # ── Claude Code 세션 파일 ──────────────────────────────────
  for f in "$CLAUDE_DIR"/*.json; do
    c=$(<"$f") || continue
    [[ $c =~ \"kind\":\"interactive\" ]] || continue
    [[ $c =~ \"tmux\":\"[^\"]*\.(%[0-9]+)\" ]] || continue
    pane=${BASH_REMATCH[1]}
    [[ $c =~ \"status\":\"([a-z]+)\" ]] || continue
    st=${BASH_REMATCH[1]}
    case "$st" in waiting|idle|busy) ;; *) continue ;; esac
    state[$pane]=$st
    if [[ $c =~ \"statusUpdatedAt\":([0-9]+) ]]; then
      started[$pane]=$(( BASH_REMATCH[1] / 1000 ))
    fi
  done

  # ── 확장과 훅이 쓴 상태 파일. 프로세스가 죽었으면 파일을 치운다 ──
  for f in "$STATE_DIR"/pi-* "$STATE_DIR"/codex-*; do
    base=${f##*/}
    pane="%${base#*-}"
    read -r pst pid 2>/dev/null < "$f" || continue
    if [ -n "${pid:-}" ] && [ "$pid" != 0 ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$f" 2>/dev/null; continue
    fi
    case "$pst" in idle|busy|waiting) state[$pane]=$pst ;; esac
  done

  rows=$(tmux list-panes -a -F '#{pane_id}|#{window_id}|#{@agent_pane_state}|#{@agent_clock}' 2>/dev/null) || exit 0

  declare -A count=() seen=()
  changed=""
  while IFS='|' read -r pane wid cur_state cur_el; do
    [ -n "$pane" ] || continue
    seen[$wid]=1
    st=${state[$pane]:-}

    case "$st" in
      busy|waiting) worked[$pane]=1 ;;
      idle) [ -n "${worked[$pane]:-}" ] || st="" ;;
    esac

    if [ "$st" = busy ]; then
      [ -n "${started[$pane]:-}" ] && since[$pane]=${started[$pane]}
      [ -n "${since[$pane]:-}" ] || since[$pane]=$now
      s=$(( now - since[$pane] )); [ "$s" -lt 0 ] && s=0
      if   [ "$s" -lt 60 ];   then el="${s}s "
      elif [ "$s" -lt 3600 ]; then el="$(( s / 60 ))m "
      else                         el="$(( s / 3600 ))h "; fi
    else
      unset 'since[$pane]'; el=""
    fi

    [ "$st" != "$cur_state" ] && {
      if [ -n "$st" ]; then tmux set-option -p -t "$pane" @agent_pane_state "$st" 2>/dev/null
      else tmux set-option -p -t "$pane" -u @agent_pane_state 2>/dev/null; fi
      changed=1
    }
    [ "$el" != "$cur_el" ] && {
      if [ -n "$el" ]; then tmux set-option -p -t "$pane" @agent_clock "$el" 2>/dev/null
      else tmux set-option -p -t "$pane" -u @agent_clock 2>/dev/null; fi
      changed=1
    }

    [ -n "$st" ] && count[$wid/$st]=$(( ${count[$wid/$st]:-0} + 1 ))
  done <<< "$rows"

  for wid in "${!seen[@]}"; do
    ind=""
    for s in "${ORDER[@]}"; do
      n=${count[$wid/$s]:-0}
      [ "$n" -gt 0 ] || continue
      if [ -n "${COUNTER_COLOR:-}" ]; then
      ind+="#[fg=${COLOR[$s]}]${MARKER[$s]} #[fg=$COUNTER_COLOR]$n "
    else
      ind+="#[fg=${COLOR[$s]}]${MARKER[$s]} $n "
    fi
    done
    [ -n "$ind" ] && ind+="#[fg=$TEXT_COLOR]"
    [ "$ind" = "${prev_ind[$wid]:-}" ] && continue
    if [ -n "$ind" ]; then tmux set-option -w -t "$wid" @agent_window_indicator "$ind" 2>/dev/null
    else tmux set-option -w -t "$wid" -u @agent_window_indicator 2>/dev/null; fi
    prev_ind[$wid]=$ind
    changed=1
  done

  [ -n "$changed" ] && tmux refresh-client -S 2>/dev/null
  unset count seen state started
  sleep "$INTERVAL"
done

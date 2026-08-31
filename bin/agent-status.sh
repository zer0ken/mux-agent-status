#!/usr/bin/env bash
# agent-status.sh - 에이전트 상태를 tmux 옵션으로 밀어 넣는 티커.
#
# 상태는 에이전트가 스스로 쓴 것을 읽는다. Claude Code 는 세션마다
# ~/.claude/sessions/<pid>.json 을 갱신하고, pi 는 pi-tmux-status 확장이
# /tmp/pi-tmux-<pane>.txt 를 갱신한다. 훅도 프로세스 탐색도 필요 없다.
#
# 어휘는 claude-session-manager 와 같다.
#   waiting  입력이 필요하다
#   idle     끝났다, 사용자 차례
#   busy     돌고 있다
#
# 내보내는 것
#   @agent_pane_state  pane 하나의 상태 (pane 옵션)
#   @agent_elapsed     busy 로 있은 시간 (pane 옵션)
#   @agent_win_badge   창 안 상태별 개수를 그린 문자열 (창 옵션)
set -uo pipefail

INTERVAL=1
STARTUP_TRIES=30

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
PI_DIR=/tmp
PI_PREFIX=pi-tmux-
TEXT_FG="#cdd6f4"

# 창 요약에 나오는 순서. 사용자가 먼저 봐야 하는 것이 왼쪽이다.
ORDER=(waiting idle busy)

# 색과 글리프는 tmux 옵션으로 바꾼다. 기본값은 claude-session-manager 와 같은
# 뜻이고 catppuccin mocha 팔레트를 쓴다. 시작할 때 한 번만 읽는다.
declare -A GLYPH COLOR
_v=$(tmux display-message -p '#{@agent_color_waiting}|#{@agent_color_idle}|#{@agent_color_busy}|#{@agent_color_text}|#{@agent_glyph}' 2>/dev/null)
IFS='|' read -r c_wait c_idle c_busy c_text glyph <<< "$_v"
COLOR=( [waiting]="${c_wait:-#f9e2af}" [idle]="${c_idle:-#a6e3a1}" [busy]="${c_busy:-#f38ba8}" )
TEXT_FG="${c_text:-$TEXT_FG}"
glyph="${glyph:-●}"
GLYPH=( [waiting]="$glyph" [idle]="$glyph" [busy]="$glyph" )

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

# 세션이 한 번도 일한 적 없으면 배지를 달지 않는다. 띄워만 두고 아무 작업도
# 하지 않은 세션과 방금 응답을 마친 세션이 둘 다 idle 이기 때문이다.
declare -A worked=() prev_win=() since=()
shopt -s nullglob

while :; do
  now=$EPOCHSECONDS
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

  # ── pi 상태 파일. 프로세스가 죽었으면 파일을 치운다 ────────
  for f in "$PI_DIR/$PI_PREFIX"*.txt; do
    pane=${f##*/$PI_PREFIX}; pane=${pane%.txt}
    read -r pst pid 2>/dev/null < "$f" || continue
    if [ -n "${pid:-}" ] && [ "$pid" != 0 ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$f" 2>/dev/null; continue
    fi
    case "$pst" in
      working) state[$pane]=busy ;;
      asking)  state[$pane]=waiting ;;
      idle)    state[$pane]=idle ;;
    esac
  done

  rows=$(tmux list-panes -a -F '#{pane_id}|#{window_id}|#{@agent_pane_state}|#{@agent_elapsed}' 2>/dev/null) || exit 0

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
      if [ -n "$el" ]; then tmux set-option -p -t "$pane" @agent_elapsed "$el" 2>/dev/null
      else tmux set-option -p -t "$pane" -u @agent_elapsed 2>/dev/null; fi
      changed=1
    }

    [ -n "$st" ] && count[$wid/$st]=$(( ${count[$wid/$st]:-0} + 1 ))
  done <<< "$rows"

  for wid in "${!seen[@]}"; do
    badge=""
    for s in "${ORDER[@]}"; do
      n=${count[$wid/$s]:-0}
      [ "$n" -gt 0 ] || continue
      badge+="#[fg=${COLOR[$s]}]${GLYPH[$s]} $n "
    done
    [ -n "$badge" ] && badge+="#[fg=$TEXT_FG]"
    [ "$badge" = "${prev_win[$wid]:-}" ] && continue
    if [ -n "$badge" ]; then tmux set-option -w -t "$wid" @agent_win_badge "$badge" 2>/dev/null
    else tmux set-option -w -t "$wid" -u @agent_win_badge 2>/dev/null; fi
    prev_win[$wid]=$badge
    changed=1
  done

  [ -n "$changed" ] && tmux refresh-client -S 2>/dev/null
  unset count seen state started
  sleep "$INTERVAL"
done

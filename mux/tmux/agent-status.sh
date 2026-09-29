#!/usr/bin/env bash
# agent-status.sh - 에이전트 상태를 tmux 옵션으로 밀어 넣는 티커.
#
# 상태는 에이전트가 스스로 쓴 것을 읽는다. Claude Code 는 세션마다
# ~/.claude/sessions/<pid>.json 을 갱신하고, pi 와 codex 는 이 저장소가 담은
# 확장과 훅이 $TMPDIR/mux-agent-status[-<uid>]/<mux>/<세션>/<에이전트>-<pane>
# 을 갱신한다. 이 티커는 자기 몫인 tmux 서브디렉터리 아래를 세션 구분 없이
# 다 읽는다. tmux 의 pane_id 는 서버 전체에서 고유해서 어느 세션 아래
# 있었는지는 상관없다. psmux 는 tmux CLI 의 별칭이라 같은 서브디렉터리를
# 쓴다. 프로세스 탐색은 필요 없다.
#
# 어휘는 claude-session-manager 와 같다.
#   waiting  입력이 필요하다
#   idle     끝났다, 사용자 차례
#   busy     돌고 있다
#
# window indicator 는 창 이름 뒤에 온다. tmux 는 창 이름을 건드리지 않고도
# 포맷에서 뒤에 이어 붙일 수 있어서, 이름을 고쳐 쓰는 psmux 와 zellij 티커와
# 달리 automatic-rename 을 그대로 둔다. 그 자리를 티커가 직접 확보한다.
#
# 내보내는 것
#   @agent_pane_state        pane 하나의 상태 (pane 옵션)
#   @agent_clock             busy 로 있은 시간 (pane 옵션)
#   @agent_window_indicator  marker 와 counter 를 늘어놓은 문자열 (창 옵션)
set -uo pipefail

INTERVAL=1
STARTUP_TRIES=30

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
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
STATE_DIR="$STATE_ROOT/tmux"

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

# window indicator 에 나오는 순서. 사용자가 먼저 봐야 하는 것이 왼쪽이다.
ORDER=(waiting idle busy)

# marker 의 색과 글리프는 상태마다 따로 정한다. counter 는 색을 비워 두면
# 자기 marker 의 색을 따른다. compact 형식은 counter 를 윗첨자로 바꾸고
# marker 에 붙인다. 매 틱마다 읽으므로 옵션을 바꾸면 바로 반영된다.
declare -A COLOR MARKER
read_options() {
  local v c_wait c_idle c_busy c_text m_wait m_idle m_busy
  v=$(tmux display-message -p '#{@agent_marker_color_waiting}|#{@agent_marker_color_idle}|#{@agent_marker_color_busy}|#{@agent_text_color}|#{E:@agent_window_marker_waiting}|#{E:@agent_window_marker_idle}|#{E:@agent_window_marker_busy}|#{@agent_counter_color}|#{@agent_window_format}' 2>/dev/null) || return
  IFS='|' read -r c_wait c_idle c_busy c_text m_wait m_idle m_busy COUNTER_COLOR WINDOW_FORMAT <<< "$v"
  COLOR=(  [waiting]="${c_wait:-#f9e2af}" [idle]="${c_idle:-#a6e3a1}" [busy]="${c_busy:-#f38ba8}" )
  MARKER=( [waiting]="$m_wait" [idle]="$m_idle" [busy]="$m_busy" )
  TEXT_COLOR="${c_text:-#cdd6f4}"
  case "$WINDOW_FORMAT" in default|compact) ;; *) WINDOW_FORMAT=default ;; esac
}

superscript() {
  SUPERSCRIPT=$1
  SUPERSCRIPT=${SUPERSCRIPT//0/⁰}
  SUPERSCRIPT=${SUPERSCRIPT//1/¹}
  SUPERSCRIPT=${SUPERSCRIPT//2/²}
  SUPERSCRIPT=${SUPERSCRIPT//3/³}
  SUPERSCRIPT=${SUPERSCRIPT//4/⁴}
  SUPERSCRIPT=${SUPERSCRIPT//5/⁵}
  SUPERSCRIPT=${SUPERSCRIPT//6/⁶}
  SUPERSCRIPT=${SUPERSCRIPT//7/⁷}
  SUPERSCRIPT=${SUPERSCRIPT//8/⁸}
  SUPERSCRIPT=${SUPERSCRIPT//9/⁹}
}

# window indicator 를 창 이름 뒤에 놓는다. 사용자가 포맷을 다시 정하면 이어
# 붙인 것이 사라지므로 매 틱마다 확인한다. 이미 어딘가에서 indicator 를
# 참조하는 포맷은 사용자가 자리를 정한 것이라 건드리지 않는다. indicator 는 앞뒤
# 공백을 포함하지 않으므로 창 이름과의 공백은 indicator 가 있을 때만 붙인다.
ensure_format() {
  local opt cur
  for opt in window-status-format window-status-current-format; do
    cur=$(tmux show-options -gv "$opt" 2>/dev/null) || continue
    case "$cur" in *@agent_window_indicator*) continue ;; esac
    tmux set-option -g "$opt" "${cur}#{?#{==:#{E:@agent_window_indicator},},, #{E:@agent_window_indicator}}" 2>/dev/null
  done
}

ready=""
for _ in $(seq "$STARTUP_TRIES"); do
  if tmux list-panes -a -F '#{pane_id}' >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ -n "$ready" ] || exit 0

# 티커는 pane 밖에서도 뜨므로 TMUX 가 없을 수 있다. set -u 아래에서 그대로
# 펼치면 아래의 폴백에 닿기 전에 죽는다.
server_id=${TMUX:-}; server_id=${server_id%,*}; server_id=${server_id##*,}
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
  ensure_format
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
  for f in "$STATE_DIR"/*/pi-* "$STATE_DIR"/*/codex-*; do
    base=${f##*/}
    pane="%${base#*-}"
    read -r pst pid 2>/dev/null < "$f" || continue
    if [ -n "${pid:-}" ] && [ "$pid" != 0 ] && ! pid_alive "$pid"; then
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
      if   [ "$s" -lt 60 ];   then el="${s}s"
      elif [ "$s" -lt 3600 ]; then el="$(( s / 60 ))m"
      else                         el="$(( s / 3600 ))h"; fi
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
      if [ "$WINDOW_FORMAT" = compact ]; then
        superscript "$n"
        counter=$SUPERSCRIPT
        gap=
      else
        counter=$n
        gap=" "
      fi
      part=""
      if [ -n "${COUNTER_COLOR:-}" ]; then
        if [ -n "${MARKER[$s]}" ]; then
          part+="#[fg=${COLOR[$s]}]${MARKER[$s]}${gap}"
        fi
        part+="#[fg=$COUNTER_COLOR]${counter}#[fg=$TEXT_COLOR]"
      else
        if [ -n "${MARKER[$s]}" ]; then
          part+="#[fg=${COLOR[$s]}]${MARKER[$s]}${gap}${counter}#[fg=$TEXT_COLOR]"
        else
          part+="#[fg=${COLOR[$s]}]${counter}#[fg=$TEXT_COLOR]"
        fi
      fi
      # 상태 묶음 사이에만 공백을 둔다. indicator 앞뒤 여백은 포맷이 정한다.
      ind+="${ind:+ }$part"
    done
    [[ ${prev_ind[$wid]+set} ]] && [ "$ind" = "${prev_ind[$wid]}" ] && continue
    if [ -n "$ind" ]; then tmux set-option -w -t "$wid" @agent_window_indicator "$ind" 2>/dev/null
    else tmux set-option -w -t "$wid" -u @agent_window_indicator 2>/dev/null; fi
    prev_ind[$wid]=$ind
    changed=1
  done

  [ -n "$changed" ] && tmux refresh-client -S 2>/dev/null
  unset count seen state started
  sleep "$INTERVAL"
done

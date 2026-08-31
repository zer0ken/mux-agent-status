#!/usr/bin/env bash
# tmux-agent-status 진입점. tmux.conf 에서 이 파일을 부른다.
#
#   run-shell "~/tmux-agent-status/tmux/agent-status.tmux"
#
# 기본값은 set -gq 라서 tmux.conf 에서 미리 정한 값이 우선한다.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 색의 뜻은 claude-session-manager 의 세션 피커와 같다.
tmux set -gq @agent_color_waiting "#f9e2af"
tmux set -gq @agent_color_idle    "#a6e3a1"
tmux set -gq @agent_color_busy    "#f38ba8"
tmux set -gq @agent_color_text    "#cdd6f4"
tmux set -gq @agent_glyph         "●"

# pane 하나의 상태를 그리는 배지. pane-border-format 에 끼워 쓴다.
# busy 는 점 뒤에 경과 시간이 붙는다.
badge=""
for st in waiting idle busy; do
  if [ "$st" = busy ]; then
    body='#{@agent_glyph} #{@agent_elapsed}'
  else
    body='#{@agent_glyph} '
  fi
  badge+="#{?#{==:#{@agent_pane_state},$st},#[fg=#{@agent_color_$st}]$body#[fg=#{@agent_color_text}],"
done
badge+="}}}"
tmux set -gq @agent_badge_pane "$badge"

# 티커는 tmux 의 감시 밖에서 띄운다. run-shell 로 띄우면 tmux 가 그 프로세스를
# 계속 지켜보다가 종료 시그널을 받고 죽을 때 오류 창을 띄운다. 티커는 서버가
# 살아 있는 내내 도는 프로세스라 언젠가는 반드시 그렇게 끝난다.
setsid "$DIR/../bin/agent-status.sh" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

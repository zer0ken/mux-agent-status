#!/usr/bin/env bash
# tmux-agent-status 진입점. tmux.conf 에서 이 파일을 부른다.
#
#   run-shell "~/tmux-agent-status/tmux/agent-status.tmux"
#
# 기본값은 set -ogq 로 넣는다. -o 는 이미 정해진 옵션을 건드리지 않으므로
# tmux.conf 에서 미리 정한 값이 우선한다.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 색의 뜻은 claude-session-manager 의 세션 피커와 같다.
tmux set -ogq @agent_marker_color_waiting "#f9e2af"
tmux set -ogq @agent_marker_color_idle    "#a6e3a1"
tmux set -ogq @agent_marker_color_busy    "#f38ba8"
tmux set -ogq @agent_text_color    "#cdd6f4"

# marker 는 상태마다 따로 정한다. @agent_marker 를 미리 정해 두면 세 상태의
# 기본값이 한꺼번에 바뀐다.
base=$(tmux show-option -gqv @agent_marker 2>/dev/null)
base=${base:-●}
tmux set -ogq @agent_marker         "$base"
tmux set -ogq @agent_marker_waiting "$base"
tmux set -ogq @agent_marker_idle    "$base"
tmux set -ogq @agent_marker_busy    "$base"

# counter 와 clock 은 색을 비워 두면 자기 marker 의 색을 따른다.
tmux set -ogq @agent_counter_color ""
tmux set -ogq @agent_clock_color   ""

# pane indicator. pane-border-format 에 끼워 쓴다. marker 하나로 그 pane 의
# 상태를 나타내고, busy 이면 뒤에 clock 이 붙는다. 색과 글리프는 값을 박지 않고
# 옵션을 가리키므로, 옵션을 바꾸면 다음 화면 갱신에 바로 반영된다.
clock="#{?#{@agent_clock_color},#[fg=#{@agent_clock_color}],}#{@agent_clock}"

ind=""
for st in waiting idle busy; do
  if [ "$st" = busy ]; then
    body="#{@agent_marker_$st} $clock"
  else
    body="#{@agent_marker_$st} "
  fi
  ind+="#{?#{==:#{@agent_pane_state},$st},#[fg=#{@agent_marker_color_$st}]$body#[fg=#{@agent_text_color}],"
done
ind+="}}}"
tmux set -ogq @agent_pane_indicator "$ind"

# 티커는 tmux 의 감시 밖에서 띄운다. run-shell 로 띄우면 tmux 가 그 프로세스를
# 계속 지켜보다가 종료 시그널을 받고 죽을 때 오류 창을 띄운다. 티커는 서버가
# 살아 있는 내내 도는 프로세스라 언젠가는 반드시 그렇게 끝난다.
setsid "$DIR/../bin/agent-status.sh" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

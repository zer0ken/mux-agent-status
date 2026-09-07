#!/usr/bin/env bash
# mux-agent-status 의 psmux 진입점. psmux.conf 에서 이 파일을 부른다.
#
#   run-shell "~/mux-agent-status/mux/psmux/agent-status.tmux"
#
# psmux 는 pane 과 window 스코프의 사용자 정의 옵션을 저장하지 않으므로,
# mux/tmux 의 진입점과 달리 색과 글리프를 옵션으로 내보내지 않는다. 티커가
# 스스로 정한 marker 를 window 이름에 직접 새겨 넣는다.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 티커는 psmux 의 감시 밖에서 띄운다. run-shell 로 띄우면 psmux 가 그
# 프로세스를 계속 지켜보다가 종료 시그널을 받고 죽을 때 오류 창을 띄운다.
# 티커는 서버가 살아 있는 내내 도는 프로세스라 언젠가는 반드시 그렇게 끝난다.
setsid "$DIR/agent-status.sh" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

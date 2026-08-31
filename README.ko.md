# tmux-agent-status

[English](README.md)

tmux-agent-status 는 tmux 상태바에 Claude Code 와 pi 세션의 상태를 표시한다.
창을 여러 개 열어 두었을 때 어느 창이 입력을 기다리는지, 어느 창이 아직 돌고
있는지를 창을 옮기지 않고 알 수 있다.

## 상태 구분

상태는 세 가지다. 어휘와 색은 claude-session-manager 의 세션 피커와 같아서,
피커와 상태바가 같은 뜻으로 읽힌다. 기본 팔레트는 catppuccin mocha 다.

| 상태 | 색 | 뜻 |
| --- | --- | --- |
| `waiting` | ![f9e2af](https://img.shields.io/badge/waiting-%23f9e2af-f9e2af?style=flat-square&labelColor=313244) | 세션이 입력을 기다린다 |
| `idle` | ![a6e3a1](https://img.shields.io/badge/idle-%23a6e3a1-a6e3a1?style=flat-square&labelColor=313244) | 세션이 응답을 마쳤다 |
| `busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | 세션이 돌고 있다 |

방금 띄워 아직 아무 작업도 하지 않은 세션은 상태바에 나오지 않는다. Claude Code
가 그런 세션과 응답을 마친 세션에 똑같이 `idle` 을 주므로, tmux-agent-status 는
`busy` 나 `waiting` 을 한 번이라도 거친 세션만 `idle` 로 표시한다.

## indicator 구성

tmux-agent-status 가 내보내는 indicator 는 두 가지다. window indicator 는 창
하나를, pane indicator 는 pane 하나를 나타낸다. indicator 를 이루는 부분에는
각각 이름이 있다.

| 이름 | 나오는 곳 | 뜻 |
| --- | --- | --- |
| marker | 두 indicator | 상태를 색과 글리프로 나타내는 점 |
| counter | window indicator | 그 상태인 pane 의 수 |
| clock | pane indicator | 세션이 `busy` 로 있은 시간 |

window indicator 는 창에 속한 pane 을 상태별로 세어 marker 와 counter 를 짝지어
늘어놓는다. 순서는 `waiting`, `idle`, `busy` 로 고정이고, 한 개도 없는 상태는
빠진다.

```
 2  ● 1 ● 2  claude
```

pane indicator 는 그 pane 하나의 marker 를 보여준다. 상태가 `busy` 이면 marker
뒤에 clock 이 붙는다.

```
 1  ● 49s  Jupiter tmux 커스텀
```

## 설치

```bash
git clone https://github.com/zer0ken/tmux-agent-status.git ~/tmux-agent-status
```

tmux.conf 에 진입점을 부르는 한 줄을 넣는다. 진입점은 옵션의 기본값을 채우고
티커를 띄운다. 티커는 상태를 읽어 tmux 옵션으로 옮기는 백그라운드 프로세스다.

```tmux
run-shell "~/tmux-agent-status/tmux/agent-status.tmux"
```

진입점은 indicator 를 옵션에 넣어 둘 뿐 상태바 포맷을 대신 고치지 않는다.
사용자가 쓰던 포맷에 indicator 를 직접 끼워 넣는다.

```tmux
set -g window-status-format "#I #{E:@agent_window_indicator}#W"
set -wg pane-border-format  "#{pane_index} #{E:@agent_pane_indicator}#{pane_title}"
```

## pi 연동

pi 는 실행 중인 세션의 목록도 상태 파일도 내보내지 않는다. 그래서 이 저장소가
상태를 기록하는 pi 확장을 함께 담고 있다. 확장은 pi 로 설치하고, 다른 패키지는
필요 없다.

```bash
pi install git:github.com/zer0ken/tmux-agent-status
```

확장은 상태가 바뀔 때마다 `$TMPDIR/tmux-agent-status-<uid>/pi-<pane>` 에
`<상태> <pid>` 를 쓰고, 세션이 끝나면 그 파일을 지운다. 상태 이름은
tmux-agent-status 의 나머지와 같아서 중간에 옮겨 적는 과정이 없다.

## 옵션

옵션은 값을 바꾸면 1초 안에 반영된다. tmux.conf 에서 진입점보다 먼저 정한 값이
우선한다. 진입점이 기본값을 `set -ogq` 로 넣기 때문이다.

| 옵션 | 기본값 | 뜻 |
| --- | --- | --- |
| `@agent_marker` | `●` | 세 상태의 기본 marker |
| `@agent_marker_waiting` | `@agent_marker` | `waiting` 의 marker |
| `@agent_marker_idle` | `@agent_marker` | `idle` 의 marker |
| `@agent_marker_busy` | `@agent_marker` | `busy` 의 marker |
| `@agent_marker_color_waiting` | ![f9e2af](https://img.shields.io/badge/waiting-%23f9e2af-f9e2af?style=flat-square&labelColor=313244) | `waiting` marker 의 색 |
| `@agent_marker_color_idle` | ![a6e3a1](https://img.shields.io/badge/idle-%23a6e3a1-a6e3a1?style=flat-square&labelColor=313244) | `idle` marker 의 색 |
| `@agent_marker_color_busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | `busy` marker 의 색 |
| `@agent_counter_color` | 비움 | counter 의 색. 비우면 marker 색을 따른다 |
| `@agent_clock_color` | 비움 | clock 의 색. 비우면 marker 색을 따른다 |
| `@agent_text_color` | ![cdd6f4](https://img.shields.io/badge/text-%23cdd6f4-cdd6f4?style=flat-square&labelColor=313244) | indicator 뒤에 오는 글자의 색 |

## 동작 원리

상태는 에이전트가 스스로 기록한 것을 읽는다. tmux-agent-status 는 Claude Code
훅을 걸지 않고 프로세스 목록을 뒤지지도 않는다.

| 에이전트 | 상태 파일 |
| --- | --- |
| Claude Code | `~/.claude/sessions/<pid>.json` |
| pi | `$TMPDIR/tmux-agent-status-<uid>/pi-<pane>` |

Claude Code 의 세션 파일에는 그 세션이 붙어 있는 pane 의 id 가 `tmux` 필드로
들어 있어서, pid 를 tty 로 옮기고 다시 pane 으로 옮기는 과정이 필요 없다.
파일이 한 줄짜리 JSON 이라 bash 정규식만으로 읽히고, 이 과정에서 프로세스가
하나도 뜨지 않는다.

`bin/agent-status.sh` 가 티커다. 1초마다 돌면서 tmux 포맷만으로는 할 수 없는 두
가지를 맡는다.

- 상태 파일을 읽어 pane 옵션으로 옮긴다
- 창에 속한 pane 을 상태별로 센다

티커는 값이 바뀐 pane 과 창에만 옵션을 쓴다. tmux 서버마다 하나만 돌고 서버가
끝나면 함께 끝난다.

## 제약

**중단과 완료를 구분하지 않는다.** Claude Code 는 사용자가 중단한 세션과
응답을 마친 세션을 모두 `idle` 로 보고한다. 두 경우 모두 초록 점으로 나온다.
Claude Code 가 상태를 하나만 주므로 이 구분을 만들 방법이 없다.

**세션 파일의 경로는 공개된 인터페이스가 아니다.** `~/.claude/sessions` 는
Claude Code 의 내부 구조이고 버전이 올라가면 바뀔 수 있다. 파일을 못 읽게 되면
Claude 세션의 indicator 만 사라지고 pi 세션과 tmux 는 그대로 동작한다. 같은 값을
`claude agents --json` 이 공개 인터페이스로 내보내므로, 티커가 그 명령을 쓰도록
고치면 다시 동작한다. 이 명령은 호출당 400밀리초가 들어서 폴링 주기를 함께
늘려야 한다.

## 요구 사항

- tmux 3.2 이상
- bash 5.0 이상
- Claude Code 2.1 이상

## 라이선스

MIT

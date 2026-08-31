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
| `busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | 세션이 돌고 있다. 경과 시간이 함께 나온다 |

세션을 띄우고 아직 아무 작업도 하지 않은 동안에는 배지가 붙지 않는다.
`idle` 은 응답을 마친 세션과 한 번도 일한 적 없는 세션이 같은 값이므로,
tmux-agent-status 는 `busy` 나 `waiting` 을 한 번이라도 거친 세션만 `idle` 로
표시한다.

## 표시 위치

창 탭에는 그 창에 속한 pane 을 상태별로 센 개수가 나온다. 순서는 고정이고,
사용자가 먼저 봐야 하는 상태가 왼쪽에 온다.

```
 2  ● 1 ● 2  claude
```

pane 제목에는 그 pane 하나의 상태가 나온다. `busy` 이면 그 상태로 있은 시간이
뒤에 붙는다.

```
 1  ● 49s  Jupiter tmux 커스텀
```

## 설치

tmux-agent-status 는 Claude Code 훅을 쓰지 않는다. install.sh 는 이전 판이
남긴 훅만 걷어내므로, 새로 설치하는 경우에는 실행하지 않아도 된다.

```bash
git clone https://github.com/zer0ken/tmux-agent-status.git ~/tmux-agent-status
```

tmux.conf 에 진입점을 부르는 한 줄을 넣는다. 진입점은 옵션의 기본값을 채우고
티커를 띄운다.

```tmux
run-shell "~/tmux-agent-status/tmux/agent-status.tmux"
```

진입점은 배지 문자열을 옵션에 넣어 둘 뿐 상태바 포맷을 대신 고치지 않는다.
배지는 쓰던 포맷에 직접 끼워 넣는다.

```tmux
set -g window-status-format "#I #{E:@agent_win_badge}#W"
set -wg pane-border-format  "#{pane_index} #{E:@agent_badge_pane}#{pane_title}"
```

## pi 연동

pi 세션의 상태는 pi-tmux-status 확장이 `/tmp/pi-tmux-<pane>.txt` 에 쓴 값을
읽어서 가져온다. pi 를 쓰면 이 확장을 함께 설치한다.

```bash
pi install npm:pi-tmux-status
```

pi 의 `working` 은 `busy` 로, `asking` 은 `waiting` 으로, `idle` 은 `idle` 로
대응한다.

## 옵션

색과 글리프는 티커가 시작할 때 한 번 읽는다. 값을 바꾼 뒤에는 tmux 설정을
다시 읽어야 반영된다.

| 옵션 | 기본값 | 뜻 |
| --- | --- | --- |
| `@agent_color_waiting` | ![f9e2af](https://img.shields.io/badge/waiting-%23f9e2af-f9e2af?style=flat-square&labelColor=313244) | `waiting` 의 색 |
| `@agent_color_idle` | ![a6e3a1](https://img.shields.io/badge/idle-%23a6e3a1-a6e3a1?style=flat-square&labelColor=313244) | `idle` 의 색 |
| `@agent_color_busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | `busy` 의 색 |
| `@agent_color_text` | ![cdd6f4](https://img.shields.io/badge/text-%23cdd6f4-cdd6f4?style=flat-square&labelColor=313244) | 배지 뒤에 오는 글자의 색 |
| `@agent_glyph` | `●` | 세 상태가 함께 쓰는 글리프 |

## 동작 원리

상태는 에이전트가 스스로 기록한 것을 읽는다. Claude Code 는 세션마다
`~/.claude/sessions/<pid>.json` 을 갱신하고, pi 는 pi-tmux-status 확장이
`/tmp/pi-tmux-<pane>.txt` 를 갱신한다. tmux-agent-status 는 훅을 걸지 않고
프로세스를 뒤지지도 않는다.

Claude Code 의 세션 파일에는 그 세션이 붙어 있는 pane 의 id 가 `tmux` 필드로
들어 있어서, pid 를 tty 로 옮기고 다시 pane 으로 옮기는 과정이 필요 없다.
파일이 한 줄짜리 JSON 이라 bash 정규식만으로 읽히고, 이 과정에서 프로세스가
하나도 뜨지 않는다.

`bin/agent-status.sh` 는 1초마다 도는 티커다. tmux 포맷만으로는 할 수 없는 두
가지를 맡는다.

- 상태 파일을 읽어 pane 옵션으로 옮기는 이관
- 창에 속한 pane 을 상태별로 세는 집계

티커는 값이 바뀌지 않으면 tmux 를 호출하지 않는다. tmux 서버마다 하나만 돌고
서버가 끝나면 함께 끝난다.

## 제약

**중단과 완료를 구분하지 않는다.** Claude Code 는 사용자가 중단한 세션과
응답을 마친 세션을 모두 `idle` 로 보고한다. 두 경우 모두 초록 점으로 나온다.
Claude Code 가 상태를 하나만 주므로 이 구분을 만들 방법이 없다.

**세션 파일의 경로는 공개된 인터페이스가 아니다.** `~/.claude/sessions` 는
Claude Code 의 내부 구조이고 버전이 올라가면 바뀔 수 있다. 파일을 못 읽게 되면
Claude 세션의 배지만 사라지고 pi 세션과 tmux 는 그대로 동작한다. 같은 값을
`claude agents --json` 이 공개 인터페이스로 내보내므로, 그때는 티커가 그 명령을
쓰도록 바꾸면 된다. 이 명령은 호출당 400밀리초가 들어서 폴링 주기를 함께
늘려야 한다.

## 요구 사항

- tmux 3.2 이상
- bash 5.0 이상
- Claude Code 2.1 이상

## 라이선스

MIT

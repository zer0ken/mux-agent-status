# mux-agent-status

[English](README.md)

mux-agent-status 는 tmux 와 psmux 의 상태바에 Claude Code, codex, pi 세션의
상태를 표시한다. 창을 여러 개 열어 두었을 때 어느 창이 입력을 기다리는지,
어느 창이 아직 돌고 있는지를 창을 옮기지 않고 알 수 있다.

## 상태 구분

상태는 세 가지다. 어휘와 색은 claude-session-manager 의 세션 피커와 같아서,
피커와 상태바가 같은 뜻으로 읽힌다. 기본 팔레트는 catppuccin mocha 다.

| 상태 | 색 | 뜻 |
| --- | --- | --- |
| `waiting` | ![f9e2af](https://img.shields.io/badge/waiting-%23f9e2af-f9e2af?style=flat-square&labelColor=313244) | 세션이 입력을 기다린다 |
| `idle` | ![a6e3a1](https://img.shields.io/badge/idle-%23a6e3a1-a6e3a1?style=flat-square&labelColor=313244) | 세션이 응답을 마쳤다 |
| `busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | 세션이 돌고 있다 |

방금 띄워 아직 아무 작업도 하지 않은 세션은 상태바에 나오지 않는다. Claude Code
가 그런 세션과 응답을 마친 세션에 똑같이 `idle` 을 주므로, mux-agent-status 는
`busy` 나 `waiting` 을 한 번이라도 거친 세션만 `idle` 로 표시한다.

## indicator 구성

mux-agent-status 가 내보내는 indicator 는 두 가지다. window indicator 는 창
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
git clone https://github.com/zer0ken/mux-agent-status.git ~/mux-agent-status
```

tmux.conf 에 진입점을 부르는 한 줄을 넣는다. 진입점은 옵션의 기본값을 채우고
티커를 띄운다. 티커는 상태를 읽어 tmux 옵션으로 옮기는 백그라운드 프로세스다.

```tmux
run-shell "~/mux-agent-status/mux/tmux/agent-status.tmux"
```

진입점은 indicator 를 옵션에 넣어 둘 뿐 상태바 포맷을 대신 고치지 않는다.
사용자가 쓰던 포맷에 indicator 를 직접 끼워 넣는다.

```tmux
set -g window-status-format "#I #{E:@agent_window_indicator}#W"
set -wg pane-border-format  "#{pane_index} #{E:@agent_pane_indicator}#{pane_title}"
```

psmux 는 사용자 정의 옵션의 pane 과 창 스코프를 저장하지 않아 이 방식을
그대로 쓸 수 없다. `psmux.conf` 에는 별도 진입점을 넣는다.

```tmux
run-shell "~/mux-agent-status/mux/psmux/agent-status.tmux"
```

psmux 쪽 티커는 옵션에 넣어 두고 참조하는 대신, 완성된 집계 문자열을 창
이름 뒤에 직접 붙인다. 원래 창 이름은 그대로 두고 상태바 포맷을 고칠 자리도
없어서, 설치 외에 추가로 손볼 곳이 없다.

## pi 연동

pi 는 실행 중인 세션의 목록도 상태 파일도 내보내지 않는다. 그래서 이 저장소가
상태를 기록하는 pi 확장을 함께 담고 있다. 확장은 pi 로 설치하고, 다른 패키지는
필요 없다.

```bash
pi install git:github.com/zer0ken/mux-agent-status
```

확장은 pi 프로세스 환경에서 mux 와 세션을 판별해, 상태가 바뀔 때마다
`$TMPDIR/mux-agent-status-<uid>/<mux>/<세션>/pi-<pane>` 에 `<상태> <pid>` 를
쓰고, 세션이 끝나면 그 파일을 지운다. mux 와 세션을 판별하는 방법, pane
표기는 [동작 원리](#동작-원리)에 있다. 상태 이름은 mux-agent-status 의
나머지와 같아서 중간에 옮겨 적는 과정이 없다.

## codex 연동

codex 는 세션마다 기록 파일을 남기지만 그 파일에 pane 이 없다. 세션을 pane 에 이을
값이 없어서, 이 저장소가 상태를 기록하는 훅 스크립트를 함께 담고 있다. codex 는 훅을
부를 때 자기 환경을 물려주므로, 스크립트는 그 환경에서 mux 와 pane 을 안다.

`~/.codex/hooks.json` 에 훅 세 개를 넣는다.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "~/mux-agent-status/agents/codex/agent-status.sh busy" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/mux-agent-status/agents/codex/agent-status.sh idle" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "~/mux-agent-status/agents/codex/agent-status.sh remove" } ] }
    ]
  }
}
```

codex 는 신뢰하지 않은 훅을 돌리지 않는다. 훅을 넣은 뒤 codex 를 처음 띄우면
codex 가 훅을 검토하는 화면을 보여준다. 사용자가 거기서 승인해야 훅이 돈다.

훅은 `$TMPDIR/mux-agent-status-<uid>/<mux>/<세션>/codex-<pane>` 에
`<상태> <pid>` 를 쓰고, 세션이 끝나면 그 파일을 지운다. mux 와 세션을
판별하는 방법, pane 표기는 [동작 원리](#동작-원리)에 있다. 상태 이름은
mux-agent-status 의 나머지와 같아서 중간에 옮겨 적는 과정이 없다.

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

상태는 에이전트가 스스로 기록한 것을 읽는다. Claude Code 는 세션 파일을 직접
쓰고, codex 와 pi 는 이 저장소가 담은 훅과 확장이 대신 쓴다. mux-agent-status 는
어느 쪽에서도 프로세스 목록을 뒤지지 않는다.

| 에이전트 | 상태 파일 |
| --- | --- |
| Claude Code | `~/.claude/sessions/<pid>.json` |
| codex | `$TMPDIR/mux-agent-status-<uid>/<mux>/<세션>/codex-<pane>` |
| pi | `$TMPDIR/mux-agent-status-<uid>/<mux>/<세션>/pi-<pane>` |

codex 훅과 pi 확장은 자기 프로세스 환경에서 mux 를 판별한다. `TMUX_PANE` 이
있으면 tmux 로 판별하고 pane 표기에서 앞의 `%` 를 뗀다. psmux 는 tmux CLI
의 별칭이라 `TMUX_PANE` 을 그대로 물려주므로 같은 `tmux` 서브디렉터리를
쓴다. `ZELLIJ_PANE_ID` 가 있으면 zellij 로 판별하고 그 값을 pane 표기로
그대로 쓴다. 둘 다 없으면 표시할 곳이 없어 아무것도 쓰지 않는다.

세션 이름은 `tmux display-message -p '#S'`(tmux 계열) 나
`ZELLIJ_SESSION_NAME`(zellij) 으로 얻는다. psmux 는 `#{window_id}` 와
`#{pane_id}` 를 서버 전체가 아니라 세션마다 따로 채번해서, 세션이 다르면
같은 pane 번호가 겹칠 수 있다. 세션 이름을 경로에 넣어야 그 둘을 가른다.
tmux 는 pane_id 가 이미 서버 전체 고유라 이 계층이 없어도 됐지만, 모든
mux 에 공통으로 둬서 소비자 쪽 코드가 mux 마다 갈리지 않는다. 세션을 얻지
못하면 다른 세션의 pane 과 가를 수 없으므로 아무것도 쓰지 않는다.

에이전트마다 상태를 어떻게 남기는지는 `agents/<에이전트>/` 가 담고 있다.
Claude Code 의 상태 파일을 읽는 원리는 [agents/claude](agents/claude/README.ko.md)
에 있다.

`mux/tmux/agent-status.sh` 가 tmux 의 티커다. 1초마다 돌면서 tmux 포맷만으로는
할 수 없는 두 가지를 맡는다.

- 상태 파일을 세션 구분 없이 읽어 pane 옵션으로 옮긴다(pane_id 가 서버 전체
  고유라 어느 세션 아래 있었는지는 상관없다)
- 창에 속한 pane 을 상태별로 센다

`mux/psmux/agent-status.sh` 가 psmux 의 티커다. 옵션을 못 쓰는 대신 창
이름 자체에 집계를 붙이고, 창을 가리킬 때마다 "세션 이름:창 인덱스" 형태의
정규 타겟만 쓴다. `#{window_id}` 나 세션 없는 인덱스만으로 창을 가리키면
같은 번호를 쓰는 다른 세션의 창이 바뀔 수 있어서다.

두 티커 모두 값이 바뀐 대상에만 쓰고, 서버마다 하나만 돌고 서버가 끝나면
함께 끝난다.

## 저장소 구조

디렉터리는 mux 를 아는 코드와 에이전트를 아는 코드로 나뉜다. 새 mux 나 새
에이전트를 더할 때 고쳐야 할 자리가 한 곳으로 모인다.

| 디렉터리 | 담고 있는 것 |
| --- | --- |
| `mux/tmux` | tmux 진입점과 티커. 상태 파일을 읽어 tmux 옵션으로 옮긴다 |
| `mux/psmux` | psmux 진입점과 티커. 상태 파일을 읽어 창 이름에 집계를 붙인다 |
| `agents/claude` | Claude Code 의 상태 파일을 읽는 원리를 적은 문서 |
| `agents/codex` | codex 훅이 부르는 스크립트 |
| `agents/pi` | pi 확장 |

에이전트는 상태를
`$TMPDIR/mux-agent-status-<uid>/<mux>/<세션>/<에이전트>-<pane>` 에 남기고,
각 mux 소비자는 자기 이름의 서브디렉터리 아래만 읽는다. 두 쪽은 이 경로와
세 상태 이름으로만 이어져 있다.

## 제약

**중단과 완료를 구분하지 않는다.** Claude Code 는 사용자가 중단한 세션과
응답을 마친 세션을 모두 `idle` 로 보고한다. 두 경우 모두 초록 점으로 나온다.
Claude Code 가 상태를 하나만 주므로 이 구분을 만들 방법이 없다.

**세션 파일의 경로는 공개된 인터페이스가 아니다.** `~/.claude/sessions` 는
Claude Code 의 내부 구조이고 버전이 올라가면 바뀔 수 있다. 파일을 못 읽게 되면
Claude 세션의 indicator 만 사라지고 codex 와 pi 세션은 그대로 동작한다. 같은 값을
`claude agents --json` 이 공개 인터페이스로 내보내므로, 티커가 그 명령을 쓰도록
고치면 다시 동작한다. 이 명령은 호출당 400밀리초가 들어서 폴링 주기를 함께
늘려야 한다.

**codex 의 승인 대기는 `busy` 로 나온다.** codex 가 명령 실행 승인을 물어도 턴은
끝나지 않아서 `Stop` 훅이 돌지 않는다. 사용자가 답해야 하는 동안 pane 은 `busy` 의
빨간 점으로 남는다. 걸어 둔 훅 세 개로는 승인 프롬프트가 떠 있다는 것을 알 수 없다.

**zellij 에서는 Claude Code 세션이 나오지 않는다.** Claude Code 는 자기 세션
파일의 `tmux` 필드에 tmux 와 psmux 의 pane 만 채우고 zellij 의 pane 은 채우지
않는다. Claude Code 가 세션 파일을 스스로 쓰므로 이 저장소가 고칠 수 있는
값이 아니다. codex 와 pi 는 이 저장소가 담은 훅과 확장이 두 mux 를 모두
가리므로 zellij 에서도 그대로 나온다.

**psmux 에서는 pane 단위 indicator 를 못 그린다.** psmux 는 pane 과 창
스코프의 사용자 정의 옵션을 저장하지 않아서, `mux/tmux` 가 쓰는 pane
indicator(marker 와 clock 을 pane border 에 얹는 것) 방식을 psmux 에는
쓸 수 없다. `mux/psmux` 는 window indicator 에 해당하는 집계만 창 이름에
붙인다.

**psmux 의 세션 이름은 경로에 그대로 들어간다.** 세션 이름에 `/` 가 있으면
상태 파일 경로가 어긋난다. tmux 와 psmux 모두 세션 이름에 `/` 를 허용하지
않는 것이 보통이지만, 이 저장소는 그 값을 따로 검증하지 않는다.

## 요구 사항

- tmux 3.2 이상
- bash 5.0 이상
- Claude Code 2.1 이상
- codex 0.152 이상

## 라이선스

MIT

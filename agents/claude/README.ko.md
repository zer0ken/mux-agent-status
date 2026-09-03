# Claude Code 연동 원리

[English](README.md)

Claude Code 는 세션마다 상태 파일을 스스로 쓴다. mux-agent-status 는 그 파일을
읽기만 하므로 이 디렉터리에 코드가 없다.

## 상태 파일

Claude Code 는 세션마다 `~/.claude/sessions/<pid>.json` 을 두고 상태가 바뀔 때마다
갱신한다. 티커는 그중 네 필드를 읽는다.

| 필드 | 쓰임 |
| --- | --- |
| `kind` | 값이 `interactive` 인 세션만 표시한다 |
| `tmux` | 세션이 붙어 있는 pane 의 id |
| `status` | `waiting`, `idle`, `busy` 중 하나 |
| `statusUpdatedAt` | 상태가 바뀐 시각. 밀리초 단위이고 clock 의 기준이다 |

파일이 한 줄짜리 JSON 이라 티커는 bash 정규식만으로 이 값을 읽는다. 1초마다 도는
경로인데도 프로세스가 하나도 뜨지 않는다.

## pane 과 세션의 연결

`tmux` 필드에 pane 의 id 가 들어 있다. 티커는 파일 하나로 pane 을 알아내므로 pid 를
tty 로 옮기고 tty 를 다시 pane 으로 옮기는 과정이 없다. codex 와 pi 에 훅과 확장이
필요한 것은 두 에이전트가 이 값을 남기지 않기 때문이다.

## 표시하지 않는 세션

Claude Code 는 방금 띄워 아무 작업도 하지 않은 세션과 응답을 마친 세션에 똑같이
`idle` 을 준다. 두 세션을 갈라 놓을 값이 파일에 없어서, 티커는 `busy` 나 `waiting`
을 한 번이라도 거친 세션만 `idle` 로 표시한다.

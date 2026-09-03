# How the Claude Code integration works

[한국어](README.ko.md)

Claude Code writes a state file for every session on its own. mux-agent-status
only reads it, so this directory holds no code.

## The state file

Claude Code keeps `~/.claude/sessions/<pid>.json` per session and updates it on
every state change. The ticker reads four of its fields.

| Field | Use |
| --- | --- |
| `kind` | Only sessions whose value is `interactive` are shown |
| `tmux` | Id of the pane the session runs in |
| `status` | One of `waiting`, `idle`, `busy` |
| `statusUpdatedAt` | When the state changed, in milliseconds. The clock counts from it |

The file is single-line JSON, so the ticker reads these values with a bash
regular expression alone. This path runs once a second and spawns no process.

## Tying a session to a pane

The `tmux` field carries the id of the pane. The ticker learns the pane from the
file itself, so it never maps a pid to a tty and a tty to a pane. codex and pi
need a hook and an extension because neither of them records that value.

## Sessions that stay hidden

Claude Code reports `idle` both for a session that was just started and did no
work and for one that finished responding. Nothing in the file separates the
two, so the ticker shows `idle` only for sessions it has seen in `busy` or
`waiting` at least once.

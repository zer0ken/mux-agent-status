# tmux-agent-status

[한국어](README.ko.md)

tmux-agent-status shows the state of your Claude Code, codex and pi sessions in the
tmux status bar. With several windows open, you can see which one is waiting on
you and which one is still running without switching to it.

## States

There are three states. The vocabulary and the colors match the session picker
in claude-session-manager, so the picker and the status bar read the same way.
The default palette is catppuccin mocha.

| State | Color | Meaning |
| --- | --- | --- |
| `waiting` | ![f9e2af](https://img.shields.io/badge/waiting-%23f9e2af-f9e2af?style=flat-square&labelColor=313244) | The session is waiting for input |
| `idle` | ![a6e3a1](https://img.shields.io/badge/idle-%23a6e3a1-a6e3a1?style=flat-square&labelColor=313244) | The session has finished responding |
| `busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | The session is running |

A session that has just been started and has not done any work yet stays off the
status bar. Claude Code reports `idle` for such a session and for one that
finished responding alike, so tmux-agent-status only shows `idle` for sessions
it has seen in `busy` or `waiting` at least once.

## Indicators

tmux-agent-status publishes two indicators. The window indicator stands for one
window, the pane indicator for one pane. The parts an indicator is built from
each have a name.

| Name | Appears in | Meaning |
| --- | --- | --- |
| marker | both indicators | A dot carrying the state as a color and a glyph |
| counter | window indicator | How many panes are in that state |
| clock | pane indicator | How long the session has been `busy` |

The window indicator counts the panes of a window per state and lays out a
marker and a counter for each. The order is fixed at `waiting`, `idle`, `busy`,
and a state with no pane in it is left out.

```
 2  ● 1 ● 2  claude
```

The pane indicator carries the marker for that one pane. In `busy` a clock
follows the marker.

```
 1  ● 49s  Jupiter tmux setup
```

## Installation

```bash
git clone https://github.com/zer0ken/tmux-agent-status.git ~/tmux-agent-status
```

Add one line to tmux.conf that calls the entry point. The entry point fills in
the option defaults and starts the ticker, a background process that reads the
state and carries it into tmux options.

```tmux
run-shell "~/tmux-agent-status/tmux/agent-status.tmux"
```

The entry point only writes the indicators into options. It does not rewrite
your status bar format. Splice the indicators into the format you already use.

```tmux
set -g window-status-format "#I #{E:@agent_window_indicator}#W"
set -wg pane-border-format  "#{pane_index} #{E:@agent_pane_indicator}#{pane_title}"
```

## pi support

pi publishes neither a list of running sessions nor a state file, so this
repository ships a pi extension that records the state itself. Install the
extension with pi; no other package is needed.

```bash
pi install git:github.com/zer0ken/tmux-agent-status
```

The extension writes `<state> <pid>` to
`$TMPDIR/tmux-agent-status-<uid>/pi-<pane>` on every state change and removes
the file when the session ends. It uses the same three state names as the rest
of tmux-agent-status, so nothing is translated in between.

## codex support

codex writes a record file per session, but that file carries no pane. Nothing
in it ties a session to a pane, so this repository ships a hook script that
records the state instead. codex passes its own environment to a hook, so the
script reads the pane from `TMUX_PANE`.

Put three hooks in `~/.codex/hooks.json`.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "~/tmux-agent-status/codex/agent-status.sh busy" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/tmux-agent-status/codex/agent-status.sh idle" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "~/tmux-agent-status/codex/agent-status.sh remove" } ] }
    ]
  }
}
```

codex runs no hook it does not trust. On the first codex launch after the hooks
are in place, codex shows a review screen. The hooks run once the user approves
them there.

The hook writes `<state> <pid>` to
`$TMPDIR/tmux-agent-status-<uid>/codex-<pane>` and removes the file when the
session ends. It uses the same state names as the rest of tmux-agent-status, so
nothing is translated in between.

## Options

An option takes effect within a second of being changed. Values set in
tmux.conf before the entry point runs win, because the entry point writes its
defaults with `set -ogq`.

| Option | Default | Meaning |
| --- | --- | --- |
| `@agent_marker` | `●` | Default marker for all three states |
| `@agent_marker_waiting` | `@agent_marker` | Marker for `waiting` |
| `@agent_marker_idle` | `@agent_marker` | Marker for `idle` |
| `@agent_marker_busy` | `@agent_marker` | Marker for `busy` |
| `@agent_marker_color_waiting` | ![f9e2af](https://img.shields.io/badge/waiting-%23f9e2af-f9e2af?style=flat-square&labelColor=313244) | Color of the `waiting` marker |
| `@agent_marker_color_idle` | ![a6e3a1](https://img.shields.io/badge/idle-%23a6e3a1-a6e3a1?style=flat-square&labelColor=313244) | Color of the `idle` marker |
| `@agent_marker_color_busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | Color of the `busy` marker |
| `@agent_counter_color` | empty | Color of the counter. Empty follows the marker |
| `@agent_clock_color` | empty | Color of the clock. Empty follows the marker |
| `@agent_text_color` | ![cdd6f4](https://img.shields.io/badge/text-%23cdd6f4-cdd6f4?style=flat-square&labelColor=313244) | Color of the text that follows an indicator |

## How it works

The state comes from what each agent records about itself. Claude Code writes
its session file on its own; for codex and pi the hook and the extension this
repository ships write it instead. tmux-agent-status scans a process table on
neither path.

| Agent | State file |
| --- | --- |
| Claude Code | `~/.claude/sessions/<pid>.json` |
| codex | `$TMPDIR/tmux-agent-status-<uid>/codex-<pane>` |
| pi | `$TMPDIR/tmux-agent-status-<uid>/pi-<pane>` |

The Claude Code session file carries the id of the pane the session runs in, in
its `tmux` field, so there is no need to map a pid to a tty and a tty to a pane.
The file is single-line JSON, which bash reads with a regular expression, and
that path spawns no processes at all.

`bin/agent-status.sh` is the ticker. It runs once a second and covers the two
things a tmux format cannot do on its own.

- Carrying the state files into pane options
- Counting the panes of a window per state

The ticker writes options only for the panes and windows whose values changed.
One ticker runs per tmux server and ends when that server ends.

## Limitations

**An interrupted turn is indistinguishable from a finished one.** Claude Code
reports `idle` both for a session the user interrupted and for one that finished
responding, so both appear as a green dot. Claude Code exposes a single state,
so this distinction cannot be recovered.

**The session file path is not a public interface.** `~/.claude/sessions` is
internal to Claude Code and may move between versions. If the files become
unreadable, only the indicators for Claude sessions disappear; codex and pi
sessions keep working. The same values are published through `claude agents --json`,
so pointing the ticker at that command brings them back. That call costs about
400 milliseconds, so the polling interval has to grow with it.

**An approval prompt in codex reads as `busy`.** When codex asks to run a
command the turn has not ended, so the `Stop` hook does not fire. The pane stays
on the red `busy` dot for as long as it is the user's move. The three hooks
above cannot tell that an approval prompt is on screen.

## Requirements

- tmux 3.2 or newer
- bash 5.0 or newer
- Claude Code 2.1 or newer
- codex 0.152 or newer

## License

MIT

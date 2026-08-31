# tmux-agent-status

[한국어](README.ko.md)

tmux-agent-status shows the state of your Claude Code and pi sessions in the
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
| `busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | The session is running. Elapsed time is shown alongside |

A session that has just been started and has not done any work yet carries no
badge. `idle` is the same value for a session that finished responding and for
one that never worked, so tmux-agent-status only reports `idle` for sessions it
has seen in `busy` or `waiting` at least once.

## Placement

The window tab carries a count per state for the panes in that window. The
order is fixed, and the state that most needs your attention comes first.

```
 2  ● 1 ● 2  claude
```

The pane title carries the state of that one pane. For `busy` it is followed by
how long the pane has been in that state.

```
 1  ● 49s  Jupiter tmux setup
```

## Installation

tmux-agent-status uses no Claude Code hooks. install.sh only removes hooks left
behind by an earlier version, so a fresh installation does not need to run it.

```bash
git clone https://github.com/zer0ken/tmux-agent-status.git ~/tmux-agent-status
```

Add one line to tmux.conf that calls the entry point. The entry point fills in
the option defaults and starts the ticker.

```tmux
run-shell "~/tmux-agent-status/tmux/agent-status.tmux"
```

The entry point only writes the badge strings into options. It does not rewrite
your status bar format. Splice the badges into the format you already use.

```tmux
set -g window-status-format "#I #{E:@agent_win_badge}#W"
set -wg pane-border-format  "#{pane_index} #{E:@agent_badge_pane}#{pane_title}"
```

## pi support

The state of a pi session comes from the file that the pi-tmux-status extension
writes to `/tmp/pi-tmux-<pane>.txt`. Install that extension alongside pi.

```bash
pi install npm:pi-tmux-status
```

pi reports `working`, `asking` and `idle`, which map to `busy`, `waiting` and
`idle`.

## Options

The ticker reads the colors and the glyph once at startup. Changing them takes
effect after the tmux configuration is sourced again.

| Option | Default | Meaning |
| --- | --- | --- |
| `@agent_color_waiting` | ![f9e2af](https://img.shields.io/badge/waiting-%23f9e2af-f9e2af?style=flat-square&labelColor=313244) | Color for `waiting` |
| `@agent_color_idle` | ![a6e3a1](https://img.shields.io/badge/idle-%23a6e3a1-a6e3a1?style=flat-square&labelColor=313244) | Color for `idle` |
| `@agent_color_busy` | ![f38ba8](https://img.shields.io/badge/busy-%23f38ba8-f38ba8?style=flat-square&labelColor=313244) | Color for `busy` |
| `@agent_color_text` | ![cdd6f4](https://img.shields.io/badge/text-%23cdd6f4-cdd6f4?style=flat-square&labelColor=313244) | Color of the text that follows a badge |
| `@agent_glyph` | `●` | Glyph shared by all three states |

## How it works

The state comes from what each agent records about itself. Claude Code keeps
`~/.claude/sessions/<pid>.json` up to date for every session, and pi keeps
`/tmp/pi-tmux-<pane>.txt` up to date through the pi-tmux-status extension.
tmux-agent-status installs no hooks and scans no process table.

The Claude Code session file carries the id of the pane the session runs in, in
its `tmux` field, so there is no need to map a pid to a tty and a tty to a pane.
The file is single-line JSON, which bash reads with a regular expression, and
that path spawns no processes at all.

`bin/agent-status.sh` is a ticker that runs once a second. It covers the two
things a tmux format cannot do on its own.

- Carrying the state files into pane options
- Counting the panes of a window per state

The ticker does not call tmux when nothing has changed. One ticker runs per tmux
server and ends when that server ends.

## Limitations

**An interrupted turn is indistinguishable from a finished one.** Claude Code
reports `idle` both for a session the user interrupted and for one that finished
responding, so both appear as a green dot. Claude Code exposes a single state,
so this distinction cannot be recovered.

**The session file path is not a public interface.** `~/.claude/sessions` is
internal to Claude Code and may move between versions. If the files become
unreadable, only the badges for Claude sessions disappear; pi sessions and tmux
keep working. The same values are published through `claude agents --json`, so
the ticker can be pointed at that command instead. That call costs about 400
milliseconds, so the polling interval has to grow with it.

## Requirements

- tmux 3.2 or newer
- bash 5.0 or newer
- Claude Code 2.1 or newer

## License

MIT

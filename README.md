# mux-agent-status

[한국어](README.ko.md)

mux-agent-status shows the state of your Claude Code, codex and pi sessions in the
tmux and psmux status bar. With several windows open, you can see which one is
waiting on you and which one is still running without switching to it.

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
finished responding alike, so mux-agent-status only shows `idle` for sessions
it has seen in `busy` or `waiting` at least once.

## Indicators

mux-agent-status publishes two indicators. The window indicator stands for one
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
git clone https://github.com/zer0ken/mux-agent-status.git ~/mux-agent-status
```

Add one line to tmux.conf that calls the entry point. The entry point fills in
the option defaults and starts the ticker, a background process that reads the
state and carries it into tmux options.

```tmux
run-shell "~/mux-agent-status/mux/tmux/agent-status.tmux"
```

The entry point only writes the indicators into options. It does not rewrite
your status bar format. Splice the indicators into the format you already use.

```tmux
set -g window-status-format "#I #{E:@agent_window_indicator}#W"
set -wg pane-border-format  "#{pane_index} #{E:@agent_pane_indicator}#{pane_title}"
```

psmux does not persist user-defined options at the pane or window scope, so
this approach does not carry over. `psmux.conf` gets a separate entry point.
`run-shell` on psmux runs the command through PowerShell rather than a POSIX
shell, so the entry point is a `.ps1` file that launches the bash ticker as
its own process.

```tmux
run-shell "~/mux-agent-status/mux/psmux/agent-status.ps1"
```

The psmux ticker skips the store-in-an-option-and-reference-it-from-a-format
approach and instead appends the finished aggregate string directly to the
window name. The original window name is left alone and there is no status
bar format to splice into, so installation is the only step needed.

## pi support

pi publishes neither a list of running sessions nor a state file, so this
repository ships a pi extension that records the state itself. Install the
extension with pi; no other package is needed.

```bash
pi install git:github.com/zer0ken/mux-agent-status
```

The extension detects the mux and session from the pi process's own
environment, then writes `<state> <pid>` to
`$TMPDIR/mux-agent-status-<uid>/<mux>/<session>/pi-<pane>` on every state
change and removes the file when the session ends. How the mux and session
are detected, and how the pane is spelled, is in
[How it works](#how-it-works). It uses the same three state names as the rest
of mux-agent-status, so nothing is translated in between.

## codex support

codex writes a record file per session, but that file carries no pane. Nothing
in it ties a session to a pane, so this repository ships a hook script that
records the state instead. codex passes its own environment to a hook, so the
script reads the mux and the pane from that environment.

Put three hooks in `~/.codex/hooks.json`.

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

codex runs no hook it does not trust. On the first codex launch after the hooks
are in place, codex shows a review screen. The hooks run once the user approves
them there.

The hook writes `<state> <pid>` to
`$TMPDIR/mux-agent-status-<uid>/<mux>/<session>/codex-<pane>` and removes the
file when the session ends. How the mux and session are detected, and how the
pane is spelled, is in [How it works](#how-it-works). It uses the same state
names as the rest of mux-agent-status, so nothing is translated in between.

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

psmux does not persist these as options, so `mux/psmux/agent-status.sh` reads
them from environment variables instead, with the same defaults falling back
to the ANSI 8-color names rather than the catppuccin mocha hex values. Set
them before the entry point launches the ticker, for instance by exporting
them earlier in the shell that starts psmux.

| Variable | Default | Meaning |
| --- | --- | --- |
| `MARKER_WAITING` | `●` | Marker for `waiting` |
| `MARKER_IDLE` | `●` | Marker for `idle` |
| `MARKER_BUSY` | `●` | Marker for `busy` |
| `COLOR_WAITING` | `yellow` | Color of the `waiting` marker and counter |
| `COLOR_IDLE` | `green` | Color of the `idle` marker and counter |
| `COLOR_BUSY` | `red` | Color of the `busy` marker and counter |
| `COLOR_TEXT` | `default` | Color of the window name that follows the indicator |

## How it works

The state comes from what each agent records about itself. Claude Code writes
its session file on its own; for codex and pi the hook and the extension this
repository ships write it instead. mux-agent-status scans a process table on
neither path.

| Agent | State file |
| --- | --- |
| Claude Code | `~/.claude/sessions/<pid>.json` |
| codex | `$TMPDIR/mux-agent-status-<uid>/<mux>/<session>/codex-<pane>` |
| pi | `$TMPDIR/mux-agent-status-<uid>/<mux>/<session>/pi-<pane>` |

The codex hook and the pi extension detect the mux from their own process
environment. `TMUX_PANE` present means tmux, and the pane is spelled with its
leading `%` stripped. psmux is an alias of the tmux CLI and passes `TMUX_PANE`
through unchanged, so it shares the same `tmux` subdirectory. `ZELLIJ_PANE_ID`
present means zellij, and the pane is spelled exactly as that value. Neither
present means there is nowhere to show the state, so nothing is written.

The session name is read with `tmux display-message -p '#S'` (tmux family) or
`ZELLIJ_SESSION_NAME` (zellij). psmux numbers `#{window_id}` and `#{pane_id}`
per session rather than server-wide, so two different sessions can share the
same pane number. The session name in the path is what tells them apart. tmux
didn't need this layer, since its pane_id is already server-wide unique, but
keeping it common across every mux keeps the consumer-side code from forking
per mux. When the session cannot be determined, nothing is written, since
there would be no way to tell it apart from another session's pane.

How each agent records its state lives under `agents/<agent>/`. The principle
behind reading the Claude Code state file is in
[agents/claude](agents/claude/README.md).

`mux/tmux/agent-status.sh` is the tmux ticker. It runs once a second and
covers the two things a tmux format cannot do on its own.

- Carrying the state files into pane options, read without regard to which
  session subdirectory they came from (pane_id is already server-wide unique)
- Counting the panes of a window per state

`mux/psmux/agent-status.sh` is the psmux ticker. In place of options it
appends the aggregate directly to the window name, and every place it targets
a window uses the full "session name:window index" form - targeting by
`#{window_id}` or a session-less index alone would rename another session's
window that happens to share the number. Color rides along as a tmux format
escape (`#[fg=...]`) embedded in the window name string itself; psmux
interprets that escape when it renders the window name to the screen, even
though commands that print the name back as text show it unevaluated.

Both tickers write only to targets whose value changed. One ticker runs per
server and ends when that server ends.

## Layout

The directories split code that knows a mux from code that knows an agent.
Adding a mux or an agent then touches one place.

| Directory | Holds |
| --- | --- |
| `mux/tmux` | The tmux entry point and ticker, which carry state files into tmux options |
| `mux/psmux` | The psmux entry point and ticker, which carry state files into window names |
| `agents/claude` | A document on the principle behind reading the Claude Code state file |
| `agents/codex` | The script the codex hooks call |
| `agents/pi` | The pi extension |

An agent leaves its state in
`$TMPDIR/mux-agent-status-<uid>/<mux>/<session>/<agent>-<pane>`, and each mux
consumer reads only under its own named subdirectory. That path and the three
state names are the whole contract between the two sides.

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

**Claude Code sessions do not appear under zellij.** Claude Code's own session
file fills the `tmux` field only for a tmux or psmux pane, never for a zellij
one. Claude Code writes that file itself, so this is not something this
repository can fix. codex and pi still appear under zellij, because the hook
and the extension this repository ships cover both muxes themselves.

**psmux cannot render a pane-level indicator.** psmux does not persist
user-defined options at the pane or window scope, so the pane indicator
approach `mux/tmux` uses (marker and clock riding the pane border) has
nothing to work from on psmux. `mux/psmux` only appends the equivalent of the
window indicator's aggregate to the window name.

**A psmux session name goes straight into the state file path.** A `/` in the
session name would break it. Neither tmux nor psmux ordinarily allow a `/` in
a session name, but this repository does not validate the value itself.

**Reloading psmux.conf does not start the ticker.** `run-shell` works when
typed at the prompt, but psmux does not appear to run it while reloading
config with `source-file`. Starting psmux fresh runs the entry point normally;
only a live reload needs `run-shell "~/mux-agent-status/mux/psmux/agent-status.ps1"`
typed by hand once.

## Requirements

- tmux 3.2 or newer, or psmux with PowerShell on the PATH
- bash 5.0 or newer
- Claude Code 2.1 or newer
- codex 0.152 or newer

## License

MIT

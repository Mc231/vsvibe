# Remote projects (SSH)

A remote project is a project whose folder lives on another machine. Its panes
open a local shell, `ssh` into the host, `cd` into the remote folder and run
Claude there (or an alias such as `claudework`, any other command, or just a
shell).

Create one with **File → New Remote Project…** or the network button in the
sidebar footer. The project editor's **Local folder / Remote (SSH)** switch can
also turn an existing project into a remote one or back.

| Field | Meaning |
| --- | --- |
| Host | An `~/.ssh/config` `Host`, `host` or `user@host`. |
| Port | Optional; blank uses ssh's default (or your ssh config). |
| Remote folder | Absolute, relative to the remote home, `~` or `~/…`. Blank stays in the remote home. |
| Remote command | Default `claude`. Empty opens an interactive login shell. |
| Runs Claude | On by default when there is a command: VSVibe picks the conversation id so restore can resume it. |

The name defaults to `<remote folder name> (<host>)`.

## How a pane starts

The pane spawns your local login shell in your home directory (with
`VSVIBE_PANE_ID` set, as for every pane) and types one line:

```sh
ssh -t [-p PORT] -- 'DEST' '<remote script>'
```

The remote login shell (`$SHELL -c`, run by sshd) runs the remote script:

```sh
# command
exec env VSVIBE_PANE_ID=<pane> "$SHELL" -i -l -c 'cd ~/'\''app'\'' || exit 1; exec claude --session-id <uuid>'
# restored Claude pane
exec env VSVIBE_PANE_ID=<pane> "$SHELL" -i -l -c 'cd … || exit 1; claude --resume <id> || exec claude --session-id <id>'
# empty command
cd ~/'app' || exit 1; exec env VSVIBE_PANE_ID=<pane> "$SHELL" -l
```

A full typed line, for host `dev`, folder `~/app`, command `claude`:

```sh
ssh -t -- 'dev' 'exec env VSVIBE_PANE_ID=<pane> "$SHELL" -i -l -c '\''cd ~/'\''\'\'''\''app'\''\'\'''\'' || exit 1; exec claude --session-id <uuid>'\'''
```

- The command runs in an **interactive login shell** (`-i -l -c`, like VSVibe's
  local `ShellProbe`), so aliases and PATH entries from the remote rc files work.
- `VSVIBE_PANE_ID` is exported on the remote side so remote Claude hooks tag
  their events with the pane (see *Hook events*).
- `exec` means quitting the command ends the ssh session; the pane is back at
  its local shell. A missing remote folder exits instead of running elsewhere.

## Quoting and validation

The line is parsed by two shells (local, then remote; the inner `-c` script is a
third level). Every level uses POSIX single quotes with `'` written as `'\''`,
so nothing is expanded locally. A leading `~` or `~/` of the remote folder stays
unquoted so it expands on the remote host (`~user/…` is taken literally); a
folder starting with `-` gets `./`. The remote command is your own command line
and is passed through as a command line, not quoted into one word.

`SSHCommand` rejects, rather than escapes:

- hosts that are empty, longer than 255 characters, start with `-` (also placed
  after `--`) or contain anything but letters, digits and `. _ - @ : %`
  (IPv6 literals work without brackets, e.g. `fe80::1%en0`);
- ports outside 1–65535;
- control characters (e.g. newlines, which would submit the typed line early) in
  the folder or command;
- conversation ids that are not `[A-Za-z0-9_-]`.

An invalid project (e.g. a hand-edited `state.json`) types nothing and shows the
reason in the pane's banner. The checks and real-shell round trips (`sh`, `zsh`,
a folder name full of metacharacters) are in `VSVibeTests/SSHCommand*Tests`.

## Restore without hooks

Hooks on the host are optional and events can be missed while disconnected, so
VSVibe chooses the conversation id
itself (`RemoteLaunch`): with **Runs Claude** on, a fresh pane runs
`CMD --session-id <new uuid>` and records the id as the pane's
`claudeSessionID` right away, so it is saved in `sessions.json` (format
unchanged, v2). On restore the pane runs
`CMD --resume <id> || exec CMD --session-id <id>`; the fallback covers a
conversation that never started (where `--resume` fails). Conversation flags in
the command (`--continue`, `-c`, `--resume`, `-r`, `--session-id`) are dropped for
the resume; a command that picks its own conversation (e.g. *Continue Last
Session*, `claude --continue`) gets no id. The transcript is on the remote host,
so it is not checked; a saved valid path is carried, so the restored pane's
usage shows at once. A later hook event carrying the pane's id still replaces
the id and transcript path (`SessionManager.recordClaudeConversation`).

## Identity

A remote project has no local folder. New ones get the identity URL
`/.vsvibe-remote/<project id>` (a root-level path nobody can create), which keys
its statistics and never collides with a local project; it stays the same when
the host or folder is edited. A local project turned remote keeps its old URL,
so its statistics carry on. The URL is never used as a working directory: Open
In, Show in Finder, git review and the git stats are hidden for remote projects.
`launchCommand` is `ssh`; the remote command is `remote.command`
(`FolderEntry.primaryCommand`).

## Background ssh

Everything below runs over VSVibe's own ssh calls, separate from the pane's
typed line (`RemoteSSH`): `/usr/bin/ssh` started with an argument array (no local
shell), with

```sh
ssh -o BatchMode=yes -o ConnectTimeout=10 \
    -o ControlMaster=auto -o ControlPath=~/.vsvibe/ssh/cm-%C -o ControlPersist=60 \
    [-o ServerAliveInterval=15 -o ServerAliveCountMax=3]   # streams only
    [-p PORT] -- DEST "exec /bin/sh -c '<script, quoted>'"
```

- `BatchMode` never prompts: these calls only work with key / agent
  authentication (or an existing `ControlMaster` connection). A password-only
  host still works in the pane, but shows no events, usage or branch.
- All calls to a host share one multiplexed connection; `~/.vsvibe/ssh` is
  created with mode 0700.
- The remote login shell only `exec`s `/bin/sh`, so the scripts are POSIX sh
  whatever the login shell is. Every path in them is validated (absolute, no
  control characters) and single-quoted with `SSHCommand.shellQuoted`; the
  destination and port are validated like the pane's line.

## Claude hooks on the host

The project editor of a remote project has a **Claude hooks on the host**
section: a status line (installed and current / outdated or incomplete / not
installed / can't reach the host / failed, with the Claude config dir) and
**Install / Update / Reinstall Hooks on <host>**. Editing an existing remote
project checks the status automatically; **Check** re-reads it.
`RemoteHookInstaller`:

1. Probes the host: prints `$HOME` and asks the remote interactive login shell
   (`"$SHELL" -i -l -c 'alias NAME || typeset -f NAME'`, stdin `/dev/null`) how
   the base word of the project's command is defined. A `CLAUDE_CONFIG_DIR` in
   that alias / function (read with `ShellAliasParser`, `~` and `$HOME`
   expanded to the remote home) is the config dir; otherwise `~/.claude`.
2. Writes `HookScript.contents` (the same script as locally) to
   `~/.vsvibe/hooks/claude-notify.sh` through stdin
   (`mkdir -p … && cat > … && chmod 755 …`).
3. Reads `<config dir>/settings.json`, merges the VSVibe entries with the same
   pure functions as the local installer (`HookSettings`: other hooks are kept,
   older VSVibe entries replaced) with the remote absolute script path, and
   writes it back through a temporary file, keeping `settings.json.vsvibe.bak`.
   A `settings.json` that is not valid JSON is left alone and reported.

Restart the remote Claude sessions after installing so they load the hooks.

## Hook events

For every (host, port) with open remote panes, `RemoteEventStreams` keeps one
stream:

```sh
mkdir -p ~/.vsvibe && touch ~/.vsvibe/events.jsonl && exec tail -n 0 -F ~/.vsvibe/events.jsonl
```

Its output is split into lines (`LineSplitter`), decoded as `HookEvent` and
handed to `EventCoordinator.handleRemote` on the main actor: notifications,
"needs input", stats and the pane's conversation id / transcript path work as
for local panes. A remote event only ever reaches the open remote pane its
`paneId` names (no folder-path fallback); the local events file never routes to
remote panes. When ssh exits the stream reconnects after 1 s, 2 s, 4 s … up to
60 s (`ReconnectBackoff`; a connection that lasted 30 s starts over). The
stream stops when the host's last remote pane closes, and all streams stop when
VSVibe quits.

## Token usage

Once a hook event (e.g. `SessionStart`) reports the pane's remote
`transcript_path` (absolute, `.jsonl`, no control characters),
`RemoteUsageTracker` streams it with `exec tail -c +1 -F '<path>'` and feeds the
bytes, off the main actor, to the same parser as local panes
(`UsageAccumulator`). A new path (e.g. after `/clear`) restarts the stream and
clears the shown usage; each reconnect re-reads the file from the start. Before
the first hook event a remote pane shows no usage (the local "latest transcript"
guess does not apply).

## Git branch

`RemoteBranchTracker` polls every 20 s:

```sh
cd '<remote folder>' 2>/dev/null && { git symbolic-ref --short -q HEAD || git rev-parse --short HEAD; } 2>/dev/null
```

(`~` / `~/…` expand remotely; an empty folder is the remote home). Failures hide
the branch.

## Requirements and limitations

- ssh must authenticate without a prompt (keys, agent, `ControlMaster`) for
  events, usage, branch and hook installation; otherwise you type the password
  / passphrase in the pane and those stay empty.
- The hook script needs `bash` on the host; `python3` is optional (without it
  events carry no message, conversation id or transcript path, so no usage).
- Events written while a host's stream is disconnected are missed
  (`tail -n 0`); the conversation id recorded at launch still allows restore.
- The remote login shell must understand `cd … || exit 1;`, `env` and
  `-i -l -c` for the pane's line (bash, zsh, sh, fish).

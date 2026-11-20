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
- `VSVIBE_PANE_ID` is exported on the remote side so remote Claude hooks can tag
  their events with the pane (Phase B).
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

Remote panes have no hook events yet, so VSVibe chooses the conversation id
itself (`RemoteLaunch`): with **Runs Claude** on, a fresh pane runs
`CMD --session-id <new uuid>` and records the id as the pane's
`claudeSessionID` right away, so it is saved in `sessions.json` (format
unchanged, v2). On restore the pane runs
`CMD --resume <id> || exec CMD --session-id <id>`; the fallback covers a
conversation that never started (where `--resume` fails). Conversation flags in
the command (`--continue`, `-c`, `--resume`, `-r`, `--session-id`) are dropped for
the resume; a command that picks its own conversation (e.g. *Continue Last
Session*, `claude --continue`) gets no id. The transcript is on the remote host,
so it is not checked. A later hook event carrying the pane's id still replaces
the id (`SessionManager.recordClaudeConversation`).

## Identity

A remote project has no local folder. New ones get the identity URL
`/.vsvibe-remote/<project id>` (a root-level path nobody can create), which keys
its statistics and never collides with a local project; it stays the same when
the host or folder is edited. A local project turned remote keeps its old URL,
so its statistics carry on. The URL is never used as a working directory: Open
In, Show in Finder, git review and the git stats are hidden for remote projects.
`launchCommand` is `ssh`; the remote command is `remote.command`
(`FolderEntry.primaryCommand`).

## Limitations (Phase B)

- No hook notifications or "awaiting input" state for remote panes.
- No token usage and no git branch (nothing local is tracked; the stats sheet
  shows only panes opened and active time).
- ssh must authenticate without a prompt (keys, agent, `ControlMaster`), or you
  type the password / passphrase in the pane.
- The remote login shell must understand `cd … || exit 1;`, `env` and `-i -l -c`
  (bash, zsh, sh, fish).

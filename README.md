# zzclone - ZFS Dataset Cloning Tool

## Overview

`zzclone` generates `zfs send/receive` commands to clone ZFS datasets with their snapshots from a source to a destination. It supports local and remote (SSH) transfers via mbuffer.

The tool outputs shell commands to stdout — it does not execute them directly.

## Prerequisites

- **Perl** 5 (any modern version)
- **ZFS** (`zfs` command available)
- **mbuffer** for buffered transfers
- **SSH** for remote transfers (key-based auth recommended)

## Usage

```bash
./zzclone [options] [src-host:]src-root [dest-host:]dest-root
```

### Options

- `-l, --last-only` — Only transfer the last snapshot (no incremental)
- `-s, --sync` — Check destination snapshots and only output commands for what's missing
- `-R, --rollback` — Before each incremental send, roll the destination back to the common snapshot (`zfs rollback -r`), discarding local changes and diverging snapshots; the fallback full send receives with `-F`, overwriting a destination that shares no snapshot with the source (implies `--sync`)
- `-r, --resume` — Make transfers resumable: emit `zfs receive -s`, and on a later run pick up any saved resume token with `zfs send -t`
- `-c, --chain` — Emit all commands as a single `&&`-joined chain (comments go to stderr), ready to pipe into a shell
- `-v, --verbose` — Add `-v` to every `zfs send` for size estimate and progress
- `-W, --watchdog <sec>` — Add `-W <sec>` to every mbuffer: a transfer that moves no data for that long aborts (and leaves a resume token with `--resume`) instead of hanging forever

All emitted `ssh` commands use `BatchMode` and keepalives (`ServerAliveInterval 15`, `ServerAliveCountMax 4`), so a silently dead connection fails within about a minute rather than blocking the pipeline indefinitely.
- `-S, --sudo` — Prefix every `zfs` invocation with `sudo` (shorthand for `--local-sudo --remote-sudo`)
- `--local-sudo` — Use `sudo zfs` only on the local side
- `--remote-sudo` — Use `sudo zfs` only on the remote (SSH) side
- `-h, --help` — Show help message

Either source or destination can be remote (via SSH), but not both.

### Examples

```bash
# Generate commands to clone all snapshots
./zzclone tank/data backup/data

# Clone from remote source
./zzclone remote-host:tank/data backup/data

# Clone to remote destination
./zzclone tank/data remote-host:backup/data

# Only transfer the latest snapshot
./zzclone --last-only tank/data backup/data

# Sync mode: check what's already on destination, output only the diff
./zzclone --sync tank/data backup/data

# Resumable transfer: if interrupted, re-run the same command to continue (implies --sync)
./zzclone --resume tank/data remote-host:backup/data

# Run all zfs commands via sudo (e.g. unprivileged login on the remote)
./zzclone --sudo tank/data remote-host:backup/data

# Only the remote (SSH) side needs sudo; local zfs runs as-is
./zzclone --remote-sudo tank/data remote-host:backup/data
```

## Modes

### Default Mode

Generates commands to send all snapshots from source to destination:

1. Full send of the first (or last with `-l`) snapshot
2. Incremental send (`zfs send -I`) from first to last snapshot

### Sync Mode (`--sync`)

Queries the destination for existing snapshots and generates only what's needed:

1. Lists snapshots on both source and destination
2. Finds the last common snapshot (by name match)
3. Verifies the common snapshot via ZFS GUID to ensure datasets are actually related
4. Outputs incremental send from the common snapshot to the latest source snapshot
5. If no common snapshot exists, falls back to a full send
6. If already up to date, skips with a comment

The GUID check prevents accidental transfers between unrelated datasets that happen to have same-named snapshots.

### Resume Mode (`--resume`)

Makes large transfers restartable after an interruption (dropped SSH connection, reboot, etc.). Implies `--sync`.

1. Every `zfs receive` is emitted with `-s`, so an interrupted transfer leaves a `receive_resume_token` on the destination dataset
2. On a later run with `--resume`, the script reads that token from each destination dataset and emits `zfs send -t <token>` to finish the interrupted stream, before doing anything else for that dataset
3. Finishing the stream only brings the destination to the resumed snapshot. Run the same command **once more** afterwards — with the token gone, the implied sync sends the incremental up to the newest snapshot, bringing the dataset fully up to date
4. While in this mode the script also prints a short note explaining how to resume a single dataset by hand, or how to discard a stale token (`zfs receive -A`)

## Safety

- **Output only**: The tool prints commands but does not execute them, allowing review before running
- **GUID verification** (sync mode): Ensures source and destination snapshots are actually related before generating incremental commands

## Testing

`t/regression.t` runs `zzclone` against a canned fake ZFS world (shim `zfs`, `ssh` and `sudo` commands in `t/shims`) across all option combinations and compares the generated commands against the files in `t/expected`. The fake dataset tree covers the incremental, full-send, up-to-date, no-snapshot, resume-token and guid-mismatch code paths.

```bash
prove t/
```

After an intentional change to the generated output, regenerate the expected files with `UPDATE_EXPECTED=1 prove t/` and review the diff.

## Credits

The script was originally written by [Tobias Oetiker](https://github.com/oetiker) (tobi@oetiker.ch).

## License

MIT — see [LICENSE](LICENSE).

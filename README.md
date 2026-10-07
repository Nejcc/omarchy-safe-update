# Safe Update

A bar widget that tells you whether the last `omarchy update` broke the shell or any of your plugins, and which snapshot to roll back to if it did.

## The problem

Omarchy and Arch updates break third-party plugins now and then. You find out when a widget is missing or the bar is gone, and then you roll back blind: which snapshot was the one before the update?

Omarchy already takes a Snapper snapshot before every update (`omarchy-snapshot create`). This plugin does not take another one. It records which snapshot that was, checks everything once the update is done, and only bothers you when something broke.

## Install

```bash
omarchy plugin add https://github.com/Nejcc/omarchy-safe-update.git
```

Enable it, click the shield in the bar and press **Install hooks**. That copies two small hook files into `~/.config/omarchy/hooks/post-update.d/` and `post-boot.d/`. **Remove hooks** deletes them again. Nothing runs after updates until you install them.

## Uninstall

```sh
omarchy plugin remove nejcc.safe-update
```

If you installed the hooks, click **Remove hooks** in the panel first (or run `bash ~/.config/omarchy/plugins/nejcc.safe-update/bin/safe-update hooks remove`). Leftover hooks exit quietly once the plugin is gone. State lives in `~/.local/state/omarchy-safe-update/`.

## Usage

The panel shows:

- **Last check**: when it ran, the Omarchy version before and after, and whether anything broke.
- **Rollback**: the snapshot Omarchy took before that update and how to get back to it. Rollback is never automatic. Reboot, open *Snapshots* in the Limine boot menu and pick that entry. Once you are booted into the snapshot, the panel offers **Restore snapshot**, which opens a terminal running `omarchy-snapshot restore` (`limine-snapper-restore`). On the live system, **List snapshots** opens a terminal with `sudo snapper -c root list`.
- **Plugins**: every plugin in `~/.config/omarchy/plugins/`, with failed validation or QML errors listed under its name.
- **Check now** (or `c`): runs the same check right away and scans the shell log since boot.

IPC: `omarchy-shell nejcc.safe-update open|close|toggle|check`.

## How it works

`bin/safe-update` does all the work. The panel never needs root.

1. `post-update` hook: `omarchy update` calls it after packages and migrations. It reads `/tmp/omarchy-update.log` to see whether Omarchy's snapshot succeeded, and `/var/log/pacman.log` for the Omarchy version from before the upgrade. That version is the label Omarchy gives the snapshot. It writes this to `pending.json` and starts a detached waiter.
2. The waiter waits for the update lock to free up (the update restarts the shell at the very end), then for the new shell to answer, then gives plugins 15 seconds to load.
3. The check runs `omarchy plugin validate` on every installed plugin and `omarchy-shell shell ping`, and scans `journalctl --user -t omarchy-shell` since the update for QML errors under a plugin's path and for shell crashes. The result goes to `$XDG_STATE_HOME/omarchy-safe-update/last.json`.
4. If something broke, you get one critical notification that opens the panel. If everything is fine, it stays quiet.
5. `post-boot` hook: if the update ended in a reboot before the check ran, the check runs after the next login.

The widget watches `last.json` and the hook file, so it does nothing between updates.

## Runtime deps

`jq`, `flock`/`setsid` (util-linux), `journalctl`. All of these come with Omarchy. Snapper and limine-snapper-sync are optional. Without them the panel says updates are not snapshotted.

## Limits

- Snapper only lets root, or users in its `ALLOW_USERS`, list snapshots. Without that access the panel shows the snapshot by its description (the pre-update Omarchy version) and time instead of its number.
- The plugin manifest has no field for compatible Omarchy versions, so the compatibility check is: does the plugin still validate, and did it log QML errors after the update? Runtime-only bugs that don't log aren't caught.
- Error matching is a pattern over the shell log. Known noise (duplicate IPC handlers on hot reload, a state file that doesn't exist yet) is ignored.
- Only `omarchy update` runs the hooks. A plain `pacman -Syu` is not checked; use **Check now** after one.

## Tests

```bash
bash tests/check.test.sh
```

## License

MIT

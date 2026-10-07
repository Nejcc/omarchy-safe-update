#!/bin/bash

# Runs bin/safe-update against stubbed omarchy, journal and snapper commands.
# Run with: bash tests/check.test.sh

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fails=0
assert() {
  if [[ $2 == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected '$3', got '$2'"
    fails=$((fails + 1))
  fi
}

mkdir -p "$tmp/bin" "$tmp/plugins" "$tmp/state" "$tmp/hooks"
export PATH="$tmp/bin:$PATH"
export SAFE_UPDATE_STATE_DIR=$tmp/state SAFE_UPDATE_PLUGINS_DIR=$tmp/plugins SAFE_UPDATE_HOOKS_DIR=$tmp/hooks
export SAFE_UPDATE_UPDATE_LOG=$tmp/update.log SAFE_UPDATE_PACMAN_LOG=$tmp/pacman.log SAFE_UPDATE_SETTLE=0

stub() {
  printf '#!/bin/bash\n%s\n' "$2" >"$tmp/bin/$1"
  chmod +x "$tmp/bin/$1"
}

plugin() {
  mkdir -p "$tmp/plugins/$1"
  printf '{"id":"%s","name":"%s"}' "$2" "$3" >"$tmp/plugins/$1/manifest.json"
}

plugin good acme.good "Good"
plugin broken acme.broken "Broken"
plugin noisy acme.noisy "Noisy"
mkdir -p "$tmp/plugins/not-a-plugin"

stub omarchy-version 'echo 4.0.5-1'
# shellcheck disable=SC2016 # stub bodies expand when the stub runs
stub omarchy '[[ $3 == *broken ]] && { echo "omarchy-plugin-validate: missing required field version" >&2; exit 1; }; exit 0'
# shellcheck disable=SC2016
stub omarchy-shell '[[ -f '"$tmp"'/shell-down ]] && exit 1
case $2 in
  ping) echo ok ;;
  listPlugins) echo "[{\"id\":\"acme.good\",\"enabled\":true},{\"id\":\"acme.noisy\",\"enabled\":false}]" ;;
esac'
stub journalctl "cat '$tmp/journal'"
stub snapper 'exit 1'
stub omarchy-notification-send "echo \"\$@\" >'$tmp/notified'"
stub setsid "echo \"\$@\" >'$tmp/setsid'"

esc=$'\e'
cat >"$tmp/journal" <<EOF
${esc}[33m  WARN${esc}[0m scene: file:///home/u/.config/omarchy/plugins/good/Panel.qml[4:3]: Handler was registered but will not be used because another handler is registered for target acme.good
  WARN scene: QML FileView at file:///home/u/.config/omarchy/plugins/noisy/Service.qml[53:3]: Read of /x.json failed: File does not exist.
  WARN scene: file:///home/u/.config/omarchy/plugins/noisy/Bar.qml[12:5]: TypeError: Cannot read property 'x' of null
  WARN scene: file:///home/u/.config/omarchy/plugins/noisy/Bar.qml[12:5]: TypeError: Cannot read property 'x' of null
  WARN scene: file:///home/u/.config/omarchy/plugins/goodies/Bar.qml[1:1]: Type Foo unavailable
EOF

# ---- post-update records the snapshot Omarchy took, then detaches
cat >"$tmp/update.log" <<'EOF'
Create system snapshot
Snapshots can be selected during boot.
EOF
cat >"$tmp/pacman.log" <<'EOF'
[2026-10-01T09:00:00+0200] [PACMAN] starting full system upgrade
[2026-10-01T09:00:05+0200] [ALPM] upgraded omarchy (4.0.3-1 -> 4.0.4-1)
[2026-10-07T08:00:00+0200] [PACMAN] starting full system upgrade
[2026-10-07T08:00:05+0200] [ALPM] upgraded omarchy (4.0.4-1 -> 4.0.5-1)
EOF

OMARCHY_UPDATE_LOCK_FD=9 "$root/bin/safe-update" post-update 9>"$tmp/lock"
pending=$tmp/state/pending.json
assert "pending snapshot state" "$(jq -r .snapshot.state "$pending")" taken
assert "snapshot label is the pre-update version" "$(jq -r .snapshot.label "$pending")" 4.0.4-1
assert "snapshot number unknown without snapper access" "$(jq -r .snapshot.number "$pending")" null
assert "waiter detached" "$(cat "$tmp/setsid")" "-f $root/bin/safe-update wait-check"

stub snapper 'echo "{\"root\":[{\"number\":41,\"description\":\"4.0.4-1\"},{\"number\":42,\"description\":\"4.0.4-1\"},{\"number\":43,\"description\":\"other\"}]}"'
"$root/bin/safe-update" post-update
assert "snapshot number when snapper answers" "$(jq -r .snapshot.number "$pending")" 42

: >"$tmp/update.log"
printf 'Continuing the update without a snapshot.\n' >"$tmp/update.log"
"$root/bin/safe-update" post-update
assert "failed snapshot is reported" "$(jq -r .snapshot.state "$pending")" failed
printf 'Create system snapshot\nSnapshots can be selected during boot.\n' >"$tmp/update.log"
"$root/bin/safe-update" post-update

# ---- the check itself
"$root/bin/safe-update" check
last=$tmp/state/last.json
assert "status broken" "$(jq -r .status "$last")" broken
assert "pending consumed" "$([[ -f $pending ]] && echo yes || echo no)" no
assert "snapshot carried into the report" "$(jq -r .snapshot.number "$last")" 42
assert "version after" "$(jq -r .versionAfter "$last")" 4.0.5-1
assert "broken plugins counted" "$(jq -r .broken "$last")" 2
assert "broken plugins sorted first" "$(jq -r '[.plugins[].id] | join(",")' "$last")" "acme.broken,acme.noisy,acme.good"
assert "validate error kept" "$(jq -r '.plugins[0].validateError' "$last")" "omarchy-plugin-validate: missing required field version"
assert "QML error attributed, deduped, prefix stripped" "$(jq -r '.plugins[1].errors | join("|")' "$last")" \
  "file:///home/u/.config/omarchy/plugins/noisy/Bar.qml[12:5]: TypeError: Cannot read property 'x' of null"
assert "noise and other dirs ignored" "$(jq -r '.plugins[2] | "\(.ok) \(.errors | length)"' "$last")" "true 0"
assert "enabled from listPlugins" "$(jq -r '[.plugins[].enabled] | map(tostring) | join(",")' "$last")" "null,false,true"
assert "non-plugin dirs skipped" "$(jq -r '.plugins | length' "$last")" 3
assert "notified with names" "$(cat "$tmp/notified")" \
  "-u critical -g $(printf '') Update broke something Broken, Noisy --exec omarchy-shell nejcc.safe-update open"

# ---- a clean run stays quiet
rm -rf "$tmp/plugins/broken" "$tmp/plugins/noisy" "$tmp/notified"
"$root/bin/safe-update" check
wait
assert "clean run ok" "$(jq -r .status "$last")" ok
assert "manual check flagged" "$(jq -r .manual "$last")" true
assert "no notification when ok" "$([[ -f $tmp/notified ]] && echo yes || echo no)" no

touch "$tmp/shell-down"
"$root/bin/safe-update" check --no-notify
assert "dead shell is broken" "$(jq -r '"\(.status) \(.shell.ok)"' "$last")" "broken false"
assert "--no-notify stays quiet" "$([[ -f $tmp/notified ]] && echo yes || echo no)" no
rm "$tmp/shell-down"

printf 'Omarchy shell exited with status 1; relaunching.\n' >"$tmp/journal"
"$root/bin/safe-update" check --no-notify
assert "shell crash loop is broken" "$(jq -r '"\(.status) \(.shell.restarts)"' "$last")" "broken 1"

# ---- hook install and removal
"$root/bin/safe-update" hooks install
for point in post-update post-boot; do
  hook=$tmp/hooks/$point.d/nejcc-safe-update
  assert "$point hook installed and executable" "$([[ -x $hook ]] && echo yes)" yes
  assert "$point hook points at the plugin" "$(grep -c "check=\"$root/bin/safe-update\"" "$hook")" 1
done
assert "post-boot without pending does nothing" "$(rm -f "$tmp/setsid" && bash "$tmp/hooks/post-boot.d/nejcc-safe-update" && [[ -f $tmp/setsid ]] && echo ran || echo idle)" idle
"$root/bin/safe-update" hooks remove
assert "hooks removed" "$(find "$tmp/hooks" -type f | wc -l)" 0

if ((fails > 0)); then
  echo "$fails failed"
  exit 1
fi
echo "all passed"

#!/usr/bin/env bash
# Install the distribution package and this repository's MX Master 3S config.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: sudo ./install.sh
       ./install.sh --dry-run
       ./install.sh --help

Install logiops with apt, back up the existing configuration, apply logid.cfg,
enable logid at boot, restart it, and display its status and recent logs.
Supported: Debian/Ubuntu with systemd and a logiops package in enabled apt sources.
--dry-run checks local prerequisites and prints the plan without changing anything.
EOF
}

dry_run=false
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --dry-run) dry_run=true ;;
    '') ;;
    *) usage >&2; exit 2 ;;
esac
if (( $# > 1 )); then usage >&2; exit 2; fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config="$repo_dir/logid.cfg"
[[ -s "$config" ]] || { echo "Missing configuration: $config" >&2; exit 1; }
for tool in apt-get apt-cache systemctl; do
    command -v "$tool" >/dev/null || { echo "Required command missing: $tool. This installer supports Debian/Ubuntu with systemd." >&2; exit 1; }
done
[[ -d /run/systemd/system ]] || { echo 'A running systemd system is required.' >&2; exit 1; }

if "$dry_run"; then
    cat <<EOF
Source configuration: $config
1. Refresh apt metadata and check that logiops is available.
2. Back up /etc/logid.cfg, the loaded service definition, and any /usr/local/bin/logid.
3. Install the distribution logiops package and its runtime dependencies.
4. Install the repository config at /etc/logid.cfg.
5. Archive the legacy /usr/local/bin/logid, if present.
6. Set logid's ExecStart to /usr/bin/logid with a systemd drop-in.
7. Enable and restart logid; check it after five seconds and show logs.
If restarting fails, restore the previous config and attempt to restart it.
EOF
    exit 0
fi

(( EUID == 0 )) || { echo 'Run: sudo ./install.sh (or use --dry-run without sudo).' >&2; exit 1; }

# Check availability before interrupting a working mouse daemon.
apt-get update
candidate=$(LC_ALL=C apt-cache policy logiops | awk '/Candidate:/ {print $2}')
if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
    echo 'No logiops package is available. Enable the appropriate repository (Ubuntu: universe), or use a supported distribution release.' >&2
    exit 1
fi

backup=$(mktemp -d /var/backups/mx-master-3s-gestures.XXXXXXXX)
had_config=false
if [[ -e /etc/logid.cfg ]]; then
    cp -a /etc/logid.cfg "$backup/logid.cfg"
    had_config=true
fi
systemctl cat logid > "$backup/logid.service.txt" 2>/dev/null || true
if [[ -e /usr/local/bin/logid ]]; then
    cp -a /usr/local/bin/logid "$backup/logid.local"
fi
echo "Backup: $backup"

restore_config() {
    if "$had_config"; then
        cp -a --remove-destination "$backup/logid.cfg" /etc/logid.cfg
    else
        rm -f /etc/logid.cfg
    fi
}
recover() {
    code=$?
    trap - ERR
    echo "Installation failed. Restoring the previous configuration from $backup." >&2
    restore_config
    systemctl daemon-reload || true
    systemctl restart logid || true
    journalctl -u logid -n 30 --no-pager >&2 || true
    echo 'Package installation and service changes are retained; see README.md for recovery.' >&2
    exit "$code"
}
trap recover ERR

# The package manager may start the service while installing. Preserve the old
# config during that step, then explicitly apply the repository version below.
if systemctl is-active --quiet logid; then systemctl stop logid; fi
apt-get -y -o Dpkg::Options::=--force-confold install logiops
[[ -x /usr/bin/logid ]] || { echo 'The package did not provide /usr/bin/logid.' >&2; false; }
if [[ -e /usr/local/bin/logid ]]; then
    rm -- /usr/local/bin/logid  # Already saved in the unique backup directory.
fi
install -d -m 0755 /etc/systemd/system/logid.service.d
override=/etc/systemd/system/logid.service.d/99-mx-master-3s-gestures.conf
if [[ -e "$override" ]]; then cp -a "$override" "$backup/override.conf"; fi
cat > "$override" <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/logid
Restart=on-failure
RestartSec=3
EOF
# Replace symlinks as well: install the reviewed config at the actual target path.
staged_config=$(mktemp /etc/logid.cfg.XXXXXXXX)
install -m 0644 "$config" "$staged_config"
mv -fT "$staged_config" /etc/logid.cfg
systemctl daemon-reload
systemctl enable logid
systemctl restart logid
sleep 5
systemctl is-active --quiet logid
trap - ERR
systemctl status logid --no-pager -l
journalctl -u logid --since '15 seconds ago' -n 30 --no-pager
echo "Installed. Backup: $backup"
echo 'Look for "Device found: MX Master 3S"; wake the mouse if it is asleep.'

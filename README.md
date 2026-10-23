# MX Master 3S gestures on Linux

A [logiops](https://github.com/PixlOne/logiops) configuration and installer for the
Logitech MX Master 3S. Includes thumb-button gestures, SmartShift, and DPI controls.

The configuration comes from an Ubuntu 26.04.1 LTS desktop using logiops v0.3.5
and a Logi Bolt receiver. On that machine the daemon starts and detects the mouse
without configuration errors. Physical gesture behavior still needs a manual
check on your desktop; window actions depend on your keyboard shortcuts.

## Gestures

Hold the indicated button, move the mouse in the direction, then release the
button. Actions happen on release. A click means press and release without moving.
`Super` is the Windows/Meta key.

| Button | Gesture | Action |
| --- | --- | --- |
| Thumb gesture button (`0xc3`) | Click | Super (GNOME overview with default bindings) |
| Thumb gesture button | Left | Super + Left (typically tile left) |
| Thumb gesture button | Right | Super + Right (typically tile right) |
| Thumb gesture button | Up | Super + Up (typically maximize) |
| Thumb gesture button | Down | Super + Down (typically restore) |
| Top wheel-mode button (`0xc4`) | Click | Toggle SmartShift |
| Top wheel-mode button | Up | Increase DPI by 1000 |
| Top wheel-mode button | Down | Decrease DPI by 1000 |

Other settings: 1000 DPI initially, SmartShift enabled with threshold 15,
inverted horizontal thumbwheel, and high-resolution vertical scrolling disabled.
Forward/back buttons retain their normal behavior. See [logid.cfg](logid.cfg) for
the full configuration. The original config's `pollrate` and hiresscroll
`multiplier` fields are omitted because logiops v0.3.5 does not support them.

## Install

Requires Debian/Ubuntu, a running systemd system, network access, sudo, and the
`logiops` package in your enabled apt sources. The installer installs runtime
dependencies through apt; building from source and development packages are not
needed. Other distributions are outside the installer's scope.

```sh
git clone https://github.com/javanoo6/mx-master-3s-gestures.git
cd mx-master-3s-gestures
./install.sh --dry-run
sudo ./install.sh
```

On Ubuntu, if apt cannot find logiops, enable Universe (`sudo add-apt-repository
universe`) and retry. Older distribution releases may not offer this package.

The installer refreshes apt metadata, backs up your current config under
`/var/backups/mx-master-3s-gestures.*`, installs logiops, copies this repo's config
to `/etc/logid.cfg`, and enables/restarts the service. Re-running applies the
config again and creates another backup.

It also archives an existing `/usr/local/bin/logid` in the backup directory and
adds `/etc/systemd/system/logid.service.d/99-mx-master-3s-gestures.conf` to run
`/usr/bin/logid`. This handles old source installations whose library dependencies
no longer match the OS. Existing unrelated drop-ins are preserved. Review any
local overrides if the service still starts a different binary.

## Check and customize

```sh
systemctl status logid --no-pager
journalctl -u logid -b -n 30 --no-pager
```

Expect `active (running)` and `Device found: MX Master 3S`. Wake the mouse and
confirm its connection if detection is delayed. An active daemon alone does not
prove that every gesture works: test thumb-button click, all four thumb gestures,
and the top-button click/up/down gestures from the table above. Check your desktop
keyboard shortcuts if Super + arrow keys do something different.

Edit `logid.cfg` before installation, or edit `/etc/logid.cfg` with sudo afterward.
After editing the installed config, restart the daemon:

```sh
sudo systemctl restart logid
```

## Restore your previous config

Use the backup directory printed by the installer:

```sh
sudo cp -a --remove-destination /var/backups/mx-master-3s-gestures.XXXXXXXX/logid.cfg /etc/logid.cfg
sudo systemctl restart logid
```

If installation fails, the installer restores the previous config automatically
and attempts a restart. It retains the package and service changes; this is config
recovery, not a complete system rollback. If no config existed before installation,
recovery removes the new one.

To undo the installer's service override, remove
`/etc/systemd/system/logid.service.d/99-mx-master-3s-gestures.conf`, or restore
`override.conf` from the backup if it exists, then run `sudo systemctl daemon-reload`
and `sudo systemctl restart logid`. A previous local executable is saved as
`logid.local`; restoring it may reintroduce its old library mismatch.

## Troubleshooting

- **`libconfig++.so.9` missing:** an old source-built binary may still be in use.
  Check `systemctl show logid -p ExecStart`. This installer uses the distro's
  `/usr/bin/logid` and matching dependencies. Avoid symlinking incompatible library
  versions together.
- **`Failed to allocate directory watch: Too many open files`:** check
  `sysctl fs.inotify.max_user_instances`. If that limit is exhausted, a temporary
  increase is `sudo sysctl -w fs.inotify.max_user_instances=1024`. Investigate which
  processes consume instances before making a persistent change. The installer
  does not change kernel limits.
- **Config errors or no gestures:** inspect the journal, check that the device
  name matches `MX Master 3S`, and check your desktop keyboard shortcuts.

## References

Inspired by [MisterAnt92/MxMaster3sLinux](https://github.com/MisterAnt92/MxMaster3sLinux).
The config here comes from our existing setup; the installer is written for this
repository. See the upstream [logiops configuration reference](https://github.com/PixlOne/logiops/wiki/Configuration)
for supported options.

## Development checks

```sh
docker run --rm -v "$PWD:/repo:ro" ubuntu:26.04 bash /repo/tests/integration.sh
```

CI runs ShellCheck, Bash syntax checks, and a real libconfig parser check. It also
checks dry runs, backups, repeated installation, missing packages, and config
recovery after package/restart failures in a disposable container. Package and
service calls are simulated for those scenarios after installing the real Ubuntu
package. These checks do not test a physical mouse or a running systemd daemon.

## License

MIT; see [LICENSE](LICENSE). logiops is a separate project with its own license.

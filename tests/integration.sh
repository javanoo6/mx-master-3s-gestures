#!/usr/bin/env bash
# Run ONLY in a disposable container: this test modifies /etc and /usr/local/bin.
# docker run --rm -v "$PWD:/repo:ro" ubuntu:26.04 bash /repo/tests/integration.sh
set -euo pipefail
[[ -f /.dockerenv ]] || { echo 'Use a disposable Docker container.' >&2; exit 1; }
cd /repo
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y shellcheck gcc libconfig-dev logiops
shellcheck install.sh tests/integration.sh
bash -n install.sh
cc -Wall -Wextra -Werror tests/check-config.c -lconfig -o /tmp/check-config
/tmp/check-config logid.cfg

# Exercise real file changes while simulating systemd and apt after installing
# the real distribution package. No systemd or mouse is available in a container.
mkdir -p /tmp/mock-bin /run/systemd/system /etc/systemd/system/logid.service.d
cat > /tmp/mock-bin/apt-get <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> /tmp/apt-calls
if [[ -e /tmp/fail-apt && "$*" == *install* ]]; then exit 42; fi
EOF
cat > /tmp/mock-bin/apt-cache <<'EOF'
#!/bin/bash
if [[ -e /tmp/no-candidate ]]; then
    echo '  Candidate: (none)'
else
    echo '  Candidate: 0.3.5-test'
fi
EOF
cat > /tmp/mock-bin/systemctl <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> /tmp/service-calls
if [[ "$1" == restart && -e /tmp/fail-restart ]]; then
    rm /tmp/fail-restart
    exit 43
fi
EOF
cat > /tmp/mock-bin/journalctl <<'EOF'
#!/bin/bash
echo 'Simulated journal (no physical mouse in this test).'
EOF
cat > /tmp/mock-bin/sleep <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x /tmp/mock-bin/*
export PATH="/tmp/mock-bin:$PATH"

printf 'original config\n' > /etc/logid.cfg
printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/logid
chmod +x /usr/local/bin/logid
printf '# unrelated override\n' > /etc/systemd/system/logid.service.d/override.conf
before=$(sha256sum /etc/logid.cfg)
./install.sh --dry-run
[[ "$before" == "$(sha256sum /etc/logid.cfg)" ]]
[[ ! -e /tmp/apt-calls && ! -e /tmp/service-calls ]]

./install.sh
cmp logid.cfg /etc/logid.cfg
[[ ! -e /usr/local/bin/logid ]]
grep -q 'ExecStart=/usr/bin/logid' /etc/systemd/system/logid.service.d/99-mx-master-3s-gestures.conf
grep -q 'unrelated override' /etc/systemd/system/logid.service.d/override.conf
grep -q '^restart logid$' /tmp/service-calls
grep -q 'install logiops$' /tmp/apt-calls
grep -rl 'original config' /var/backups/mx-master-3s-gestures.*/logid.cfg
./install.sh  # Applying it twice must work.
cmp logid.cfg /etc/logid.cfg

printf 'restore me\n' > /etc/logid.cfg
cp /etc/logid.cfg /tmp/expected-config
touch /tmp/fail-restart
if ./install.sh; then echo 'Expected restart failure.' >&2; exit 1; else [[ $? == 43 ]]; fi
cmp /tmp/expected-config /etc/logid.cfg

touch /tmp/fail-apt
if ./install.sh; then echo 'Expected package failure.' >&2; exit 1; else [[ $? == 42 ]]; fi
cmp /tmp/expected-config /etc/logid.cfg
rm /tmp/fail-apt

rm /tmp/service-calls
touch /tmp/no-candidate
if ./install.sh; then echo 'Expected unavailable-package failure.' >&2; exit 1; fi
[[ ! -e /tmp/service-calls ]]
cmp /tmp/expected-config /etc/logid.cfg
rm /tmp/no-candidate

rm /etc/logid.cfg
touch /tmp/fail-restart
if ./install.sh; then echo 'Expected restart failure.' >&2; exit 1; else [[ $? == 43 ]]; fi
[[ ! -e /etc/logid.cfg ]]
echo 'Passed: parsing, dry run, install, repeated install, config recovery, and missing package.'

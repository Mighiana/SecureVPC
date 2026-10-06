#!/bin/bash
# Bastion bootstrap: patch the OS and harden sshd. No application software.
set -euo pipefail

dnf -y update --security || true

cat > /etc/ssh/sshd_config.d/90-securevpc.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowAgentForwarding no
AllowTcpForwarding yes
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
CONF

systemctl restart sshd

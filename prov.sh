#!/usr/bin/env bash
# AlmaLinux 9.8 setup helper. Run as root only after reviewing these settings.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "Run with sudo: sudo bash $0" >&2
	exit 1
fi

# Set the requested hostname.
hostnamectl set-hostname TechnovaCutsa

# Create distinct roles. Set unique passwords interactively; never use a shared
# default password. The sudo role receives administrator privileges.
for user in sudo admin logger; do
	if ! id "$user" >/dev/null 2>&1; then
		useradd --create-home "$user"
	fi
	passwd "$user"
done
usermod -aG wheel sudo

# Create a shared Docker project directory for the users created above.
groupadd --force dockercutsa
for user in sudo admin logger; do
	usermod -aG dockercutsa "$user"
done
install -d -o root -g dockercutsa -m 2775 /srv/Docker-Cutsa

# Enable firewalld and open only standard web and SSH ports. Grafana (3000) and
# Alertmanager (9093) remain local; expose them only through a trusted VPN/proxy.
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Install a systemd timer to start the shared-home compose project at boot.
# The timer and service run as the invoking non-root user, not as root.
RUN_USER="${SUDO_USER:-}"
if [[ -z "$RUN_USER" || "$RUN_USER" == root ]]; then
	echo "Invoke via sudo from the non-root account that owns ~/Docker-Cutsa." >&2
	exit 1
fi
PROJECT=/srv/Docker-Cutsa
[[ -f "$PROJECT/compose.yaml" || -f "$PROJECT/docker-compose.yml" ]] || {
	echo "Place compose.yaml or docker-compose.yml in the shared directory $PROJECT first." >&2; exit 1;
}

install -d -m 0755 /etc/systemd/system
cat > /etc/systemd/system/dockercutsa.service <<EOF
[Unit]
Description=Start Docker-Cutsa compose project
Wants=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
User=$RUN_USER
WorkingDirectory=$PROJECT
ExecStart=/usr/bin/docker compose up -d
EOF
cat > /etc/systemd/system/dockercutsa.timer <<'EOF'
[Unit]
Description=Start Docker-Cutsa at boot

[Timer]
OnBootSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now dockercutsa.timer

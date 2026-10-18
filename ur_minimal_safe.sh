#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Minimal & sicher für Ubuntu 24.04 (Bare-metal)
# Download / Ausführung:
#   wget -O ur_minimal_safe.sh https://raw.githubusercontent.com/dokupendium/ubuntu-from-scratch/add/ur_minimal_safe/ur_minimal_safe.sh
#   chmod +x ur_minimal_safe.sh
#   sudo ./ur_minimal_safe.sh
#
# Bitte die Variablen unten vor Ausführung anpassen!

LOCALE="de_DE.UTF-8"
TIMEZONE="Europe/Berlin"
HOSTNAME="rusys-01"
USER="panx"
SSH_PORT="54535"
# Setze hier deinen vollständigen Public Key (z.B. ssh-ed25519 AAAA... user@device)
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAMxRjdR7+oT6OVUfKzEu7+8Fu2IAQY3c6Hhee1EMBpl panx"

# Cosmos Einstellungen (kein Docker)
COSMOS_REPO="https://github.com/azukaar/Cosmos-Server.git"
COSMOS_DIR="/opt/cosmos"
COSMOS_SERVICE="cosmos"

# Optional: Web-Ports automatisch öffnen? 0 = no, 1 = yes (Cosmos benötigt meist 80/443)
OPEN_WEB_PORTS=0

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte als root ausführen."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "== Minimal & Sicher: Ubuntu 24.04 initial setup =="
echo "WICHTIG: Prüfe PUBKEY zuerst. Wenn der Key falsch ist, kannst du dich sperren."
read -r -p "Weiter? (y/N): " ok
if [[ "${ok,,}" != "y" && "${ok,,}" != "yes" ]]; then
  echo "Abgebrochen."
  exit 0
fi

apt update -y
apt upgrade -y

# locale + timezone + hostname
grep -q "^${LOCALE}" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen "${LOCALE}"
update-locale LANG="${LOCALE}"
timedatectl set-timezone "${TIMEZONE}"
hostnamectl set-hostname "${HOSTNAME}"
if ! grep -q "127.0.1.1 ${HOSTNAME}" /etc/hosts 2>/dev/null; then
  echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
fi

# create user if not exists
if id "${USER}" &>/dev/null; then
  echo "User ${USER} existiert bereits."
else
  useradd -m -s /bin/bash -G sudo "${USER}"
  echo "User ${USER} angelegt."
fi
HOME_DIR="$(getent passwd "${USER}" | cut -d: -f6)"
[ -n "${HOME_DIR}" ] || HOME_DIR="/home/${USER}"

# setup SSH for user (avoid duplicate key entries)
mkdir -p "${HOME_DIR}/.ssh"
chmod 700 "${HOME_DIR}/.ssh"
touch "${HOME_DIR}/.ssh/authorized_keys"
chmod 600 "${HOME_DIR}/.ssh/authorized_keys"
if ! grep -Fxq "${PUBKEY}" "${HOME_DIR}/.ssh/authorized_keys"; then
  echo "${PUBKEY}" >> "${HOME_DIR}/.ssh/authorized_keys"
fi
chown -R "${USER}:${USER}" "${HOME_DIR}/.ssh"

# Safety: add same key to root only if not present
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
if ! grep -Fxq "${PUBKEY}" /root/.ssh/authorized_keys 2>/dev/null; then
  echo "${PUBKEY}" >> /root/.ssh/authorized_keys
  echo "INFO: Key temporär auch nach /root/.ssh/authorized_keys geschrieben."
fi

# sshd drop-in
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# Added by ur_minimal_safe_fixed.sh
Port ${SSH_PORT}
PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
AuthorizedKeysFile .ssh/authorized_keys
EOF

# Validate and restart sshd (try both unit names)
sshd -t || { echo "sshd config invalid — Abbruch"; exit 1; }
if systemctl restart ssh 2>/dev/null; then
  echo "sshd über 'ssh' Unit neu gestartet."
elif systemctl restart sshd 2>/dev/null; then
  echo "sshd über 'sshd' Unit neu gestartet."
else
  echo "Warnung: Konnte sshd nicht neu starten via systemctl. Prüfe 'systemctl status sshd'/'ssh'."
fi

# Install essentials (ufw, fail2ban, unattended-upgrades, git)
apt install -y ufw fail2ban unattended-upgrades git

ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"
if [ "${OPEN_WEB_PORTS}" -eq 1 ]; then
  ufw allow 80/tcp
  ufw allow 443/tcp
fi
ufw --force enable

systemctl enable --now fail2ban

# Swap (4G)
if [ ! -f /swapfile ]; then
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
  else
    dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
  fi
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  sysctl -p || true
fi

# Python + build essentials
apt install -y python3 python3-pip python3-venv build-essential

# Clone Cosmos (baremetal, no Docker)
if [ ! -d "${COSMOS_DIR}" ]; then
  git clone --depth 1 "${COSMOS_REPO}" "${COSMOS_DIR}"
  chown -R "${USER}:${USER}" "${COSMOS_DIR}"
fi

# Ensure start.sh executable and create systemd unit
if [ -f "${COSMOS_DIR}/start.sh" ]; then
  chmod +x "${COSMOS_DIR}/start.sh"
fi

cat > /etc/systemd/system/${COSMOS_SERVICE}.service <<EOF
[Unit]
Description=Cosmos Server (baremetal)
After=network.target

[Service]
User=${USER}
Group=${USER}
WorkingDirectory=${COSMOS_DIR}
ExecStart=${COSMOS_DIR}/start.sh
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${COSMOS_SERVICE}.service || echo "Service konnte nicht sofort gestartet — prüfe 'journalctl -u ${COSMOS_SERVICE}.service'"

echo

echo "=== Nächste, wichtige manuelle Schritte (UNBEDINGT) ==="
echo "1) Melde dich in einem NEUEN SSH-Fenster an als ${USER}:"
echo "   ssh -i <dein_privkey> -p ${SSH_PORT} ${USER}@<server-ip>"
echo "   Oder teste root: ssh -i <dein_privkey> -p ${SSH_PORT} root@<server-ip> (falls benötigt)"
echo

echo "2) Wenn Login funktioniert, entferne den Key aus /root/.ssh/authorized_keys:"
echo "   sudo sed -i '/${PUBKEY//\//\\/}/d' /root/.ssh/authorized_keys"
echo 
echo "3) Danach kannst du root logins komplett deaktivieren (streng):"
echo "   sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config.d/99-hardening.conf"
echo "   sudo sshd -t && sudo systemctl restart ssh || sudo systemctl restart sshd"
echo
echo "4) Prüfe Cosmos Service:"
echo "   sudo systemctl status ${COSMOS_SERVICE}.service"
echo "   sudo journalctl -u ${COSMOS_SERVICE}.service -f"
echo
echo "ENDE."

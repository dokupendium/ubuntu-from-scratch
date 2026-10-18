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

# --- Automatisierte Nachschritte: Root-Key Entfernen, Root deaktivieren, Cosmos prüfen ---

# prompt to proceed with removal/disabling
read -r -p $'\nHast du dich in einem NEUEN SSH-Fenster als \"'"${USER}"'\" angemeldet und getestet?\nWenn ja, kann das Script nun den root-Key entfernen und root-Login endgültig deaktivieren.\n\nWeiter? (y/N): ' proceed
if [[ "${proceed,,}" == "y" || "${proceed,,}" == "yes" ]]; then
  # Remove the exact PUBKEY line from root authorized_keys safely
  if [ -f /root/.ssh/authorized_keys ]; then
    # Use temporary file to avoid truncation if same file
    grep -Fvx -- "${PUBKEY}" /root/.ssh/authorized_keys > /root/.ssh/authorized_keys.tmp || true
    mv /root/.ssh/authorized_keys.tmp /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "Removed specified public key from /root/.ssh/authorized_keys (if it existed)."
  else
    echo "/root/.ssh/authorized_keys not found; nothing to remove."
  fi

  # Set PermitRootLogin to no in our drop-in (or /etc/ssh/sshd_config if needed)
  if [ -f /etc/ssh/sshd_config.d/99-hardening.conf ]; then
    if grep -q "^PermitRootLogin" /etc/ssh/sshd_config.d/99-hardening.conf; then
      sed -i "s/^PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config.d/99-hardening.conf
    else
      echo "PermitRootLogin no" >> /etc/ssh/sshd_config.d/99-hardening.conf
    fi
    echo "Set PermitRootLogin no in /etc/ssh/sshd_config.d/99-hardening.conf"
  else
    # fallback to main sshd_config
    if grep -q "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null; then
      sed -i "s/^PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
    else
      echo "PermitRootLogin no" >> /etc/ssh/sshd_config
    fi
    echo "Set PermitRootLogin no in /etc/ssh/sshd_config"
  fi

  # Validate and restart ssh
  if sshd -t; then
    if systemctl restart ssh 2>/dev/null; then
      echo "sshd neu gestartet (unit: ssh)."
    elif systemctl restart sshd 2>/dev/null; then
      echo "sshd neu gestartet (unit: sshd)."
    else
      echo "Warnung: Konnte sshd nicht neu starten via systemctl. Prüfe manuell."
    fi
  else
    echo "Fehlerhafte sshd-Konfiguration nach Änderungen. Abbruch - überprüfe /etc/ssh/..."
  fi
else
  echo "Übersprunge Entfernen des root-Keys und Deaktivierung von root-Login. Du kannst dies manuell später ausführen."
fi

# Cosmos service check
echo -e "\n--- Cosmos Service Check ---\n"
if systemctl list-units --type=service --all | grep -q "${COSMOS_SERVICE}.service"; then
  status=$(systemctl is-active ${COSMOS_SERVICE}.service || true)
  echo "Service ${COSMOS_SERVICE}.service status: ${status}"
  echo "Letzte 200 Journal-Zeilen (wenn vorhanden):"
  journalctl -u ${COSMOS_SERVICE}.service -n 200 --no-pager || true
else
  echo "Service ${COSMOS_SERVICE}.service ist nicht registriert. Stelle sicher, dass ${COSMOS_DIR}/start.sh existiert und die systemd Unit korrekt ist."
fi


echo -e "\nFertig. Wenn du root vollständig gesperrt hast, behalte einen sudo-Benutzer mit deinem Key für den Zugriff."

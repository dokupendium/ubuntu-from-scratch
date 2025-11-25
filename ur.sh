#!/bin/bash
set -euo pipefail

  ##############################################################################################
 #|#   ~ Ubuntu From Scratch ~    # | #    Version: 0.3    # | #    Last Update: 2025-11-25   #|#
## ============================================================================================ ##
##  Description:                                                                                ##
##     This script aims to automate the initial setup of a fresh Ubuntu installation and is     ##
##     ment to be run on a new server or virtual machine. It is not a full solution but rather  ##
##     a starting point for further customization. It is work in progress and you are welcome   ##
##     to contribute, just open an issue or a pull request at                                   ##
##     https://github.com/dokupendium/ubuntu-from-scratch.                                      ##
## ============================================================================================ ##
##  Usage:                                                                                      ##
##     1. Check for the latest version at https://github.com/dokupendium/ubuntu-from-scratch.   ##
##     2. Download the script to your server or virtual machine and make it executable.         ##
##        `wget https://raw.githubusercontent.com/dokupendium/ubuntu-from-scratch/main/ur.sh`   ##
##        `chmod +x ur.sh`                                                                      ##
##     3. Please review the code first and make sure you understand what it does.               ##
##        `nano ur.sh`                                                                          ##
##     3. Set the variables below to your needs.                                                ##
##     4. Run the script with `sudo bash ur.sh`.                                                ##
##     5. Follow the instructions and reboot the system.                                        ##
## ============================================================================================ ##
##  Disclaimer:                                                                                 ##
##     This script is provided as is and you are responsible for any consequences of usage.     ##
##     Always review the code first and make sure you understand what it does.                  ##
##     You may #outcomment or remove any parts of the script that you do not want to run.       ##
##     Contributions and suggestions are welcome.                                               ##
## ============================================================================================ ##
##  License:                                                                                    ##
##     This script is licensed under the MIT License.                                           ##
## ============================================================================================ ##
##  Credits:                                                                                    ##
##     This script is based on the work of many other scripts and tutorials. I would like to    ##
##     thank all the authors and contributors for their work, to many to list here.             ##
##     If you feel that you should be mentioned here, please let me know.                       ##
## ============================================================================================ ##
##  Changelog:                                                                                  ##
##     2025-05-16: Initial version.                                                             ##
##     2025-11-19: Added   -> Root-Check, Swap Configuration, New Variables hostname & pubkey   ##
##                 Changed -> Updated Docker (Compose) Installation                             ##
##     2025-11-25: Added -> Password for sudo                                                   ##
##                 Changed  -> Fix minor bugs                                                   ##
## ============================================================================================ ##
##  To Do:                                                                                      ##
##     - Add more packages and configurations.                                                  ##
##     - Add more security features.                                                            ##
##     - Add more customization options.                                                        ##
##     - Add more documentation.                                                                ##
##     - Add more error handling.                                                               ##
##     - Add more comments.                                                                     ##
##     - Add more testing.                                                                      ##
##     - Add more contributors.                                                                 ##
## ============================================================================================ ##
##  Contributors:                                                                               ##
##     - ~ mimic ~                                                                              ##
##     - **hopefully you!**                                                                     ##
## ============================================================================================ ##
 ##                             Thank you for using this script!                               ##
  ##############################################################################################


 ################################
#|#       ~ VARIABLES ~        #|#
 ################################

# Set the variables below to your needs
locale="de_DE.UTF-8"                                                                
timezone="Europe/Berlin"
hostname="HostName"                                                                          
user="UserName"                                                                        
ssh_port="22"
pubkey="ssh-ed25519 AAAAC3...YOUR_KEY... user@local"                                                                                       


 ################################
#|#      ~ SCRIPT LOGIC ~      #|#
 ################################

# check root privilege
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root!"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# set the locale
locale-gen $locale
update-locale LANG=$locale

# set the timezone
timedatectl set-timezone $timezone

# set the hostname
hostnamectl set-hostname "$hostname"
echo "127.0.0.1 $hostname" >> /etc/hosts

# create new user and add to sudo group (sudo bleibt passwortgeschuetzt)
if id "$user" &>/dev/null; then
  echo "User $user already exists."
else
  adduser --gecos "" "$user"
fi
# set password from secrets if provided; fallback to random, hashed value (PasswordAuthentication stays off)
if passwd -S "$user" | awk '{print $2}' | grep -qE 'NP|L'; then
  if [ -n "${USER_PASSWORD_HASH:-}" ]; then
    echo "$user:$USER_PASSWORD_HASH" | chpasswd -e
  elif [ -n "${USER_PASSWORD:-}" ]; then
    echo "$user:$USER_PASSWORD" | chpasswd
  else
    rand_pw=$(openssl rand -base64 32)
    hash_pw=$(printf "%s" "$rand_pw" | openssl passwd -6 -stdin)
    echo "$user:$hash_pw" | chpasswd -e
    unset rand_pw hash_pw
  fi
fi
usermod -aG sudo "$user"

# copy the ssh keys for new user
if [ ! -d /home/$user/.ssh ]; then
  mkdir -p /home/$user/.ssh
  chmod 700 /home/$user/.ssh
fi
touch /home/$user/.ssh/authorized_keys
chmod 600 /home/$user/.ssh/authorized_keys
chown -R $user:$user /home/$user/.ssh
if ! grep -Fxq "$pubkey" /home/$user/.ssh/authorized_keys; then
  echo "$pubkey" >> /home/$user/.ssh/authorized_keys
fi

# backup and configure the ssh server
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i -e '/^\(#\|\)PermitRootLogin/s/^.*$/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)PasswordAuthentication/s/^.*$/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -e "/^\(#\|\)Port/s/^.*$/Port $ssh_port/" /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)KbdInteractiveAuthentication/s/^.*$/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)ChallengeResponseAuthentication/s/^.*$/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)MaxAuthTries/s/^.*$/MaxAuthTries 2/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)AllowTcpForwarding/s/^.*$/AllowTcpForwarding no/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)X11Forwarding/s/^.*$/X11Forwarding no/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)AllowAgentForwarding/s/^.*$/AllowAgentForwarding no/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)AuthorizedKeysFile/s/^.*$/AuthorizedKeysFile .ssh\/authorized_keys/' /etc/ssh/sshd_config
if ! grep -q "^AllowUsers $user" /etc/ssh/sshd_config; then
    echo "AllowUsers $user" >> /etc/ssh/sshd_config
fi
sshd -t || { echo "Check SSH-Configuration!"; exit 1; }
systemctl restart sshd

# update index and upgrade packages
apt update && apt upgrade -y

# install and enable unattended security upgrades and set a daily update interval
apt install unattended-upgrades -y
dpkg-reconfigure --priority=low unattended-upgrades

# configure the firewall
if ! command -v ufw &>/dev/null; then
  apt install ufw -y
fi
ufw default deny incoming
ufw default allow outgoing
ufw allow $ssh_port/tcp
if ufw status | grep -q inactive; then
  echo "y" | ufw enable
fi

# install and configure fail2ban
apt install fail2ban -y
if [ ! -f /etc/fail2ban/jail.local ]; then
  cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
fi
systemctl enable fail2ban
systemctl start fail2ban

# configure swap file
if [ ! -f /swapfile ]; then
    echo "Erstelle Swapfile..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    echo "vm.swappiness=10" | tee -a /etc/sysctl.conf
    sysctl -p
else
    echo "Swapfile existiert bereits."
fi

# install and configure docker (commpose)
apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
if ! apt-cache policy docker-ce | grep -q 'Candidate:'; then
  echo "Docker-CE Paket nicht gefunden!"; exit 1;
fi
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
usermod -aG docker "$user"

# install python and development tools
apt install -y python3 python3-pip python3-dev python3-venv build-essential libssl-dev libffi-dev

# reboot the system
read -p "Reboot System Now? (y/n): " confirm && [[ $confirm == [yY] ]] && reboot

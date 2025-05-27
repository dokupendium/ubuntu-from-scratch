#!/bin/bash
set -euo pipefail

  ##############################################################################################
 #|#   ~ Ubuntu From Scratch ~    # | #    Version: 0.1     # | #    Last Update: 2025-05-23   #|#
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
##     2. If your hoster supports initiazation scripts, you can copy-paste it. Otherwise        ##
##        Download the script to your server or virtual machine and make it executable.         ##
##        `wget https://raw.githubusercontent.com/dokupendium/ubuntu-from-scratch/main/ur.sh`   ##
##        `chmod +x ur.sh`                                                                      ##
##     3. Please review the code first and make sure you understand what it does.               ##
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
user="Username"                                                                        
ssh_port="22"                                                                                       


 ################################
#|#      ~ SCRIPT LOGIC ~      #|#
 ################################

# set the locale
locale-gen $locale
update-locale LANG=$locale

# set the timezone
timedatectl set-timezone $timezone

# create new user and add to sudo group
if id "$user" &>/dev/null; then
  echo "Benutzer $user existiert bereits."
else
  adduser $user
  usermod -aG sudo $user
fi

# copy the ssh keys for new user
if [ -d ~/.ssh ]; then
  rsync --archive --chown=$user:$user ~/.ssh /home/$user
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
sed -i "$a AllowUsers $user" /etc/ssh/sshd_config
sshd -t || { echo "SSH-Konfiguration fehlerhaft!"; exit 1; }
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
ufw status | grep -q inactive && echo "y" | ufw enable

# install and configure fail2ban
apt install fail2ban -y
if [ ! -f /etc/fail2ban/jail.local ]; then
  cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
fi
systemctl enable fail2ban
systemctl start fail2ban

# install and configure docker
apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
if ! apt-cache policy docker-ce | grep -q 'Candidate:'; then
  echo "Docker-CE Paket nicht gefunden!"; exit 1;
fi
apt install docker-ce -y
usermod -aG docker $user

# install docker-compose (architekturabhängig)
ARCH=$(uname -m)
mkdir -p ~/.docker/cli-plugins
if [ "$ARCH" = "x86_64" ]; then
  curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
elif [ "$ARCH" = "aarch64" ]; then
  curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64 -o ~/.docker/cli-plugins/docker-compose
else
  echo "Nicht unterstützte Architektur: $ARCH"; exit 1;
fi
chmod +x ~/.docker/cli-plugins/docker-compose

# install python and development tools
apt install -y python3 python3-pip python3-dev python3-venv build-essential libssl-dev libffi-dev

# reboot the system
read -p "System jetzt neu starten? (y/n): " confirm && [[ $confirm == [yY] ]] && reboot

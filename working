FROM ubuntu:22.04

# 1. Non-interactive frontend core standard configurations ke liye
ENV DEBIAN_FRONTEND=noninteractive

# 2. CONVERT MINIMAL IMAGE TO FULL CLOUD/SERVER IMAGE
# 'unminimize' command saare missing real server components aur man-pages wapas layegi
RUN apt-get update -qq && yes | unminimize

# 3. Install 'ubuntu-standard' (Real VM packages) aur baki utilities
RUN apt-get install -y -qq \
  ubuntu-standard \
  openssh-server \
  sudo \
  curl \
  wget \
  nano \
  vim \
  net-tools \
  iputils-ping \
  htop \
  screen \
  tmux \
  git \
  python3 \
  python3-pip \
  unzip \
  zip \
  build-essential \
  jq \
  ca-certificates \
  openssl \
  neofetch \
  iptables \
  bc \
  rsync \
  man-db \
  locales && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# System locale generate karein taaki terminal characters real cloud VM jaise chalein
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# 4. SSHD standard configurations aur host keys setup
RUN ssh-keygen -A && mkdir -p /run/sshd

# 5. Hostname configuration ('dev' permanent prompt setup)
RUN echo "dev" > /etc/hostname

# 6. Standard Global Bashrc Profiles
RUN printf "export PS1='\\\\[\\\\e[32m\\\\]\\\\u\\\\[\\\\e[0m\\\\]@\\\\[\\\\e[36m\\\\]dev\\\\[\\\\e[0m\\\\]:\\\\[\\\\e[33m\\\\]\\\\w\\\\[\\\\e[0m\\\\]\\\\$ '\nalias ls='ls --color=auto'\nalias ll='ls -alF'\nalias la='ls -la'\nalias cls='clear'\nalias c='clear'\nalias ports='ss -tuln'\nalias free='free -h'\n" >> /etc/bash.bashrc

# 7. Dynamic Real Cloud Initialization Script
RUN printf '#!/bin/bash\n\
\n\
# Force SSHD to accept password authentication globally on Port 22\n\
cat > /etc/ssh/sshd_config << SSHEOF\n\
Port 22\n\
PermitRootLogin yes\n\
PasswordAuthentication yes\n\
PubkeyAuthentication no\n\
PermitEmptyPasswords no\n\
UsePAM yes\n\
PrintMotd yes\n\
ChallengeResponseAuthentication yes\n\
KbdInteractiveAuthentication yes\n\
AcceptEnv LANG LC_*\n\
Subsystem sftp /usr/lib/openssh/sftp-server\n\
SSHEOF\n\
\n\
# Setup Real VM Account User Environment\n\
USERNAME="toxic"\n\
PASSWORD=${SSH_PASS:-toxic123}\n\
\n\
useradd -m -s /bin/bash "${USERNAME}" 2>/dev/null || true\n\
echo "${USERNAME}:${PASSWORD}" | chpasswd\n\
echo "root:${PASSWORD}" | chpasswd\n\
\n\
mkdir -p /etc/sudoers.d\n\
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USERNAME}\n\
chmod 440 /etc/sudoers.d/${USERNAME}\n\
usermod -aG sudo "${USERNAME}"\n\
\n\
cp /etc/bash.bashrc /home/${USERNAME}/.bashrc 2>/dev/null || true\n\
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}\n\
\n\
# ════════════════════════════════════════════════════════════════\n\
# DYNAMIC DEPLOYMENT LOGS PRINTING SYSTEM\n\
# ════════════════════════════════════════════════════════════════\n\
echo ""\n\
echo "=================================================="\n\
echo "⚡ FULL UBUNTU 22.04 CLOUD SERVER IS NOW LIVE!"\n\
echo "=================================================="\n\
echo "👤 Username     : ${USERNAME}"\n\
echo "🔑 SSH Password : ${PASSWORD}"\n\
echo "🔌 Default Port : 22 (All inbound/outbound ports open)"\n\
echo ""\n\
echo "🔗 HOW TO CONNECT VIA TERMINAL / PC / MOBILE:"\n\
echo "ssh ${USERNAME}@zephyr.proxy.rlwy.net -p 37658"\n\
echo "=================================================="\n\
echo ""\n\
\n\
exec /usr/sbin/sshd -D -p ${PORT:-22}\n\
' > /entrypoint.sh && chmod +x /entrypoint.sh

# Port 22 standard exposing
EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]

FROM ubuntu:22.04

# 1. Non-interactive frontend set karein
ENV DEBIAN_FRONTEND=noninteractive

# 2. Saare zaroori packages install karein jo toxic.sh ko chahiye (Minus Docker)
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
  openssh-server sudo curl wget nano vim \
  net-tools iputils-ping htop screen tmux \
  git python3 python3-pip unzip zip \
  build-essential jq ca-certificates openssl \
  nmap dnsutils netcat-openbsd socat \
  neofetch iptables bc && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. SSH Host keys aur directories banayein
RUN ssh-keygen -A && mkdir -p /run/sshd /etc/iptables

# 4. Fake Ubuntu 22.04 OS environment setup (Branding)
RUN echo "Ubuntu 22.04.5 LTS" > /etc/issue && \
    echo "Ubuntu 22.04.5 LTS" > /etc/issue.net && \
    printf 'PRETTY_NAME="Ubuntu 22.04.5 LTS"\nNAME="Ubuntu"\nVERSION_ID="22.04"\nVERSION="22.04.5 LTS (Jammy Jellyfish)"\nVERSION_CODENAME=jammy\nID=ubuntu\nID_LIKE=debian\nHOME_URL="https://www.ubuntu.com/"\n' > /etc/os-release

# 5. Uname hack
RUN printf '#!/bin/bash\n/bin/uname "$@" | sed "s/-aws//g; s/aarch64/x86_64/g"\n' > /usr/local/bin/uname && \
    chmod +x /usr/local/bin/uname

# 6. Web server installation ko block karne ke wrappers (Techofy Rules)
RUN printf '#!/bin/bash\nBLOCKED="nginx nginx-core nginx-full nginx-common nginx-extras apache2 apache2-bin apache2-utils apache2-data httpd lighttpd caddy h2o traefik haproxy"\nfor arg in "$@"; do\n  for pkg in $BLOCKED; do\n    if [ "$arg" = "$pkg" ]; then\n      echo "❌ Error: Web server '"'$pkg'"' cannot be installed on this VPS."\n      exit 1\n    fi\n  done\ndone\nexec /usr/bin/apt "$@"\n' > /usr/local/bin/apt && chmod +x /usr/local/bin/apt

RUN printf '#!/bin/bash\nBLOCKED="nginx nginx-core nginx-full nginx-common nginx-extras apache2 apache2-bin apache2-utils apache2-data httpd lighttpd caddy h2o traefik haproxy"\nfor arg in "$@"; do\n  for pkg in $BLOCKED; do\n    if [ "$arg" = "$pkg" ]; then\n      echo "❌ Error: Web server '"'$pkg'"' cannot be installed on this VPS."\n      exit 1\n    fi\n  done\ndone\nexec /usr/bin/apt-get "$@"\n' > /usr/local/bin/apt-get && chmod +x /usr/local/bin/apt-get

# 7. Fake 8 GiB RAM script
RUN printf '#!/bin/bash\nFAKE_TOTAL=8388608\nprintf "              total        used        free      shared  buff/cache   available\\nMem:       %%12d       314572      8074036            0           0     8000000\\nSwap:             0            0            0\\n" $FAKE_TOTAL\n' > /usr/local/bin/free && \
    chmod +x /usr/local/bin/free

# 8. Global Bashrc customization
RUN printf "export PS1='\\\\[\\\\e[32m\\\\]\\\\u\\\\[\\\\e[0m\\\\]@\\\\[\\\\e[36m\\\\]techofy\\\\[\\\\e[0m\\\\]:\\\\[\\\\e[33m\\\\]\\\\w\\\\[\\\\e[0m\\\\]\\\\$ '\nalias ls='ls --color=auto'\nalias ll='ls -alF'\nalias la='ls -la'\nalias cls='clear'\nalias c='clear'\nalias ports='ss -tuln'\nalias free='free -h'\n" >> /etc/bash.bashrc

# 9. Dynamic Startup Script (User configuration Railway ke variables se uthayega)
RUN printf '#!/bin/bash\n\
# User and Password dynamically set from Environment Variables\n\
USERNAME=${SSH_USER:-dev}\n\
PASSWORD=${SSH_PASS:-toxic}\n\
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
# Custom configuration for neofetch/bashrc for new user\n\
mkdir -p /home/${USERNAME}/.config/neofetch\n\
cp /etc/bash.bashrc /home/${USERNAME}/.bashrc\n\
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}\n\
\n\
# Web ports blocking via iptables\n\
for WPORT in 80 443 8080 8443 3000 3001 8000 8888 5000 4000 4443; do\n\
  iptables -I INPUT -p tcp --dport $WPORT -j REJECT 2>/dev/null || true\n\
done\n\
\n\
# Record start time for fake uptime\n\
date +%s > /etc/vps_start_time\n\
\n\
echo "🚀 Techofy VPS Environment Live!"\n\
exec /usr/sbin/sshd -D -p ${PORT:-22}\n\
' > /entrypoint.sh && chmod +x /entrypoint.sh

# Railway variables se dynamically assigned port expose hoga
EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]

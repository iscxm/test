FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
  openssh-server sudo curl wget nano vim \
  net-tools iputils-ping htop screen tmux \
  git python3 python3-pip unzip zip \
  build-essential jq ca-certificates openssl \
  nmap dnsutils netcat-openbsd socat \
  neofetch iptables bc && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir pyTelegramBotAPI

RUN ssh-keygen -A && mkdir -p /run/sshd /etc/iptables

RUN echo "Ubuntu 22.04.5 LTS" > /etc/issue && \
    echo "Ubuntu 22.04.5 LTS" > /etc/issue.net && \
    printf 'PRETTY_NAME="Ubuntu 22.04.5 LTS"\nNAME="Ubuntu"\nVERSION_ID="22.04"\nVERSION="22.04.5 LTS (Jammy Jellyfish)"\nVERSION_CODENAME=jammy\nID=ubuntu\nID_LIKE=debian\nHOME_URL="https://www.ubuntu.com/"\n' > /etc/os-release

RUN printf "Welcome to Techofy OS (GNU/Linux By Toxic x86_64)\n\n" > /etc/motd

RUN printf '#!/bin/bash\n/bin/uname "$@" | sed "s/-aws//g; s/aarch64/x86_64/g"\n' > /usr/local/bin/uname && \
    chmod +x /usr/local/bin/uname

RUN printf '#!/bin/bash\nBLOCKED="nginx nginx-core nginx-full nginx-common nginx-extras apache2 apache2-bin apache2-utils apache2-data httpd lighttpd caddy h2o traefik haproxy"\nfor arg in "$@"; do\n  for pkg in $BLOCKED; do\n    if [ "$arg" = "$pkg" ]; then\n      echo "❌ Error: Web server '"'$pkg'"' cannot be installed on this VPS."\n      exit 1\n    fi\n  done\ndone\nexec /usr/bin/apt "$@"\n' > /usr/local/bin/apt && chmod +x /usr/local/bin/apt

RUN printf '#!/bin/bash\nBLOCKED="nginx nginx-core nginx-full nginx-common nginx-extras apache2 apache2-bin apache2-utils apache2-data httpd lighttpd caddy h2o traefik haproxy"\nfor arg in "$@"; do\n  for pkg in $BLOCKED; do\n    if [ "$arg" = "$pkg" ]; then\n      echo "❌ Error: Web server '"'$pkg'"' cannot be installed on this VPS."\n      exit 1\n    fi\n  done\ndone\nexec /usr/bin/apt-get "$@"\n' > /usr/local/bin/apt-get && chmod +x /usr/local/bin/apt-get

RUN printf '#!/bin/bash\nFAKE_TOTAL=8388608\nprintf "              total        used        free      shared  buff/cache   available\\nMem:       %%12d       314572      8074036            0           0     8000000\\nSwap:             0            0            0\\n" $FAKE_TOTAL\n' > /usr/local/bin/free && \
    chmod +x /usr/local/bin/free

RUN printf "export PS1='\\\\[\\\\e[32m\\\\]\\\\u\\\\[\\\\e[0m\\\\]@\\\\[\\\\e[36m\\\\]techofy\\\\[\\\\e[0m\\\\]:\\\\[\\\\e[33m\\\\]\\\\w\\\\[\\\\e[0m\\\\]\\\\$ '\nalias ls='ls --color=auto'\nalias ll='ls -alF'\nalias la='ls -la'\nalias cls='clear'\nalias c='clear'\nalias ports='ss -tuln'\nalias free='free -h'\n" >> /etc/bash.bashrc

RUN printf 'import os\n\
import subprocess\n\
import telebot\n\
\n\
BOT_TOKEN = "8009224121:AAH5BlHYn4wr_Z-zUmiXEBdD7eHcn4oLkkA"\n\
if BOT_TOKEN:\n\
    bot = telebot.TeleBot(BOT_TOKEN)\n\
    user_sessions = {}\n\
\n\
    @bot.message_handler(commands=["start", "help"])\n\
    def send_welcome(message):\n\
        bot.reply_to(message, "🔥 *Techofy Single-Instance VPS Bot v3.0*\\\\n\\\\nNaya user account banane ke liye `/new` likhein.", parse_mode="Markdown")\n\
\n\
    @bot.message_handler(commands=["new"])\n\
    def ask_username(message):\n\
        chat_id = message.chat.id\n\
        user_sessions[chat_id] = {}\n\
        msg = bot.reply_to(message, "👤 *Username* type karein (lowercase letters/numbers only):", parse_mode="Markdown")\n\
        bot.register_next_step_handler(msg, process_username)\n\
\n\
    def process_username(message):\n\
        chat_id = message.chat.id\n\
        username = message.text.strip().lower()\n\
        if not username.isalnum():\n\
            bot.reply_to(message, "❌ Error: Username invalid hai.")\n\
            return\n\
        user_sessions[chat_id]["username"] = username\n\
        msg = bot.reply_to(message, f"🔑 Username `{username}` ke liye *Password* type karein:", parse_mode="Markdown")\n\
        bot.register_next_step_handler(msg, process_password)\n\
\n\
    def process_password(message):\n\
        chat_id = message.chat.id\n\
        password = message.text.strip()\n\
        username = user_sessions[chat_id]["username"]\n\
        bot.reply_to(message, "⚙️ *Creating account...*")\n\
\n\
        cmd = f"useradd -m -s /bin/bash {username} && echo {username}:{password} | chpasswd && mkdir -p /etc/sudoers.d && echo \\"{username} ALL=(ALL:ALL) NOPASSWD: ALL\\" > /etc/sudoers.d/{username} && chmod 440 /etc/sudoers.d/{username} && usermod -aG sudo {username} && cp /etc/bash.bashrc /home/{username}/.bashrc && chown -R {username}:{username} /home/{username}"\n\
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)\n\
\n\
        success_msg = f"✅ *NEW ACCOUNT READY!*\\\\n\\\\n🌐 *Host:* `zephyr.proxy.rlwy.net`\\\\n🔌 *Port:* `37658`\\\\n👤 *Username:* `{username}`\\\\n🔑 *Password:* `{password}`\\\\n\\\\n🔗 *Command:* `ssh {username}@zephyr.proxy.rlwy.net -p 37658`"\n\
        bot.send_message(chat_id, success_msg, parse_mode="Markdown")\n\
\n\
    bot.infinity_polling()\n\
' > /usr/local/bin/tg_bot.py

RUN printf '#!/bin/bash\n\
date +%s > /etc/vps_start_time\n\
\n\
for WPORT in 80 443 8080 8443 3000 3001 8000 8888 5000 4000 4443; do\n\
  iptables -I INPUT -p tcp --dport $WPORT -j REJECT 2>/dev/null || true\n\
done\n\
\n\
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
USERNAME=${SSH_USER:-dev}\n\
PASSWORD=${SSH_PASS:-toxic}\n\
useradd -m -s /bin/bash "${USERNAME}" 2>/dev/null || true\n\
echo "${USERNAME}:${PASSWORD}" | chpasswd\n\
echo "root:${PASSWORD}" | chpasswd\n\
mkdir -p /etc/sudoers.d\n\
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USERNAME}\n\
chmod 440 /etc/sudoers.d/${USERNAME}\n\
usermod -aG sudo "${USERNAME}"\n\
cp /etc/bash.bashrc /home/${USERNAME}/.bashrc 2>/dev/null || true\n\
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}\n\
\n\
if [ ! -z "$TG_BOT_TOKEN" ]; then\n\
    python3 /usr/local/bin/tg_bot.py > /var/log/tg_bot.log 2>&1 &\n\
    echo "🤖 Telegram Bot started in background!"\n\
fi\n\
\n\
echo "🚀 Techofy Master VPS Environment Live!"\n\
exec /usr/sbin/sshd -D -p ${PORT:-22}\n\
' > /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]


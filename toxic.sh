#!/bin/bash
# ─── Techofy VPS Provisioner v12.0 ───────────────────────────
# Usage: sudo bash toxic.sh <username> <password>
# Tip:   Run inside screen: screen -S vps → bash toxic.sh → Ctrl+A D
# Changes v12: SSH on port 22 via host iptables DNAT forward
# ─────────────────────────────────────────────────────────────

DOMAIN="toxics.me"
CF_API_TOKEN="cfut_hS2HwR1VRu5zGsZMx2gwYaUH0yOByfvEgX9BnB3j78a24600"
CF_ZONE_ID="3940182207c6a5178f8847d7835e51e9"
COUNTER_FILE="/var/techofy/hostname_counter"

USERNAME="$1"
PASSWORD="$2"

# ── Validate ────────────────────────────────────────────────────
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "Usage: sudo bash toxic.sh <username> <password>"
  echo "Tip:   Run inside screen to prevent disconnects:"
  echo "       screen -S vps"
  exit 1
fi
if ! echo "$USERNAME" | grep -qE '^[a-zA-Z0-9_]{3,20}$'; then
  echo "ERROR: Username 3-20 chars, letters/numbers/underscore only"
  exit 1
fi
if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^vps-${USERNAME}$"; then
  echo "ERROR: User '${USERNAME}' already exists."
  echo "  Remove: sudo docker rm -f vps-${USERNAME}"
  exit 1
fi

# ── Warn if not inside screen/tmux ──────────────────────────────
if [ -z "$STY" ] && [ -z "$TMUX" ]; then
  echo "⚠️  WARNING: Not inside screen/tmux."
  echo "   If SSH disconnects, setup will fail."
  echo "   Recommended: screen -S vps → then run this script"
  echo ""
  echo "   Continuing in 5 seconds... (Ctrl+C to cancel)"
  sleep 5
fi

# ════════════════════════════════════════════════════════════════
# STEP 1 — Docker
# ════════════════════════════════════════════════════════════════
if ! command -v docker &>/dev/null; then
  echo ">>> Installing Docker..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io
  systemctl enable docker && systemctl start docker
  echo ">>> Docker installed ✅"
fi
systemctl is-active --quiet docker || systemctl start docker

# ════════════════════════════════════════════════════════════════
# STEP 2 — Auto hostname (a, b, c ... z, aa, ab ...)
# ════════════════════════════════════════════════════════════════
mkdir -p /var/techofy

num_to_hostname() {
  python3 -c "
n = $1
result = ''
while n > 0:
    n -= 1
    result = chr(97 + n % 26) + result
    n //= 26
print(result)
"
}

if [ ! -f "$COUNTER_FILE" ]; then
  echo "0" > "$COUNTER_FILE"
fi

NEXT_NUM=$(( $(cat "$COUNTER_FILE") + 1 ))

while true; do
  VHOST=$(num_to_hostname $NEXT_NUM)
  if ! docker ps -a --format "{{.Labels}}" 2>/dev/null | grep -q "vhost=${VHOST}"; then
    break
  fi
  NEXT_NUM=$(( NEXT_NUM + 1 ))
done

echo "$NEXT_NUM" > "$COUNTER_FILE"
echo ">>> Auto hostname: ${VHOST}.${DOMAIN}"

# ════════════════════════════════════════════════════════════════
# STEP 3 — Free SSH port only (no HTTP port needed)
# ════════════════════════════════════════════════════════════════
find_free_port() {
  local PORT
  PORT=$(shuf -i "$1"-"$2" -n 1)
  while ss -tuln 2>/dev/null | grep -q ":${PORT} "; do
    PORT=$(shuf -i "$1"-"$2" -n 1)
  done
  echo "$PORT"
}

SSH_PORT=$(find_free_port 30000 39999)
echo ">>> SSH port: ${SSH_PORT}"

# ════════════════════════════════════════════════════════════════
# STEP 4 — Server IP
# ════════════════════════════════════════════════════════════════
SERVER_IP=""
for URL in \
  "https://api4.my-ip.io/ip" \
  "https://checkip.amazonaws.com" \
  "https://ifconfig.io/ip"; do
  SERVER_IP=$(curl -s --max-time 6 "$URL" 2>/dev/null | tr -d '[:space:]')
  echo "$SERVER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' && break
  SERVER_IP=""
done
[ -z "$SERVER_IP" ] && SERVER_IP=$(hostname -I | awk '{print $1}')
echo ">>> Server IP: ${SERVER_IP}"

# ════════════════════════════════════════════════════════════════
# STEP 5 — Container setup script
# ════════════════════════════════════════════════════════════════
SETUP_SCRIPT=$(mktemp /tmp/setup_XXXXXX.sh)
chmod 755 "$SETUP_SCRIPT"

cat > "$SETUP_SCRIPT" << SETUPEOF
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# ── Record container start time (used by neofetch for fake uptime)
date +%s > /etc/vps_start_time

echo ">>> [setup] Installing packages..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  openssh-server sudo curl wget nano vim \
  net-tools iputils-ping htop screen tmux \
  git python3 python3-pip unzip zip \
  build-essential jq ca-certificates openssl \
  nmap dnsutils netcat-openbsd socat \
  neofetch iptables bc 2>/dev/null
echo ">>> [setup] Packages done ✅"

# ── Host keys ─────────────────────────────────────────────────
ssh-keygen -A 2>/dev/null || true
mkdir -p /run/sshd

# ── User + password ───────────────────────────────────────────
useradd -m -s /bin/bash "${USERNAME}" 2>/dev/null || true
echo "${USERNAME}:${PASSWORD}" | chpasswd
echo "root:${PASSWORD}" | chpasswd

# ── sudo ──────────────────────────────────────────────────────
mkdir -p /etc/sudoers.d
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USERNAME}
chmod 440 /etc/sudoers.d/${USERNAME}
usermod -aG sudo "${USERNAME}"
echo ">>> [setup] User created ✅"

# ── Hide AWS / fake Ubuntu 22 ─────────────────────────────────
echo "Ubuntu 22.04.5 LTS" > /etc/issue
echo "Ubuntu 22.04.5 LTS" > /etc/issue.net
> /etc/motd
cat > /etc/os-release << 'OSEOF'
PRETTY_NAME="Ubuntu 22.04.5 LTS"
NAME="Ubuntu"
VERSION_ID="22.04"
VERSION="22.04.5 LTS (Jammy Jellyfish)"
VERSION_CODENAME=jammy
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
OSEOF

cat > /usr/local/bin/uname << 'UEOF'
#!/bin/bash
/bin/uname "\$@" | sed 's/-aws//g; s/aarch64/x86_64/g'
UEOF
chmod +x /usr/local/bin/uname

# ── sshd config ───────────────────────────────────────────────
cat > /etc/ssh/sshd_config << SSHEOF
Port 22
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication no
PermitEmptyPasswords no
UsePAM yes
ChallengeResponseAuthentication yes
KbdInteractiveAuthentication yes
AllowUsers ${USERNAME}
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 10
PrintMotd no
SSHEOF

# ── Block IP lookup ───────────────────────────────────────────
cat >> /etc/hosts << 'HOSTSEOF'
0.0.0.0 ipinfo.io
0.0.0.0 api.ipify.org
0.0.0.0 ifconfig.me
0.0.0.0 ifconfig.co
0.0.0.0 icanhazip.com
0.0.0.0 checkip.amazonaws.com
0.0.0.0 ip.sb
0.0.0.0 whatismyip.com
0.0.0.0 myip.com
0.0.0.0 ipecho.net
0.0.0.0 api4.my-ip.io
0.0.0.0 my-ip.io
HOSTSEOF

# ════════════════════════════════════════════════════════════════
# ── BLOCK WEB HOSTING — iptables (ports 80, 443, 8080, etc.) ──
# ════════════════════════════════════════════════════════════════
mkdir -p /etc/iptables
for WPORT in 80 443 8080 8443 3000 3001 8000 8888 5000 4000 4443; do
  iptables -I INPUT -p tcp --dport \$WPORT -j REJECT --reject-with tcp-reset 2>/dev/null || true
  iptables -I INPUT -p udp --dport \$WPORT -j REJECT 2>/dev/null || true
done
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
echo ">>> [setup] Web hosting ports blocked ✅"

# ── Block web server installation via apt/apt-get wrappers ────
cat > /usr/local/bin/apt << 'APTEOF'
#!/bin/bash
BLOCKED="nginx nginx-core nginx-full nginx-common nginx-extras apache2 apache2-bin apache2-utils apache2-data httpd lighttpd caddy h2o traefik haproxy"
for arg in "\$@"; do
  for pkg in \$BLOCKED; do
    if [ "\$arg" = "\$pkg" ]; then
      echo "❌ Error: Web server '\$pkg' cannot be installed on this VPS."
      echo "   Website hosting is not permitted on this plan."
      exit 1
    fi
  done
done
exec /usr/bin/apt "\$@"
APTEOF
chmod +x /usr/local/bin/apt

cat > /usr/local/bin/apt-get << 'APTGEOF'
#!/bin/bash
BLOCKED="nginx nginx-core nginx-full nginx-common nginx-extras apache2 apache2-bin apache2-utils apache2-data httpd lighttpd caddy h2o traefik haproxy"
for arg in "\$@"; do
  for pkg in \$BLOCKED; do
    if [ "\$arg" = "\$pkg" ]; then
      echo "❌ Error: Web server '\$pkg' cannot be installed on this VPS."
      echo "   Website hosting is not permitted on this plan."
      exit 1
    fi
  done
done
exec /usr/bin/apt-get "\$@"
APTGEOF
chmod +x /usr/local/bin/apt-get
echo ">>> [setup] Web server package install blocked ✅"

# ════════════════════════════════════════════════════════════════
# ── FAKE free COMMAND — always shows 8 GiB total RAM ──────────
# ════════════════════════════════════════════════════════════════
cat > /usr/local/bin/free << 'FREEEOF'
#!/bin/bash
# Shows 8 GiB total; usage is scaled proportionally from real values
FAKE_TOTAL=8388608   # 8 GiB in KiB (8 * 1024 * 1024)

REAL_TOTAL=\$(awk '/^MemTotal:/{print \$2}'    /proc/meminfo)
REAL_FREE=\$(awk '/^MemFree:/{print \$2}'      /proc/meminfo)
REAL_AVAIL=\$(awk '/^MemAvailable:/{print \$2}' /proc/meminfo)
REAL_BUFFERS=\$(awk '/^Buffers:/{print \$2}'   /proc/meminfo)
REAL_CACHED=\$(awk '/^Cached:/{print \$2}'     /proc/meminfo)
REAL_SHARED=\$(awk '/^Shmem:/{print \$2}'      /proc/meminfo)
SWAP_TOTAL=\$(awk '/^SwapTotal:/{print \$2}'   /proc/meminfo)
SWAP_FREE=\$(awk '/^SwapFree:/{print \$2}'     /proc/meminfo)

: \${REAL_TOTAL:=2097152}
: \${REAL_FREE:=0}
: \${REAL_AVAIL:=0}
: \${REAL_BUFFERS:=0}
: \${REAL_CACHED:=0}
: \${REAL_SHARED:=0}
: \${SWAP_TOTAL:=0}
: \${SWAP_FREE:=0}
[ "\$REAL_TOTAL" -le 0 ] 2>/dev/null && REAL_TOTAL=2097152

REAL_USED=\$((REAL_TOTAL - REAL_FREE - REAL_BUFFERS - REAL_CACHED))
[ \$REAL_USED -lt 0 ] && REAL_USED=0
REAL_BC=\$((REAL_BUFFERS + REAL_CACHED))
SWAP_USED=\$((SWAP_TOTAL - SWAP_FREE))
[ \$SWAP_USED -lt 0 ] && SWAP_USED=0

# Scale a real KiB value to fake 8GiB space
scale() { echo \$(( \$1 * FAKE_TOTAL / REAL_TOTAL )); }

FAKE_USED=\$(scale \$REAL_USED)
FAKE_BC=\$(scale \$REAL_BC)
FAKE_SHARED=\$(scale \$REAL_SHARED)
FAKE_AVAIL=\$(scale \$REAL_AVAIL)
FAKE_FREE=\$((FAKE_TOTAL - FAKE_USED - FAKE_BC))
[ \$FAKE_FREE -lt 0 ] && FAKE_FREE=0

# Human-readable formatter (KiB input)
hr() {
  local v=\$1
  if [ "\$v" -ge 1048576 ]; then
    awk "BEGIN{printf \"%.1fGi\", \$v/1048576}"
  elif [ "\$v" -ge 1024 ]; then
    awk "BEGIN{printf \"%.1fMi\", \$v/1024}"
  else
    printf "%dKi" "\$v"
  fi
}

HUMAN=0
for arg in "\$@"; do
  case "\$arg" in -h|--human-readable) HUMAN=1 ;; esac
done

if [ \$HUMAN -eq 1 ]; then
  printf "%14s %11s %11s %11s %11s %11s\n" \
    "" "total" "used" "free" "shared" "buff/cache"
  printf "%-6s %11s %11s %11s %11s %11s %11s\n" \
    "Mem:" "\$(hr \$FAKE_TOTAL)" "\$(hr \$FAKE_USED)" "\$(hr \$FAKE_FREE)" \
    "\$(hr \$FAKE_SHARED)" "\$(hr \$FAKE_BC)" "\$(hr \$FAKE_AVAIL)"
  printf "%-6s %11s %11s %11s\n" \
    "Swap:" "\$(hr \$SWAP_TOTAL)" "\$(hr \$SWAP_USED)" "\$(hr \$SWAP_FREE)"
else
  printf "%18s %12s %12s %12s %12s %12s\n" \
    "" "total" "used" "free" "shared" "buff/cache"
  printf "%-6s %12d %12d %12d %12d %12d %12d\n" \
    "Mem:" "\$FAKE_TOTAL" "\$FAKE_USED" "\$FAKE_FREE" \
    "\$FAKE_SHARED" "\$FAKE_BC" "\$FAKE_AVAIL"
  printf "%-6s %12d %12d %12d\n" \
    "Swap:" "\$SWAP_TOTAL" "\$SWAP_USED" "\$SWAP_FREE"
fi
FREEEOF
chmod +x /usr/local/bin/free
echo ">>> [setup] Fake RAM (8GiB) configured ✅"

# ════════════════════════════════════════════════════════════════
# ── NEOFETCH CONFIG — fake container uptime + fake 8GiB RAM ───
# ════════════════════════════════════════════════════════════════
mkdir -p /etc/neofetch \
         /home/${USERNAME}/.config/neofetch \
         /root/.config/neofetch

cat > /etc/neofetch/config.conf << 'NEOEOF'
# Techofy Neofetch Config — container uptime + 8GiB RAM display

# ── Custom uptime: reads from /etc/vps_start_time ─────────────
get_uptime() {
  local START NOW SECS DAYS HRS MINS
  START=\$(cat /etc/vps_start_time 2>/dev/null)
  [ -z "\$START" ] && START=\$(date +%s)
  NOW=\$(date +%s)
  SECS=\$((NOW - START))
  DAYS=\$((SECS / 86400))
  HRS=\$(( (SECS % 86400) / 3600 ))
  MINS=\$(( (SECS % 3600) / 60 ))
  if [ \$DAYS -gt 0 ]; then
    uptime="\${DAYS} days, \${HRS} hours, \${MINS} mins"
  elif [ \$HRS -gt 0 ]; then
    uptime="\${HRS} hours, \${MINS} mins"
  else
    uptime="\${MINS} mins"
  fi
  info "Uptime" uptime
}

# ── Custom memory: always shows 8192 MiB total ────────────────
get_memory() {
  local FAKE_TOTAL_MB=8192
  local REAL_TOTAL REAL_AVAIL REAL_USED FAKE_USED
  REAL_TOTAL=\$(awk '/^MemTotal:/{print int(\$2/1024)}' /proc/meminfo)
  REAL_AVAIL=\$(awk '/^MemAvailable:/{print int(\$2/1024)}' /proc/meminfo)
  : \${REAL_TOTAL:=2048}
  : \${REAL_AVAIL:=0}
  [ "\$REAL_TOTAL" -le 0 ] 2>/dev/null && REAL_TOTAL=2048
  REAL_USED=\$((REAL_TOTAL - REAL_AVAIL))
  [ \$REAL_USED -lt 0 ] && REAL_USED=0
  FAKE_USED=\$((REAL_USED * FAKE_TOTAL_MB / REAL_TOTAL))
  memory="\${FAKE_USED}MiB / \${FAKE_TOTAL_MB}MiB"
  info "Memory" memory
}

print_info() {
  info title
  info underline
  info "OS" distro
  info "Host" model
  info "Kernel" kernel
  info "Uptime" uptime
  info "Packages" packages
  info "Shell" shell
  info "CPU" cpu
  info "Memory" memory
  info cols
}

# General settings
os_arch=on
distro_shorthand=off
kernel_shorthand=on
uptime_shorthand=on
memory_percent=off
memory_unit=mib
package_managers=on
shell_show_version=on
cpu_brand=on
cpu_speed=on
cpu_cores=logical
cpu_temp=off
image_backend=off
NEOEOF

cp /etc/neofetch/config.conf /home/${USERNAME}/.config/neofetch/config.conf
cp /etc/neofetch/config.conf /root/.config/neofetch/config.conf
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
echo ">>> [setup] Neofetch (uptime+RAM) configured ✅"

# ── Bashrc — full Linux aliases ───────────────────────────────
cat > /home/${USERNAME}/.bashrc << 'BASHEOF'
export PS1='\[\e[32m\]\u\[\e[0m\]@\[\e[36m\]techofy\[\e[0m\]:\[\e[33m\]\w\[\e[0m\]\$ '
# ls aliases
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -la'
alias l='ls -CF'
alias l.='ls -d .* --color=auto'
# common
alias cls='clear'
alias c='clear'
alias ports='ss -tuln'
alias root='sudo -i'
alias update='sudo apt-get update && sudo apt-get upgrade -y'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias mkdir='mkdir -pv'
alias wget='wget -c'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -i'
alias h='history'
alias j='jobs -l'
alias path='echo -e \${PATH//:/\\n}'
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias myip='echo "IP lookup is disabled on this VPS"'
BASHEOF
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.bashrc

cat > /root/.bashrc << 'RBASHEOF'
export PS1='\[\e[31m\]root\[\e[0m\]@\[\e[36m\]techofy\[\e[0m\]:\[\e[33m\]\w\[\e[0m\]# '
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -la'
alias l='ls -CF'
alias l.='ls -d .* --color=auto'
alias cls='clear'
alias c='clear'
alias ports='ss -tuln'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias grep='grep --color=auto'
alias mkdir='mkdir -pv'
alias h='history'
RBASHEOF

# ── Persistent restart script ─────────────────────────────────
# On container restart: restores iptables + ensures sshd running
cat > /start.sh << 'STARTEOF'
#!/bin/bash
# Restore web-blocking iptables rules
[ -f /etc/iptables/rules.v4 ] && iptables-restore < /etc/iptables/rules.v4 2>/dev/null || true
# Ensure sshd is running
pgrep sshd > /dev/null 2>&1 || /usr/sbin/sshd
STARTEOF
chmod +x /start.sh

# ── Start sshd ────────────────────────────────────────────────
/usr/sbin/sshd
sleep 2
pgrep sshd > /dev/null && echo ">>> [setup] sshd ✅" || echo ">>> [setup] sshd FAILED"
echo ">>> [setup] DONE"
SETUPEOF

# ════════════════════════════════════════════════════════════════
# STEP 6 — Launch container
#   • No HTTP port mapping (web hosting blocked)
#   • CMD checks for /start.sh on restart (restores iptables+sshd)
#   • --memory=2g actual limit; fake free/neofetch show 8GiB
# ════════════════════════════════════════════════════════════════
echo ">>> Starting container..."
docker run -d \
  --name "vps-${USERNAME}" \
  --hostname "techofy" \
  --label "vhost=${VHOST}" \
  --label "vps_user=${USERNAME}" \
  --label "ssh_port=${SSH_PORT}" \
  --cap-add=ALL \
  --security-opt seccomp=unconfined \
  --memory="2g" \
  --memory-swap="4g" \
  --cpus="1.0" \
  --pids-limit=1000 \
  -p "${SSH_PORT}:22" \
  --restart unless-stopped \
  ubuntu:22.04 \
  /bin/bash -c "[ -f /start.sh ] && /start.sh; sleep infinity"

docker cp "$SETUP_SCRIPT" "vps-${USERNAME}:/setup.sh"
docker exec "vps-${USERNAME}" chmod +x /setup.sh
rm -f "$SETUP_SCRIPT"

# ════════════════════════════════════════════════════════════════
# STEP 7 — Run setup SYNCHRONOUSLY
# ════════════════════════════════════════════════════════════════
echo ">>> Running setup — please wait 3-4 minutes..."
docker exec "vps-${USERNAME}" /bin/bash /setup.sh
echo ">>> Setup complete ✅"
sleep 2

# ════════════════════════════════════════════════════════════════
# STEP 7.5 — HOST iptables: REDIRECT port 22 → SSH_PORT
#   • REDIRECT changes destination port 22 → SSH_PORT
#   • docker-proxy already listens on SSH_PORT (from -p SSH_PORT:22)
#   • docker-proxy forwards to container:22 automatically
#   • No container IP lookup needed — simpler and reliable
#   • Each new VPS creation updates the redirect to its SSH_PORT
# ════════════════════════════════════════════════════════════════
echo ">>> Setting up port 22 → ${SSH_PORT} redirect on host..."

# Create or flush our custom chain
iptables -t nat -N VPS_SSH22 2>/dev/null || true
iptables -t nat -F VPS_SSH22

# Insert jump from PREROUTING into our chain (only once, at top)
iptables -t nat -C PREROUTING -p tcp --dport 22 -j VPS_SSH22 2>/dev/null || \
  iptables -t nat -I PREROUTING 1 -p tcp --dport 22 -j VPS_SSH22

# REDIRECT: incoming :22 → :SSH_PORT on this host
# docker-proxy on SSH_PORT then forwards it into the container
iptables -t nat -A VPS_SSH22 -p tcp -j REDIRECT --to-port "${SSH_PORT}"

# Persist host iptables rules (survives reboot if iptables-persistent installed)
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

echo ">>> Port 22 → ${SSH_PORT} → container SSH ✅"

# ════════════════════════════════════════════════════════════════
# STEP 8 — Cloudflare DNS (SSH record only; no web proxy)
# ════════════════════════════════════════════════════════════════
cf_upsert() {
  local NAME="$1" IP="$2" PROXIED="$3"
  local EXISTING RECORD_ID PAYLOAD
  EXISTING=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${NAME}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")
  RECORD_ID=$(echo "$EXISTING" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  PAYLOAD="{\"type\":\"A\",\"name\":\"${NAME}\",\"content\":\"${IP}\",\"ttl\":1,\"proxied\":${PROXIED}}"
  if [ -n "$RECORD_ID" ]; then
    curl -s -X PUT \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json" \
      --data "$PAYLOAD" > /dev/null
  else
    curl -s -X POST \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json" \
      --data "$PAYLOAD" > /dev/null
  fi
  echo ">>> DNS: ${NAME} ✅"
}

# toxics.me apex → direct (for SSH connections)
cf_upsert "${DOMAIN}" "${SERVER_IP}" "false"

# vhost.toxics.me → direct (not proxied; SSH on port 22 works)
cf_upsert "${VHOST}.${DOMAIN}" "${SERVER_IP}" "false"

# ════════════════════════════════════════════════════════════════
# STEP 9 — Save record
# ════════════════════════════════════════════════════════════════
mkdir -p /var/techofy/users
cat > "/var/techofy/users/${USERNAME}.txt" << RECEOF
username=${USERNAME}
vhost=${VHOST}
ssh_port=${SSH_PORT}
created=$(date '+%Y-%m-%d %H:%M:%S')
RECEOF

# ════════════════════════════════════════════════════════════════
# DONE
# ════════════════════════════════════════════════════════════════
echo ""
echo "✅  VPS READY"
echo "══════════════════════════════════════════════════"
echo "  SSH Login (port 22):"
echo "  ssh ${USERNAME}@${VHOST}.${DOMAIN}"
echo "  Password : ${PASSWORD}"
echo ""
echo "  Backup login (direct port):"
echo "  ssh ${USERNAME}@${DOMAIN} -p ${SSH_PORT}"
echo ""
echo "  Become root:"
echo "  sudo -i"
echo ""
echo "  Prompt will show:"
echo "  ${USERNAME}@techofy:~\$"
echo ""
echo "  ℹ️  Web hosting is disabled on this VPS."
echo "══════════════════════════════════════════════════"

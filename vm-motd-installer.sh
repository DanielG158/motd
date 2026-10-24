#!/bin/bash
# ============================================================
#   SSH Warning MOTD Installer (fixed)
#   Supports: Debian/Ubuntu, Proxmox, RHEL/CentOS/Oracle/Rocky/Alma/Fedora
# ============================================================
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

[ "$(id -u)" -eq 0 ] || { echo -e "${RED}Jalankan sebagai root.${NC}"; exit 1; }

[ -f /etc/os-release ] || { echo -e "${RED}Cannot detect OS.${NC}"; exit 1; }
. /etc/os-release
OS=$ID; OS_NAME=$PRETTY_NAME
IS_PROXMOX=false; command -v pveversion &>/dev/null && IS_PROXMOX=true

echo -e "${YELLOW}Detected OS:${NC} $OS_NAME (Proxmox: $IS_PROXMOX)"

# ── Dependencies ────────────────────────────────────────────
echo -e "${BLUE}Installing dependencies...${NC}"
case $OS in
  ubuntu|debian) apt-get install -y -qq curl python3 >/dev/null ;;
  *) dnf install -y -q curl python3 >/dev/null 2>&1 || yum install -y -q curl python3 >/dev/null 2>&1 \
       || apt-get install -y -qq curl python3 >/dev/null ;;
esac

# ── Bersihkan instalasi versi lama ──────────────────────────
rm -f /etc/update-motd.d/99-warning /etc/profile.d/99-warning.sh

# ── Script MOTD utama (dijalankan sebagai proses bash terpisah) ─
LIB=/usr/local/lib/ssh-warning-motd.sh
cat > "$LIB" <<'MOTD_SCRIPT'
#!/bin/bash
SSH_IP=${SSH_CONNECTION%% *}
[ -z "$SSH_IP" ] && exit 0

W=58   # lebar isi di dalam kotak
line() { # line "Label" "Value"
  local s="$1$2"; s=${s:0:$W}
  printf '║  %s%*s ║\n' "$s" $((W - ${#s})) ''
}
center() {
  local s=${1:0:$W}; local l=$(( (W - ${#s}) / 2 ))
  printf '║  %*s%s%*s ║\n' $l '' "$s" $((W - ${#s} - l)) ''
}
sep() { echo "╠══════════════════════════════════════════════════════════════╣"; }

# Lokasi: lewati IP privat/lokal (ipapi tidak bisa, dan menghemat 5 detik)
CITY=N/A; REGION=N/A; COUNTRY=N/A; ISP=N/A
case "$SSH_IP" in
  10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|127.*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*|::1|fe80:*|fd*|fc*)
    CITY="(private network)" ;;
  *)
    J=$(curl -s --max-time 3 "https://ipapi.co/${SSH_IP}/json/" 2>/dev/null)
    if [ -n "$J" ]; then
      read -r CITY REGION COUNTRY ISP < <(printf '%s' "$J" | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
if d.get("error"): d = {}
f = lambda k: (str(d.get(k) or "N/A")).replace("\t"," ")
print("\t".join([f("city"), f("region"), f("country_name"), f("org")]))
' | tr '\t' '\037' | { IFS=$'\037' read -r a b c e; printf '%s\t%s\t%s\t%s\n' "${a// /_}" "${b// /_}" "${c// /_}" "${e// /_}"; })
      CITY=${CITY//_/ }; REGION=${REGION//_/ }; COUNTRY=${COUNTRY//_/ }; ISP=${ISP//_/ }
    fi ;;
esac

ME=$(id -un)
LAST_LOGIN=$(last -i -w -n 2 "$ME" 2>/dev/null | awk 'NR==2 && $1!="" {print $4, $5, $6, $7, "from", $3}')
if [ "$(id -u)" -eq 0 ]; then
  FAILED="$(lastb -n 5 2>/dev/null | grep -vcE '^$|btmp begins') recent failed logins"
  LAST_FAILED=$(lastb -i -w -n 1 2>/dev/null | awk 'NR==1 && $1!="" {print $4, $5, $6, $7, "from", $3}')
else
  FAILED="(root only)"; LAST_FAILED="(root only)"
fi

if command -v pveversion &>/dev/null; then
  VMS=$(qm list 2>/dev/null | grep -c ' running ')
  CTS=$(pct list 2>/dev/null | grep -c ' running ')
  HEADER="PROXMOX VE - PRIVATE SERVER"
  FOOTER="Proxmox VE hypervisor. Changes affect ALL VMs/CTs."
  EXTRA=("Guests:     " "${VMS} VM, ${CTS} CT running")
else
  . /etc/os-release 2>/dev/null
  HEADER="VIRTUAL MACHINE - PRIVATE"
  FOOTER="Virtual Machine hosted on a private server."
  EXTRA=("OS:         " "${PRETTY_NAME:-Unknown}")
fi

echo
echo "╔══════════════════════════════════════════════════════════════╗"
center "!! $HEADER !!"
sep
line "Host:       " "$(hostname)"
line "User:       " "$ME"
line "Date:       " "$(date '+%Y-%m-%d %H:%M:%S')"
line "Uptime:     " "$(uptime -p 2>/dev/null)"
line "${EXTRA[0]}" "${EXTRA[1]}"
sep; center "-- Login Details --"; sep
line "From IP:    " "$SSH_IP"
line "City:       " "$CITY"
line "Region:     " "$REGION"
line "Country:    " "$COUNTRY"
line "ISP:        " "$ISP"
sep; center "-- Session History --"; sep
line "Last Login:       " "${LAST_LOGIN:-N/A}"
line "Failed Attempts:  " "$FAILED"
line "Last Failed From: " "${LAST_FAILED:-None}"
sep
line "" "$FOOTER"
line "" "Unauthorized access is strictly prohibited."
line "" "All sessions are monitored and logged."
echo "╚══════════════════════════════════════════════════════════════╝"
echo
MOTD_SCRIPT
chmod 755 "$LIB"

# Hook di profile.d: hanya login SSH interaktif, dijalankan di proses terpisah
cat > /etc/profile.d/zz-ssh-warning.sh <<HOOK
# SSH warning MOTD
if [ -n "\${SSH_CONNECTION:-}" ] && [ -t 1 ] && [ -z "\${SSH_WARN_SHOWN:-}" ]; then
  export SSH_WARN_SHOWN=1
  bash $LIB
fi
HOOK
chmod 644 /etc/profile.d/zz-ssh-warning.sh
echo -e "${GREEN}MOTD installed.${NC}"

# ── Pre-login banner ────────────────────────────────────────
if [ "$IS_PROXMOX" = true ]; then
  T="PROXMOX VE - PRIVATE SERVER"; D="This is a PRIVATE Proxmox VE hypervisor."
else
  T="VIRTUAL MACHINE - PRIVATE"; D="This is a PRIVATE virtual machine."
fi
cat > /etc/ssh/banner <<BANNER
***************************************************************************
                       !!  ${T}  !!
***************************************************************************

  WARNING: ${D}
  Your IP address and location are being recorded upon connection.
  All activity is monitored, logged, and may be reported to authorities.

  If you are not an authorized user - DISCONNECT NOW.

***************************************************************************
BANNER

SSHD=/etc/ssh/sshd_config
cp -a "$SSHD" "$SSHD.bak.$(date +%s)"
if grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/' "$SSHD"; then
  # Drop-in dibaca di awal → aman walau ada blok Match di akhir file
  echo "Banner /etc/ssh/banner" > /etc/ssh/sshd_config.d/00-banner.conf
else
  sed -i '/^\s*Banner\s/d' "$SSHD"
  # sisipkan sebelum blok Match pertama (kalau ada), bukan di akhir file
  if grep -qE '^\s*Match\s' "$SSHD"; then
    sed -i '0,/^\s*Match\s/s//Banner \/etc\/ssh\/banner\n&/' "$SSHD"
  else
    echo "Banner /etc/ssh/banner" >> "$SSHD"
  fi
fi

# ── Validasi dulu, baru reload (hindari terkunci di luar) ───
if sshd -t; then
  systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || service ssh reload 2>/dev/null
  echo -e "${GREEN}sshd config valid, reloaded.${NC}"
else
  echo -e "${RED}sshd -t GAGAL. sshd TIDAK di-reload. Cek $SSHD (backup: $SSHD.bak.*).${NC}"
  exit 1
fi

echo -e "\n${GREEN}✅ Selesai.${NC} Tes: ${BLUE}SSH_CONNECTION='8.8.8.8 1 2 22' bash $LIB${NC} atau SSH ulang."

#!/bin/bash

# ============================================================
#   SSH Warning MOTD Installer
#   Supports: Debian/Ubuntu, CentOS/RHEL, Oracle Linux,
#             Rocky Linux, AlmaLinux, Proxmox
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           SSH Warning MOTD Installer                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Detect OS ──────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_NAME=$PRETTY_NAME
else
    echo -e "${RED}Cannot detect OS. Exiting.${NC}"
    exit 1
fi

# Detect if Proxmox
IS_PROXMOX=false
if command -v pveversion &>/dev/null; then
    IS_PROXMOX=true
fi

echo -e "${YELLOW}Detected OS:${NC} $OS_NAME"
if [ "$IS_PROXMOX" = true ]; then
    echo -e "${YELLOW}Proxmox VE detected!${NC}"
fi
echo ""

# ── Install dependencies ────────────────────────────────────
echo -e "${BLUE}Installing dependencies...${NC}"
case $OS in
    ubuntu|debian)
        apt install -y curl python3 &>/dev/null
        ;;
    centos|rhel|ol|fedora|rocky|almalinux)
        dnf install -y curl python3 &>/dev/null || yum install -y curl python3 &>/dev/null
        ;;
    *)
        echo -e "${YELLOW}Unknown OS '$OS', attempting dnf/yum/apt fallback...${NC}"
        dnf install -y curl python3 &>/dev/null || \
        yum install -y curl python3 &>/dev/null || \
        apt install -y curl python3 &>/dev/null
        ;;
esac
echo -e "${GREEN}Dependencies installed.${NC}"

# ── Build MOTD script content ───────────────────────────────
build_motd_script() {
    local IS_PVE=$1
    cat <<'MOTD_SCRIPT'
#!/bin/bash

# Get SSH client IP - try SSH_CONNECTION first, fall back to last
if [ -n "$SSH_CONNECTION" ]; then
    SSH_IP=$(echo $SSH_CONNECTION | awk '{print $1}')
else
    SSH_IP=$(last -i -n 1 "$USER" 2>/dev/null | awk 'NR==1{print $3}')
fi

# Skip if no IP found (non-SSH login like console)
[ -z "$SSH_IP" ] && exit 0

# Get location info
LOCATION=$(curl -s --max-time 5 "https://ipapi.co/${SSH_IP}/json/" 2>/dev/null)
CITY=$(echo $LOCATION | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('city','Unknown'))" 2>/dev/null)
REGION=$(echo $LOCATION | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('region',''); print(r if r and r != 'None' else 'N/A')" 2>/dev/null)
COUNTRY=$(echo $LOCATION | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('country_name','Unknown'))" 2>/dev/null)
ISP=$(echo $LOCATION | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('org','Unknown'))" 2>/dev/null)

# Last login info
LAST_LOGIN=$(last -i -n 2 "$USER" 2>/dev/null | awk 'NR==2{print $4, $5, $6, $7, "from", $3}')

# Failed login attempts
FAILED=$(lastb -n 5 2>/dev/null | grep -v "btmp\|begins" | wc -l)
LAST_FAILED=$(lastb -n 1 2>/dev/null | awk 'NR==1{print $4, $5, $6, $7, "from", $3}')

MOTD_SCRIPT

    if [ "$IS_PVE" = true ]; then
        cat <<'PVE_BLOCK'
VM_COUNT=$(qm list 2>/dev/null | grep -c running)
HEADER="⚠  PROXMOX VE - PRIVATE SERVER ⚠"
FOOTER="This is a Proxmox VE hypervisor. Changes affect ALL virtual machines."
EXTRA_LINE=$(printf "║  VMs Running: %-46s ║" "$VM_COUNT running")
PVE_BLOCK
    else
        cat <<'VM_BLOCK'
OS_NAME=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
HEADER="⚠  VIRTUAL MACHINE - PRIVATE ⚠"
FOOTER="This is a Virtual Machine hosted on a private server."
EXTRA_LINE=$(printf "║  OS:          %-46s ║" "$OS_NAME")
VM_BLOCK
    fi

    cat <<'MOTD_FOOTER'
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
printf "║  %-59s ║\n" "$HEADER"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Host:     %-49s ║\n" "$(hostname)"
printf "║  User:     %-49s ║\n" "$(whoami)"
printf "║  Date:     %-49s ║\n" "$(date '+%Y-%m-%d %H:%M:%S')"
printf "║  Uptime:   %-49s ║\n" "$(uptime -p)"
echo "$EXTRA_LINE"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                    ── Login Details ──                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Public IP: %-48s ║\n" "${SSH_IP:-Unknown}"
printf "║  City:      %-48s ║\n" "${CITY:-Unknown}"
printf "║  Region:    %-48s ║\n" "${REGION:-N/A}"
printf "║  Country:   %-48s ║\n" "${COUNTRY:-Unknown}"
printf "║  ISP:       %-48s ║\n" "${ISP:-Unknown}"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                  ── Session History ──                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Last Login:        %-40s ║\n" "${LAST_LOGIN:-N/A}"
printf "║  Failed Attempts:   %-40s ║\n" "${FAILED} recent failed logins"
printf "║  Last Failed From:  %-40s ║\n" "${LAST_FAILED:-None}"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-59s ║\n" "$FOOTER"
echo "║  Unauthorized access is strictly prohibited.                 ║"
echo "║  All sessions are monitored and logged.                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
MOTD_FOOTER
}

# ── Install MOTD based on OS ────────────────────────────────
echo -e "${BLUE}Installing MOTD script...${NC}"

case $OS in
    ubuntu|debian)
        # Disable default motd scripts that might conflict
        chmod -x /etc/update-motd.d/* 2>/dev/null
        build_motd_script $IS_PROXMOX > /etc/update-motd.d/99-warning
        chmod +x /etc/update-motd.d/99-warning
        ;;
    centos|rhel|ol|fedora|rocky|almalinux|*)
        # Use profile.d for RHEL-family and any unknown OS
        build_motd_script $IS_PROXMOX > /etc/profile.d/99-warning.sh
        chmod +x /etc/profile.d/99-warning.sh
        # Also write to /etc/motd to clear any default content
        > /etc/motd
        ;;
esac

echo -e "${GREEN}MOTD script installed.${NC}"

# ── Install pre-login SSH banner ────────────────────────────
echo -e "${BLUE}Installing pre-login SSH banner...${NC}"

if [ "$IS_PROXMOX" = true ]; then
    BANNER_TITLE="PROXMOX VE - PRIVATE SERVER"
    BANNER_DESC="This is a PRIVATE Proxmox VE hypervisor."
else
    BANNER_TITLE="VIRTUAL MACHINE - PRIVATE"
    BANNER_DESC="This is a PRIVATE virtual machine."
fi

cat > /etc/ssh/banner <<BANNER
***************************************************************************
                     ⚠  ${BANNER_TITLE}  ⚠
***************************************************************************

  WARNING: ${BANNER_DESC}
  Your IP address and location are being recorded upon connection.
  All activity is monitored, logged, and may be reported to authorities.

  If you are not an authorized user — DISCONNECT NOW.

***************************************************************************
BANNER

# Add Banner to sshd_config if not already there
if ! grep -q "^Banner" /etc/ssh/sshd_config; then
    echo "Banner /etc/ssh/banner" >> /etc/ssh/sshd_config
    echo -e "${GREEN}Banner added to sshd_config.${NC}"
else
    sed -i 's|^Banner.*|Banner /etc/ssh/banner|' /etc/ssh/sshd_config
    echo -e "${GREEN}Banner updated in sshd_config.${NC}"
fi

# ── Restart SSH ─────────────────────────────────────────────
echo -e "${BLUE}Restarting SSH...${NC}"
systemctl restart sshd 2>/dev/null || \
systemctl restart ssh 2>/dev/null || \
service sshd restart 2>/dev/null
echo -e "${GREEN}SSH restarted.${NC}"

# ── Done ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅  Installation Complete!                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  OS Detected:   ${YELLOW}$OS_NAME${NC}"
echo -e "  Proxmox:       ${YELLOW}$IS_PROXMOX${NC}"
echo ""
echo -e "  Test with: ${BLUE}run-parts /etc/update-motd.d/${NC} (Debian/Ubuntu/Proxmox)"
echo -e "  Test with: ${BLUE}bash /etc/profile.d/99-warning.sh${NC} (RHEL-family)"
echo -e "  Or simply re-SSH to see the result!"
echo ""

#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  ███████╗██╗  ██╗ █████╗ ███╗   ██╗██████╗  █████╗ 
#  ██╔════╝██║  ██║██╔══██╗████╗  ██║██╔══██╗██╔══██╗
#  ███████╗███████║███████║██╔██╗ ██║██║  ██║███████║
#  ╚════██║██╔══██║██╔══██║██║╚██╗██║██║  ██║██╔══██║
#  ███████║██║  ██║██║  ██║██║ ╚████║██████╔╝██║  ██║
#  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝
#
#  Universal VM Bootstrapper v5.0 - Actually Working
#  Made with ❤️ by Shahriar (Shanda Bhai 💖)
# ═══════════════════════════════════════════════════════════════════

set -e
VERSION="5.0.0"
CONFIG_FILE="/root/.shanda/config"

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; P='\033[0;35m'; W='\033[1;37m'; NC='\033[0m'

log() { echo -e "${G}[✓]${NC} $1"; }
warn() { echo -e "${Y}[!]${NC} $1"; }
err() { echo -e "${R}[✗]${NC} $1"; exit 1; }
ask() { echo -e "${P}[?]${NC} $1"; }

banner() {
    clear
    echo -e "${C}"
    cat << 'EOF'
  ███████╗██╗  ██╗ █████╗ ███╗   ██╗██████╗  █████╗ 
  ██╔════╝██║  ██║██╔══██╗████╗  ██║██╔══██╗██╔══██╗
  ███████╗███████║███████║██╔██╗ ██║██║  ██║███████║
  ╚════██║██╔══██║██╔══██║██║╚██╗██║██║  ██║██╔══██║
  ███████║██║  ██║██║  ██║██║ ╚████║██████╔╝██║  ██║
  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝
EOF
    echo -e "${NC}"
    echo -e "         ${W}VM Bootstrapper v${VERSION}${NC}"
    echo -e "         ${P}Made with ❤️  by Shahriar${NC}\n"
}

# Find best disk
find_disk() {
    lsblk -ndo NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | \
        awk '/disk/ && !/loop/ && $4=="" {print $1}' | \
        head -1
}

# Get user input
get_input() {
    banner
    
    ask "Enter VM username"; read -p "> " VM_USER
    VM_USER=${VM_USER:-ubuntu}
    
    ask "Enter VM password"; read -p "> " VM_PASS
    VM_PASS=${VM_PASS:-password123}
    
    ask "Enter VM hostname"; read -p "> " VM_HOST
    VM_HOST=${VM_HOST:-shanda-vm}
    
    ask "SSH port (forwarded to host)"; read -p "> " SSH_PORT
    SSH_PORT=${SSH_PORT:-2222}
    
    ask "VM CPUs"; read -p "> " VM_CPU
    VM_CPU=${VM_CPU:-2}
    
    ask "VM RAM (MB)"; read -p "> " VM_RAM
    VM_RAM=${VM_RAM:-4096}
    
    ask "VM Disk (GB)"; read -p "> " VM_DISK
    VM_DISK=${VM_DISK:-50}
    
    STORAGE_DISK=$(find_disk)
    [ -z "$STORAGE_DISK" ] && STORAGE_DISK="sdb"
    STORAGE_PART="${STORAGE_DISK}1"
    MOUNT_DIR="/mnt/shanda"
    
    log "Configuration:"
    echo "  User: $VM_USER"
    echo "  Pass: $VM_PASS"
    echo "  Host: $VM_HOST"
    echo "  SSH:  localhost:$SSH_PORT"
    echo "  Spec: ${VM_CPU}CPU/${VM_RAM}MB/${VM_DISK}GB"
    echo "  Disk: /dev/$STORAGE_DISK"
    echo ""
    ask "Continue? (y/n)"; read -p "> " confirm
    [[ ! "$confirm" =~ ^[Yy] ]] && exit 0
}

# Save config
save_config() {
    mkdir -p /root/.shanda
    cat > "$CONFIG_FILE" << EOF
VM_USER="$VM_USER"
VM_PASS="$VM_PASS"
VM_HOST="$VM_HOST"
SSH_PORT="$SSH_PORT"
VM_CPU="$VM_CPU"
VM_RAM="$VM_RAM"
VM_DISK="$VM_DISK"
STORAGE_DISK="$STORAGE_DISK"
STORAGE_PART="$STORAGE_PART"
MOUNT_DIR="$MOUNT_DIR"
VM_DISK_PATH="$MOUNT_DIR/${VM_HOST}.qcow2"
CLOUD_INIT_ISO="$MOUNT_DIR/cloud-init.iso"
EOF
}

# Install packages
install_packages() {
    log "Installing packages..."
    export DEBIAN_FRONTEND=noninteractive
    
    apt-get update -qq
    apt-get install -y -qq \
        qemu-system-x86 qemu-kvm qemu-utils \
        cloud-image-utils \
        wget curl screen jq cron \
        openssh-server openssh-client \
        net-tools vim htop \
        > /dev/null 2>&1
    
    # Start cron
    service cron start > /dev/null 2>&1 || true
    
    log "Packages installed"
}

# Setup storage
setup_storage() {
    log "Setting up storage..."
    
    # Format if needed
    if ! blkid /dev/$STORAGE_PART 2>/dev/null | grep -q ext4; then
        mkfs.ext4 -F /dev/$STORAGE_PART > /dev/null 2>&1
    fi
    
    # Mount
    mkdir -p $MOUNT_DIR
    if ! mountpoint -q $MOUNT_DIR; then
        mount /dev/$STORAGE_PART $MOUNT_DIR
    fi
    
    # Add to fstab
    if ! grep -q "$STORAGE_PART" /etc/fstab; then
        echo "/dev/$STORAGE_PART $MOUNT_DIR ext4 defaults 0 2" >> /etc/fstab
    fi
    
    log "Storage ready: $(df -h $MOUNT_DIR | tail -1 | awk '{print $4}') free"
}

# Download Ubuntu image
download_image() {
    log "Downloading Ubuntu 24.04..."
    
    IMG="$MOUNT_DIR/ubuntu-24.04.img"
    if [ -f "$IMG" ]; then
        log "Image exists, skipping"
        return
    fi
    
    wget -q --show-progress \
        -O "$IMG" \
        "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    
    log "Image downloaded"
}

# Create VM disk
create_disk() {
    log "Creating VM disk..."
    
    VM_DISK_PATH="$MOUNT_DIR/${VM_HOST}.qcow2"
    
    if [ -f "$VM_DISK_PATH" ]; then
        warn "VM disk exists, skipping"
        return
    fi
    
    qemu-img convert -f qcow2 -O qcow2 \
        "$MOUNT_DIR/ubuntu-24.04.img" \
        "$VM_DISK_PATH" > /dev/null 2>&1
    
    qemu-img resize "$VM_DISK_PATH" "${VM_DISK}G" > /dev/null 2>&1
    
    log "VM disk created (${VM_DISK}GB)"
}

# Create cloud-init
create_cloud_init() {
    log "Configuring cloud-init..."
    
    CLOUD_INIT_DIR="$MOUNT_DIR/cloud-init"
    mkdir -p "$CLOUD_INIT_DIR"
    
    PASS_HASH=$(openssl passwd -6 "$VM_PASS")
    
    cat > "$CLOUD_INIT_DIR/user-data" << EOF
#cloud-config
hostname: $VM_HOST
fqdn: ${VM_HOST}.local

users:
  - name: $VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: $PASS_HASH

package_update: true
packages:
  - openssh-server
  - curl
  - wget
  - vim
  - htop
  - git

runcmd:
  - systemctl enable ssh
  - systemctl start ssh
  - sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - systemctl restart ssh
  - echo '${VM_USER}:${VM_PASS}' | chpasswd
  - echo 'root:${VM_PASS}' | chpasswd
  - echo "VM Ready! SSH: ssh ${VM_USER}@<host> -p ${SSH_PORT}" > /etc/motd

ssh_pwauth: true
disable_root: false
EOF

    cat > "$CLOUD_INIT_DIR/meta-data" << EOF
instance-id: $VM_HOST
local-hostname: $VM_HOST
EOF

    cloud-localds "$MOUNT_DIR/cloud-init.iso" \
        "$CLOUD_INIT_DIR/user-data" \
        "$CLOUD_INIT_DIR/meta-data" \
        > /dev/null 2>&1
    
    log "Cloud-init ready"
}

# Create VM starter
create_starter() {
    cat > /usr/local/bin/shanda-start << 'STARTER'
#!/bin/bash
source /root/.shanda/config

# Kill old VM
pkill -9 qemu-system 2>/dev/null
sleep 2

# Mount storage
mountpoint -q $MOUNT_DIR || mount /dev/$STORAGE_PART $MOUNT_DIR

# Check disk exists
[ ! -f "$VM_DISK_PATH" ] && echo "[✗] VM disk not found" && exit 1

# Start QEMU in screen
screen -dmS shanda-vm bash -c "
qemu-system-x86_64 \
    -name $VM_HOST \
    -machine type=q35,accel=kvm \
    -cpu host \
    -smp $VM_CPU \
    -m $VM_RAM \
    -drive file=$VM_DISK_PATH,format=qcow2,if=virtio \
    -drive file=$CLOUD_INIT_ISO,format=raw,if=virtio \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::8443-:443 \
    -nographic \
    -serial mon:stdio
"

sleep 3
if screen -list | grep -q shanda-vm; then
    echo "[✓] VM started in screen"
    echo "[i] Attach: screen -r shanda-vm"
else
    echo "[✗] VM failed to start"
    exit 1
fi
STARTER
    chmod +x /usr/local/bin/shanda-start
}

# Create watchdog
create_watchdog() {
    cat > /usr/local/bin/shanda-watch << 'WATCH'
#!/bin/bash
source /root/.shanda/config

while true; do
    # Mount storage if needed
    mountpoint -q $MOUNT_DIR || mount /dev/$STORAGE_PART $MOUNT_DIR 2>/dev/null
    
    # Check if VM running
    if ! screen -list | grep -q shanda-vm; then
        echo "[$(date)] VM died, restarting..." >> /var/log/shanda.log
        /usr/local/bin/shanda-start >> /var/log/shanda.log 2>&1
    fi
    
    sleep 30
done
WATCH
    chmod +x /usr/local/bin/shanda-watch
}

# Setup autostart
setup_autostart() {
    log "Setting up autostart..."
    
    # Cron method
    (crontab -l 2>/dev/null | grep -v shanda; cat << 'CRON'
@reboot sleep 10 && /usr/local/bin/shanda-start >> /var/log/shanda-boot.log 2>&1
@reboot sleep 20 && /usr/local/bin/shanda-watch >> /var/log/shanda-boot.log 2>&1 &
CRON
) | crontab -
    
    # Profile method
    for f in /root/.bashrc /root/.profile; do
        grep -q shanda-watch "$f" 2>/dev/null || echo '
# Shanda autostart
pgrep -f shanda-watch > /dev/null || nohup /usr/local/bin/shanda-watch > /dev/null 2>&1 &
' >> "$f"
    done
    
    log "Autostart configured"
}

# Create CLI
create_cli() {
    cat > /usr/local/bin/shanda << 'CLI'
#!/bin/bash
[ -f /root/.shanda/config ] && source /root/.shanda/config || { echo "Not installed"; exit 1; }

case "${1:-status}" in
    start)
        /usr/local/bin/shanda-start
        ;;
    stop)
        screen -X -S shanda-vm quit 2>/dev/null
        pkill -9 qemu-system
        echo "[✓] VM stopped"
        ;;
    restart)
        $0 stop
        sleep 3
        $0 start
        ;;
    status)
        echo "═══ Shanda Status ═══"
        if screen -list | grep -q shanda-vm; then
            echo "[✓] VM Running"
        else
            echo "[✗] VM Not Running"
        fi
        echo ""
        echo "SSH: ssh $VM_USER@localhost -p $SSH_PORT"
        echo "Pass: $VM_PASS"
        ;;
    ssh)
        ssh $VM_USER@localhost -p $SSH_PORT
        ;;
    console)
        screen -r shanda-vm
        ;;
    logs)
        tail -f /var/log/shanda.log
        ;;
    *)
        echo "Shanda v5.0 Commands:"
        echo "  start    - Start VM"
        echo "  stop     - Stop VM"
        echo "  restart  - Restart VM"
        echo "  status   - Show status"
        echo "  ssh      - Connect via SSH"
        echo "  console  - Attach to console (Ctrl+A D to detach)"
        echo "  logs     - View logs"
        ;;
esac
CLI
    chmod +x /usr/local/bin/shanda
}

# Main installation
main() {
    [ "$EUID" -ne 0 ] && err "Run as root: sudo bash $0"
    
    # Check KVM
    [ ! -e /dev/kvm ] && err "KVM not available - enable nested virtualization"
    
    # Check if already installed
    if [ -f "$CONFIG_FILE" ]; then
        log "Already installed"
        exec /usr/local/bin/shanda "$@"
    fi
    
    # Fresh install
    get_input
    save_config
    install_packages
    setup_storage
    download_image
    create_disk
    create_cloud_init
    create_starter
    create_watchdog
    setup_autostart
    create_cli
    
    # Start VM
    log "Starting VM..."
    /usr/local/bin/shanda-start
    
    sleep 5
    
    # Start watchdog
    nohup /usr/local/bin/shanda-watch > /dev/null 2>&1 &
    
    echo ""
    echo -e "${G}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${G}║          🎉 Installation Complete! 🎉       ║${NC}"
    echo -e "${G}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    log "VM is booting (takes ~2 minutes)"
    echo ""
    echo -e "${C}Connection:${NC}"
    echo "  ssh $VM_USER@localhost -p $SSH_PORT"
    echo "  Password: $VM_PASS"
    echo ""
    echo -e "${C}Commands:${NC}"
    echo "  shanda status   - Check if running"
    echo "  shanda ssh      - Connect"
    echo "  shanda console  - VM console (Ctrl+A D to exit)"
    echo "  shanda restart  - Restart VM"
    echo ""
    echo -e "${Y}⏳ Wait 2 minutes for VM to boot, then: shanda ssh${NC}"
    echo ""
}

main "$@"

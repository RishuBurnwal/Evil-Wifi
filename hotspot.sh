#!/bin/bash

# Exit on error
set -e

# Import logger
source logger.sh

# Load configuration from config.ini
CONFIG_FILE="config.ini"

# Default values
SSID="SecureHotspot_$(hostname | cut -d'.' -f1)"
CHANNEL=6
WPA_PASSPHRASE="SecurePass123"
IP_RANGE="192.168.100.100,192.168.100.200,255.255.255.0"
GATEWAY="192.168.100.1"

# Load configuration if config.ini exists
if [ -f "$CONFIG_FILE" ]; then
    # Load hotspot configuration
    if grep -q "\[HOTSPOT\]" "$CONFIG_FILE"; then
        SSID_PREFIX=$(grep -A 10 "\[HOTSPOT\]" "$CONFIG_FILE" | grep "SSID_PREFIX=" | cut -d'=' -f2 | tr -d ' ' || echo "$SSID")
        CHANNEL=$(grep -A 10 "\[HOTSPOT\]" "$CONFIG_FILE" | grep "CHANNEL=" | cut -d'=' -f2 | tr -d ' ' || echo "$CHANNEL")
        WPA_PASSPHRASE=$(grep -A 10 "\[HOTSPOT\]" "$CONFIG_FILE" | grep "WPA_PASSPHRASE=" | cut -d'=' -f2 | tr -d ' ' || echo "$WPA_PASSPHRASE")
        IP_RANGE=$(grep -A 10 "\[HOTSPOT\]" "$CONFIG_FILE" | grep "IP_RANGE=" | cut -d'=' -f2 | tr -d ' ' || echo "$IP_RANGE")
        GATEWAY=$(grep -A 10 "\[HOTSPOT\]" "$CONFIG_FILE" | grep "GATEWAY=" | cut -d'=' -f2 | tr -d ' ' || echo "$GATEWAY")
    fi
    
    # Use SSID prefix if available
    if [ -n "$SSID_PREFIX" ] && [ "$SSID_PREFIX" != "$SSID" ]; then
        SSID="${SSID_PREFIX}$(hostname | cut -d'.' -f1)"
    fi
fi

# Configuration
INTERFACE=$1

# Validate input
if [ -z "$INTERFACE" ]; then
    log "ERROR" "No interface specified"
    exit 1
fi

# Check if interface exists
if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    log "ERROR" "Interface $INTERFACE not found"
    exit 1
fi

# Get the interface used for internet connection (not SSH specifically)
INTERNET_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)

# Function to clean up on exit
cleanup() {
    log "INFO" "Cleaning up..."
    # Kill our specific processes
    pkill -f "dnsmasq.*$INTERFACE" 2>/dev/null || true
    pkill -f "hostapd.*$INTERFACE" 2>/dev/null || true
    # Bring down our interface
    ip link set "$INTERFACE" down 2>/dev/null || true
    # Flush iptables rules we added
    iptables -t nat -D POSTROUTING -o "$INTERNET_IFACE" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "$INTERFACE" -o "$INTERNET_IFACE" -j ACCEPT 2>/dev/null || true
    log "INFO" "Cleanup complete."
}

# Set up trap to call cleanup function on script exit
trap cleanup EXIT INT TERM

# Stop any conflicting services
log "INFO" "Stopping conflicting services..."
systemctl stop NetworkManager 2>/dev/null || true
systemctl stop wpa_supplicant 2>/dev/null || true

# Release DHCP lease for the interface
dhclient -r "$INTERFACE" 2>/dev/null || true

# Configure interface
log "INFO" "Configuring interface $INTERFACE..."
ip link set "$INTERFACE" down
sleep 1
ip addr flush dev "$INTERFACE" 2>/dev/null || true
ip addr add "$GATEWAY/24" dev "$INTERFACE"
ip link set "$INTERFACE" up
sleep 2

# Configure hostapd
log "INFO" "Configuring hostapd..."
cat > "/tmp/hostapd_$INTERFACE.conf" <<EOF
interface=$INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WPA_PASSPHRASE
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
EOF

# Configure dnsmasq
log "INFO" "Configuring dnsmasq..."
cat > "/tmp/dnsmasq_$INTERFACE.conf" <<EOF
# Interface configuration
interface=$INTERFACE
# DHCP configuration
dhcp-range=$IP_RANGE,12h
dhcp-option=3,$GATEWAY
dhcp-option=6,$GATEWAY
# DNS configuration
server=8.8.8.8
server=8.8.4.4
# Logging
log-queries
log-dhcp
# Security
bind-interfaces
no-resolv
no-hosts
EOF

# Enable IP forwarding
log "INFO" "Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward

# Configure NAT
log "INFO" "Configuring NAT with internet interface $INTERNET_IFACE..."
iptables -t nat -A POSTROUTING -o "$INTERNET_IFACE" -j MASQUERADE
iptables -A FORWARD -i "$INTERFACE" -o "$INTERNET_IFACE" -j ACCEPT
iptables -A FORWARD -i "$INTERNET_IFACE" -o "$INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT

# Start services
log "INFO" "Starting dnsmasq..."
dnsmasq -C "/tmp/dnsmasq_$INTERFACE.conf" -d > "/tmp/dnsmasq_$INTERFACE.log" 2>&1 &
DNSMASQ_PID=$!

# Give dnsmasq a moment to start
sleep 2

# Verify dnsmasq is running
if ! ps -p $DNSMASQ_PID > /dev/null; then
    log "ERROR" "Failed to start dnsmasq. Check /tmp/dnsmasq_$INTERFACE.log for details."
    exit 1
fi

log "INFO" "Starting hostapd..."
hostapd -B "/tmp/hostapd_$INTERFACE.conf" > "/tmp/hostapd_$INTERFACE.log" 2>&1
HOSTAPD_PID=$!

# Give hostapd a moment to start
sleep 3

# Verify hostapd is running
if ! ps -p $HOSTAPD_PID > /dev/null; then
    log "ERROR" "Failed to start hostapd. Check /tmp/hostapd_$INTERFACE.log for details."
    exit 1
fi

log "INFO" "Hotspot is now running!"
log "INFO" "SSID: $SSID"
log "INFO" "Password: $WPA_PASSPHRASE"
log "INFO" "IP Range: $IP_RANGE"
log "INFO" "Gateway: $GATEWAY"
log "INFO" "Internet Interface: $INTERNET_IFACE"

# Display hotspot information directly to user (send to stderr so it doesn't interfere with logging)
echo "==========================================" >&2
echo "WiFi Hotspot is now running!" >&2
echo "==========================================" >&2
echo "SSID:     $SSID" >&2
echo "Password: $WPA_PASSPHRASE" >&2
echo "IP Range: $IP_RANGE" >&2
echo "Gateway:  $GATEWAY" >&2
echo "==========================================" >&2
echo "Connect your devices to the hotspot now." >&2
echo "Press Ctrl+C to stop the hotspot." >&2
echo "==========================================" >&2

# Keep the script running
while true; do
    sleep 60
    # Check if our processes are still running
    if ! ps -p $DNSMASQ_PID > /dev/null || ! ps -p $HOSTAPD_PID > /dev/null; then
        log "ERROR" "One of the services has stopped unexpectedly"
        exit 1
    fi
done
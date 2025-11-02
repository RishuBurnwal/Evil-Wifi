#!/bin/bash

# Import logger
source logger.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to setup hotspot
setup_hotspot() {
    local wifi_iface=$1
    local internet_iface=$2
    
    log "INFO" "Setting up hotspot on $wifi_iface with internet from $internet_iface"
    
    # Configure IP address
    sudo ip addr add 192.168.100.1/24 dev "$wifi_iface"
    sudo ip link set "$wifi_iface" up
    
    # Enable IP forwarding
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    
    # Configure NAT
    sudo iptables -t nat -A POSTROUTING -o "$internet_iface" -j MASQUERADE
    sudo iptables -A FORWARD -i "$wifi_iface" -o "$internet_iface" -j ACCEPT
    sudo iptables -A FORWARD -i "$internet_iface" -o "$wifi_iface" -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Configure hostapd
    cat << EOF | sudo tee /etc/hostapd/hostapd.conf
interface=$wifi_iface
driver=nl80211
ssid=Hotspot_$(hostname)
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=ConnectMe123
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

    # Configure dnsmasq
    cat << EOF | sudo tee /etc/dnsmasq.conf
interface=$wifi_iface
dhcp-range=192.168.100.100,192.168.100.200,255.255.255.0,24h
dhcp-option=3,192.168.100.1
dhcp-option=6,8.8.8.8,8.8.4.4
server=8.8.8.8
server=8.8.4.4
EOF

    # Start services
    sudo systemctl unmask hostapd
    sudo systemctl enable hostapd
    sudo systemctl restart hostapd
    sudo systemctl restart dnsmasq
    
    log "INFO" "Hotspot setup complete!"
    log "INFO" "SSID: Hotspot_$(hostname)"
    log "INFO" "Password: ConnectMe123"
    log "INFO" "IP Range: 192.168.100.100-200"
}

# Main execution
main() {
    log "INFO" "Starting WiFi Hotspot Setup"
    
    # Detect internet interface
    log "INFO" "Detecting internet connection..."
    internet_iface=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
    if [ -z "$internet_iface" ]; then
        log "ERROR" "No internet connection detected!"
        exit 1
    fi
    log "INFO" "Internet connection detected on $internet_iface"
    
    # List available wireless interfaces
    interfaces=($(iw dev | awk '/Interface/ {print $2}'))
    if [ ${#interfaces[@]} -eq 0 ]; then
        log "ERROR" "No wireless interfaces found!"
        exit 1
    fi
    
    # Select WiFi interface
    echo -e "${YELLOW}Select WiFi interface for hotspot:${NC}"
    select wifi_iface in "${interfaces[@]}" "Quit"; do
        if [ "$wifi_iface" == "Quit" ]; then
            log "INFO" "Exiting..."
            exit 0
        elif [[ " ${interfaces[@]} " =~ " ${wifi_iface} " ]]; then
            break
        else
            echo -e "${RED}Invalid selection. Try again.${NC}"
        fi
    done
    
    # Confirm setup
    echo -e "${YELLOW}Setup Summary:${NC}"
    echo "WiFi Interface: $wifi_iface"
    echo "Internet Source: $internet_iface"
    echo "SSID: Hotspot_$(hostname)"
    echo "Password: ConnectMe123"
    echo ""
    
    read -p "Proceed with setup? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_hotspot "$wifi_iface" "$internet_iface"
    else
        log "INFO" "Setup cancelled."
    fi
}

# Run main function
main "$@"

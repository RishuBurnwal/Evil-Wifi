#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}Updating package lists...${NC}"
apt-get update

# Install system packages
echo -e "\n${GREEN}Installing system packages...${NC}"
apt-get install -y hostapd dnsmasq tcpdump python3-pip net-tools iw iproute2

# Stop and disable services to prevent conflicts
echo -e "\n${GREEN}Configuring services...${NC}"
systemctl stop hostapd
systemctl stop dnsmasq
systemctl disable hostapd
systemctl disable dnsmasq

# Install Python packages
echo -e "\n${GREEN}Installing Python packages...${NC}
pip3 install pyshark scapy colorama

# Make scripts executable
chmod +x *.sh

# Create necessary directories
mkdir -p logs pcap_logs

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "Run 'sudo ./main.sh' to start the WiFi Hotspot and Activity Logger."

exit 0

#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== WiFi Interface Detection Test ===${NC}\n"

echo -e "${YELLOW}1. Checking for wireless tools...${NC}"
for tool in iw iwconfig ip; do
    if command -v $tool >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $tool found at $(which $tool)"
    else
        echo -e "${RED}✗${NC} $tool not found"
    fi
done

echo -e "\n${YELLOW}2. Checking network interfaces...${NC}"
echo -e "\n${GREEN}Network interfaces:${NC}"
ip -o link show | awk -F': ' '{print $2}'

echo -e "\n${YELLOW}3. Checking wireless interfaces...${NC}"

# Method 1: Using ip command
echo -e "\n${GREEN}Method 1: Using 'ip' command:${NC}"
ip -o link show | grep -i wireless | awk -F': ' '{print $2}' || echo "No wireless interfaces found with 'ip' command"

# Method 2: Using iwconfig
echo -e "\n${GREEN}Method 2: Using 'iwconfig' command:${NC}"
iwconfig 2>/dev/null | grep -o '^[^ ]\+' || echo "No wireless interfaces found with 'iwconfig' command"

# Method 3: Using iw
echo -e "\n${GREEN}Method 3: Using 'iw' command:${NC}"
iw dev 2>/dev/null | awk '/Interface/ {print $2}' || echo "No wireless interfaces found with 'iw' command"

# Method 4: Checking /sys/class/net
echo -e "\n${GREEN}Method 4: Checking /sys/class/net:${NC}"
for iface in $(ls /sys/class/net); do
    if [ -d "/sys/class/net/$iface/wireless" ] || [ -d "/sys/class/net/$iface/phy80211" ]; then
        echo "Found wireless interface: $iface"
        echo "  Driver: $(readlink -f /sys/class/net/$iface/device/driver 2>/dev/null || echo 'Unknown')"
        echo "  Operstate: $(cat /sys/class/net/$iface/operstate 2>/dev/null || echo 'Unknown')"
    fi
done

echo -e "\n${YELLOW}4. Checking for blocked interfaces...${NC}"
if command -v rfkill >/dev/null 2>&1; then
    rfkill list
else
    echo "rfkill command not found. Install it with 'sudo apt install rfkill'"
fi

echo -e "\n${YELLOW}5. Checking loaded wireless modules...${NC}"
lsmod | grep -E 'wifi|80211|wlan|ath[0-9]|rtl[0-9]' || echo "No wireless modules loaded"

echo -e "\n${YELLOW}6. Checking kernel messages...${NC}"
dmesg | grep -i 'wlan\|wifi\|80211\|firmware' | tail -n 20

echo -e "\n${GREEN}=== Test Complete ===${NC}"
echo "Please share the output of this script for further assistance."

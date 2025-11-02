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

echo "Checking for required dependencies..."

# List of required commands and their packages
declare -A REQUIRED=(
    ["hostapd"]="hostapd"
    ["dnsmasq"]="dnsmasq"
    ["tcpdump"]="tcpdump"
    ["python3"]="python3"
    ["pip3"]="python3-pip"
    ["ifconfig"]="net-tools"
    ["iw"]="iw"
    ["ip"]="iproute2"
)

# Check each command
MISSING_DEPS=0
for cmd in "${!REQUIRED[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}✗${NC} $cmd (package: ${REQUIRED[$cmd]})"
        ((MISSING_DEPS++))
    else
        echo -e "${GREEN}✓${NC} $cmd"
    fi
done

# Check Python packages
PYTHON_DEPS=("pyshark" "scapy" "colorama")
for pkg in "${PYTHON_DEPS[@]}"; do
    if ! python3 -c "import $pkg" &> /dev/null; then
        echo -e "${RED}✗${NC} Python package: $pkg"
        ((MISSING_DEPS++))
    else
        echo -e "${GREEN}✓${NC} Python package: $pkg"
    fi
done

# Print results
if [ $MISSING_DEPS -eq 0 ]; then
    echo -e "\n${GREEN}All dependencies are installed!${NC}"
else
    echo -e "\n${RED}$MISSING_DEPS dependencies are missing.${NC}"
    echo -e "Run 'sudo ./install_deps.sh' to install missing dependencies."
    exit 1
fi

exit 0

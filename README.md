# Evil WiFi - Advanced WiFi Hotspot and Network Monitoring Toolkit

A comprehensive security tool for creating WPA2-encrypted WiFi hotspots with advanced network monitoring, traffic capture, and credential extraction capabilities. Originally designed for TP-Link Archer T2U PLUS (RTL8821AU chipset) but compatible with other wireless adapters supporting AP and Monitor modes.

## ⚠️ Legal Disclaimer

This tool is for educational and authorized security testing purposes only. Unauthorized use of this tool to monitor or intercept network traffic is illegal and unethical. Always obtain proper authorization before testing any network.

## Features

- 🔐 **Secure WiFi Hotspot**: Create WPA2-encrypted access points
- 📡 **Multi-Adapter Support**: Works with various wireless chipsets
- 🕵️ **Traffic Monitoring**: Real-time network activity logging
- 📦 **Packet Capture**: Full packet capture with tcpdump
- 🍪 **Data Extraction**: Extract cookies, credentials, and visited URLs
- 📊 **Comprehensive Logging**: Detailed logs with unique IDs for each event
- 🎛️ **Interactive Menu**: User-friendly interface with multiple options
- 🔄 **GitHub Integration**: Automatic updates from remote repository
- 🧹 **Data Management**: Selective deletion of logs and captured data
- ⚙️ **Centralized Configuration**: Easy customization via config.ini

## Hardware Compatibility

- **Primary Tested Adapter**: TP-Link Archer T2U PLUS
- **Chipset**: Realtek RTL8821AU
- **Alternative Adapters**: Any adapter supporting AP and Monitor modes
- **Supported Modes**: Access Point (AP) and Monitor

## Prerequisites

- Linux-based operating system (Kali Linux recommended)
- Root/sudo access
- Compatible wireless adapter
- Internet connection for initial setup
- Minimum 2GB RAM (4GB recommended)
- At least 2GB free disk space

## Installation

### 1. Clone the Repository
```bash
git clone https://github.com/RishuBurnwal/Evil-Wifi.git
cd Evil-Wifi
```

### 2. Install Required Dependencies
```bash
sudo apt update
sudo apt install -y hostapd dnsmasq iptables tcpdump python3-pip git
```

### 3. Install Python Dependencies
```bash
pip3 install pyshark scapy
```

### 4. Make Scripts Executable
```bash
chmod +x *.sh
```

### 5. WiFi Driver Installation (for TP-Link Archer T2U PLUS)
```bash
# Install required dependencies
sudo apt install -y dkms git build-essential libelf-dev linux-headers-$(uname -r)

# Clone and install RTL8812AU driver
git clone https://github.com/aircrack-ng/rtl8812au.git
cd rtl8812au
make
sudo make install
sudo modprobe 8812au

# Make it persistent across reboots
echo "8812au" | sudo tee -a /etc/modules
```

## Configuration

Customize the hotspot settings in `config.ini`:

```ini
[HOTSPOT]
SSID_PREFIX=MyHotspot
CHANNEL=6
WPA_PASSPHRASE=SecurePass123
IP_RANGE=192.168.100.100,192.168.100.200,255.255.255.0
GATEWAY=192.168.100.1

[LOGGING]
LOG_LEVEL=INFO
LOG_FILE=logs/hotspot.log
PCAP_DIR=pcap_logs/
PCAP_FILE=capture.pcap

[CAPTURE]
CAPTURE_FILTER=tcp port http or tcp port https or tcp port 8080 or tcp port 8443
SNAPLEN=0
PROMISCUOUS=true

[EXTRACTION]
OUTPUT_DIR=logs/
COOKIE_FILE=cookies.txt
CREDENTIALS_FILE=credentials.txt
```

## Usage

### Interactive Menu System
Run the main script to access the interactive menu:
```bash
sudo ./main.sh
```

### Menu Options
1. **Select WiFi Adapter**: Manually choose your wireless interface
2. **Use Default WiFi Adapter**: Auto-select the first compatible adapter
3. **Update Software**: Check for and install updates from GitHub
4. **Check Dependencies**: Verify all required packages are installed
5. **Project Setup**: Initialize or reconfigure the project
6. **View Logs**: Access various log files with multiple viewing options
7. **Delete Data**: Selectively remove logs, captures, or all data
8. **Exit**: Safely terminate the application

### Advanced Features

#### Log Viewing Options
- View logs in terminal with pagination (10, 50, 100, or all entries)
- Open log files directly in your preferred editor
- Search functionality within logs
- Support for all log types (software, hotspot, capture, cookies, credentials, URLs)

#### Data Deletion Options
- Delete all data (logs, captures, cookies, credentials, URLs)
- Delete all logs
- Delete specific log types (hotspot, software, capture)
- Delete packet captures only
- Delete extracted data (cookies, credentials, URLs)

#### Software Update System
- Automatic checking against GitHub repository
- Detailed change logs before updating
- Safe update process with local change preservation
- Automatic restart after successful updates

## Logs and Outputs

All data is organized in structured directories:

```
logs/
├── hotspot.log          # Hotspot operation logs
├── software.log         # Software lifecycle events
├── capture.log          # Packet capture logs
├── cookies.txt          # Extracted HTTP cookies
├── credentials.txt      # Potential credentials
└── urls.txt             # Visited URLs

pcap_logs/
└── capture.pcap         # Full packet capture files
```

## Security Considerations

- Change default credentials in `config.ini`
- Regularly clean up logs and captured data
- Monitor disk usage to prevent storage issues
- Use only on networks you own or have explicit permission to test
- Be aware of legal implications in your jurisdiction

## Troubleshooting

### Common Issues
- **No wireless interfaces detected**: Ensure your adapter is properly connected and drivers are installed
- **Hotspot fails to start**: Check for conflicting services (`sudo systemctl stop NetworkManager`)
- **No internet sharing**: Verify the internet interface is correctly detected
- **Packet capture issues**: Ensure tcpdump is installed and has proper permissions

### Diagnostic Commands
```bash
# Check wireless interfaces
iwconfig

# Verify AP mode support
iw list | grep "AP"

# Check if required services are running
systemctl status hostapd dnsmasq

# View recent logs
tail -f logs/hotspot.log
```

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a pull request

## License

This project is for educational purposes only. The authors are not responsible for any misuse of this tool. Always ensure you have proper authorization before conducting any network testing.

## Acknowledgments

- Thanks to the aircrack-ng team for RTL8812AU driver
- Inspired by various network security research projects
- Built for educational cybersecurity purposes
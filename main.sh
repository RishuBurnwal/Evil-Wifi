#!/bin/bash

# Check if running as root, if not re-run with sudo
if [ "$EUID" -ne 0 ]; then
    # Make sure the script is executable
    chmod +x "$0"
    # Re-run with sudo, passing all arguments
    exec sudo "$0" "$@"
    exit 1
fi

# Create logs directory with proper permissions
mkdir -p logs
chmod 777 logs 2>/dev/null

# Import logger
source logger.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Demo remote GitHub URL for updates
GITHUB_REPO_URL="https://github.com/example/wifi-hotspot-logger.git"

# Function to detect internet connection
detect_internet() {
    log "INFO" "Detecting internet connection..."
    
    # Check for active internet connection
    if ping -c 1 8.8.8.8 &> /dev/null; then
        # Get the default route interface
        local default_iface=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
        if [ -n "$default_iface" ]; then
            local ip_addr=$(ip -4 addr show "$default_iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
            log "INFO" "Internet connection detected on $default_iface ($ip_addr)"
            echo "$default_iface"
            return 0
        fi
    fi
    
    log "WARNING" "No active internet connection detected"
    echo "none"
    return 1
}

# Function to list available wireless interfaces
list_wireless_interfaces() {
    log "INFO" "Detecting available wireless interfaces..."
    local interfaces=()
    local tempfile=$(mktemp)
    
    # Method 1: Try using 'iw' command
    if command -v iw >/dev/null 2>&1; then
        log "DEBUG" "Using 'iw' to detect wireless interfaces"
        iw dev 2>/dev/null | awk '/Interface/ {print $2}' > "$tempfile"
        while IFS= read -r iface; do
            [ -n "$iface" ] && interfaces+=("$iface")
        done < "$tempfile"
    fi
    
    # Method 2: Try using 'iwconfig' if no interfaces found yet
    if [ ${#interfaces[@]} -eq 0 ] && command -v iwconfig >/dev/null 2>&1; then
        log "DEBUG" "Using 'iwconfig' to detect wireless interfaces"
        iwconfig 2>/dev/null | grep -o '^[^ ]\+' | grep -v '^$' > "$tempfile"
        while IFS= read -r iface; do
            [ -n "$iface" ] && interfaces+=("$iface")
        done < "$tempfile"
    fi
    
    # Method 3: Check /sys/class/net if still no interfaces found
    if [ ${#interfaces[@]} -eq 0 ]; then
        log "DEBUG" "Using sysfs to detect wireless interfaces"
        for iface in /sys/class/net/*; do
            if [ -e "$iface/wireless" ]; then
                interfaces+=("$(basename "$iface")")
            fi
        done
    fi
    
    # Clean up temp file
    rm -f "$tempfile"
    
    # Display results
    if [ ${#interfaces[@]} -gt 0 ]; then
        log "INFO" "Found ${#interfaces[@]} wireless interface(s):"
        for i in "${!interfaces[@]}"; do
            local iface="${interfaces[$i]}"
            local capabilities=()
            
            # Check AP mode support
            if iw phy "$(cat "/sys/class/net/$iface/phy80211/name" 2>/dev/null)" info 2>/dev/null | grep -q "\* AP\>"; then
                capabilities+=("AP")
            fi
            
            # Check monitor mode support
            if iw phy "$(cat "/sys/class/net/$iface/phy80211/name" 2>/dev/null)" info 2>/dev/null | grep -q "\* monitor"; then
                capabilities+=("Monitor")
            fi
            
            # Display interface with capabilities
            if [ ${#capabilities[@]} -gt 0 ]; then
                log "INFO" "  $((i+1)). $iface (${capabilities[*]})"
            else
                log "INFO" "  $((i+1)). $iface"
            fi
        done
    else
        log "WARNING" "No wireless interfaces found!"
    fi
    
    # Return the list of interfaces
    printf '%s\n' "${interfaces[@]}"
    return ${#interfaces[@]}
}

# Function to select interface
select_interface() {
    local interfaces=("$@")
    local count=${#interfaces[@]}
    
    if [ $count -eq 0 ]; then
        log "ERROR" "No wireless interfaces available"
        return 1
    fi
    
    # If only one interface, use it
    if [ $count -eq 1 ]; then
        echo "${interfaces[0]}"
        return 0
    fi
    
    # Show menu for multiple interfaces
    echo -e "${YELLOW}Available wireless interfaces:${NC}"
    for i in "${!interfaces[@]}"; do
        echo -e "$((i+1)). ${interfaces[$i]}"
    done
    
    while true; do
        read -p "Select interface (1-$count): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $count ]; then
            echo "${interfaces[$((choice-1))]}"
            return 0
        fi
        echo -e "${RED}Invalid selection. Please try again.${NC}"
    done
}


# Function to check if interface supports AP mode
check_ap_mode() {
    local iface=$1
    
    # Check if interface exists
    if [ ! -d "/sys/class/net/$iface" ]; then
        log "WARNING" "Interface $iface does not exist"
        return 1
    fi
    
    # Get phy name
    local phy_path="/sys/class/net/$iface/phy80211/name"
    if [ ! -f "$phy_path" ]; then
        log "WARNING" "$iface is not a wireless interface"
        return 1
    fi
    
    local phy_name=$(cat "$phy_path" 2>/dev/null)
    if [ -z "$phy_name" ]; then
        log "WARNING" "Could not get PHY name for $iface"
        return 1
    fi
    
    # Check if interface supports AP mode
    if iw phy "$phy_name" info 2>/dev/null | grep -q "\* AP$"; then
        return 0
    else
        log "DEBUG" "$iface does not support AP mode"
        return 1
    fi
}

# Function to check if interface supports monitor mode
check_monitor_mode() {
    local iface=$1
    
    # Check if interface exists
    if [ ! -d "/sys/class/net/$iface" ]; then
        return 1
    fi
    
    # Get phy name
    local phy_path="/sys/class/net/$iface/phy80211/name"
    if [ ! -f "$phy_path" ]; then
        return 1
    fi
    
    local phy_name=$(cat "$phy_path" 2>/dev/null)
    if [ -z "$phy_name" ]; then
        return 1
    fi
    
    # Check if interface supports monitor mode
    if iw phy "$phy_name" info 2>/dev/null | grep -q "monitor"; then
        return 0
    else
        return 1
    fi
}

# Function to check for wireless tools
check_wireless_tools() {
    local missing=()
    
    for tool in iw iwconfig ip; do
        if ! command -v $tool >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log "WARNING" "Missing wireless tools: ${missing[*]}"
        log "INFO" "Installing required wireless tools..."
        
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y wireless-tools iw
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y wireless-tools iw
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y wireless-tools iw
        else
            log "ERROR" "Could not install required packages. Please install 'wireless-tools' and 'iw' manually."
            return 1
        fi
    fi
    
    return 0
}

# Function to handle script termination
cleanup() {
    log "INFO" "Stopping processes..."
    # Kill child processes
    if [ -n "$HOTSPOT_PID" ]; then
        kill -TERM $HOTSPOT_PID 2>/dev/null
    fi
    if [ -n "$CAPTURE_PID" ]; then
        kill -TERM $CAPTURE_PID 2>/dev/null
    fi
    
    # Wait for processes to terminate
    [ -n "$HOTSPOT_PID" ] && wait $HOTSPOT_PID 2>/dev/null
    [ -n "$CAPTURE_PID" ] && wait $CAPTURE_PID 2>/dev/null
    
    # Process captured data if any
    if [ -f "pcap_logs/capture.pcap" ] && [ -s "pcap_logs/capture.pcap" ]; then
        log "INFO" "Processing captured traffic..."
        
        # Check if pyshark is installed
        if python3 -c "import pyshark" 2>/dev/null; then
            log "INFO" "Extracting cookies..."
            if [ -f "cookie_extractor.py" ]; then
                python3 cookie_extractor.py "pcap_logs/capture.pcap"
                
                if [ -f "logs/cookies.txt" ]; then
                    log "INFO" "Cookies extracted to logs/cookies.txt"
                else
                    log "WARNING" "No cookies were extracted from the capture"
                fi
            else
                log "WARNING" "cookie_extractor.py not found. Skipping cookie extraction."
            fi
        else
            log "WARNING" "pyshark Python module not found. Install it with: pip install pyshark"
        fi
    else
        log "WARNING" "No capture file found or file is empty at pcap_logs/capture.pcap"
    fi
    
    log "INFO" "All operations completed. Check logs in the 'logs' folder."
    exit 0
}

# Set up trap to catch termination signals
trap cleanup INT TERM

# Function to display main menu
show_main_menu() {
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}WiFi Hotspot and Activity Logger${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "1. Select WiFi Adapter (Manual Selection)"
    echo -e "2. Use Default WiFi Adapter (Auto-select)"
    echo -e "3. Update Software"
    echo -e "4. Check Dependencies"
    echo -e "5. Project Setup"
    echo -e "6. View Logs"
    echo -e "7. Delete Data"
    echo -e "8. Extract Data"
    echo -e "9. Exit"
    echo -e "${GREEN}==========================================${NC}"
}

# Function to display terminal options menu
show_terminal_options() {
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}Terminal Options${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "1. Open separate terminals for each component"
    echo -e "2. Run everything in current terminal"
    echo -e "3. Run in background with logging only"
    echo -e "${GREEN}==========================================${NC}"
}

# Function to display log viewing options
show_log_menu() {
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}Log Viewing Options${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "1. View Software Logs in Terminal"
    echo -e "2. Open Software Log File"
    echo -e "3. View Hotspot Logs in Terminal"
    echo -e "4. Open Hotspot Log File"
    echo -e "5. View Packet Capture Logs"
    echo -e "6. View Cookies Log"
    echo -e "7. View Credentials Log"
    echo -e "8. View URLs Log"
    echo -e "9. Back to Main Menu"
    echo -e "${GREEN}==========================================${NC}"
}

# Function to display data deletion options
show_delete_menu() {
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}Data Deletion Options${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "1. Delete All Data (Logs, Captures, Cookies, Credentials, URLs)"
    echo -e "2. Delete All Logs"
    echo -e "3. Delete Hotspot Logs"
    echo -e "4. Delete Software Logs"
    echo -e "5. Delete Capture Logs"
    echo -e "6. Delete Packet Captures"
    echo -e "7. Delete Cookies"
    echo -e "8. Delete Credentials"
    echo -e "9. Delete URLs"
    echo -e "10. Back to Main Menu"
    echo -e "${GREEN}==========================================${NC}"
}

# Function to display data extraction menu
show_extraction_menu() {
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}Data Extraction Options${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "1. Extract and List Visited Websites"
    echo -e "2. Extract and List Cookies"
    echo -e "3. Extract and List Credentials"
    echo -e "4. Live Logging in New Terminal"
    echo -e "5. Back to Main Menu"
    echo -e "${GREEN}==========================================${NC}"
}

# Function to view logs in terminal with custom range options
view_logs_terminal() {
    local log_file=$1
    local log_name=$2
    
    if [ ! -f "$log_file" ]; then
        echo -e "\n${RED}Log file not found: $log_file${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}$log_name${NC}"
    echo -e "${GREEN}==========================================${NC}"
    
    # Show number of entries
    local total_lines=$(wc -l < "$log_file")
    echo -e "${YELLOW}Total entries: $total_lines${NC}"
    
    # Ask user how they want to view the logs
    echo -e "\nOptions:"
    echo -e "1. View from top (first N entries)"
    echo -e "2. View from bottom (last N entries)"
    echo -e "3. View from middle (N entries starting from position)"
    echo -e "4. Search in logs"
    echo -e "5. Back"
    
    while true; do
        read -p "Select option (1-5): " log_choice
        case $log_choice in
            1)
                read -p "Enter number of entries from top: " num_entries
                if [[ "$num_entries" =~ ^[0-9]+$ ]] && [ "$num_entries" -gt 0 ]; then
                    echo -e "\n${YELLOW}First $num_entries entries:${NC}"
                    head -n "$num_entries" "$log_file" | nl -w 4
                else
                    echo -e "${RED}Invalid number. Please enter a positive integer.${NC}"
                fi
                break
                ;;
            2)
                read -p "Enter number of entries from bottom: " num_entries
                if [[ "$num_entries" =~ ^[0-9]+$ ]] && [ "$num_entries" -gt 0 ]; then
                    echo -e "\n${YELLOW}Last $num_entries entries:${NC}"
                    tail -n "$num_entries" "$log_file" | nl -w 4
                else
                    echo -e "${RED}Invalid number. Please enter a positive integer.${NC}"
                fi
                break
                ;;
            3)
                read -p "Enter starting position: " start_pos
                read -p "Enter number of entries: " num_entries
                if [[ "$start_pos" =~ ^[0-9]+$ ]] && [[ "$num_entries" =~ ^[0-9]+$ ]] && 
                   [ "$start_pos" -gt 0 ] && [ "$num_entries" -gt 0 ]; then
                    echo -e "\n${YELLOW}$num_entries entries starting from position $start_pos:${NC}"
                    sed -n "${start_pos},$((start_pos + num_entries - 1))p" "$log_file" | nl -w 4 -v"$start_pos"
                else
                    echo -e "${RED}Invalid input. Please enter positive integers.${NC}"
                fi
                break
                ;;
            4)
                read -p "Enter search term: " search_term
                if [ -n "$search_term" ]; then
                    echo -e "\n${YELLOW}Search results for '$search_term':${NC}"
                    grep -i "$search_term" "$log_file" | nl -w 4
                else
                    echo -e "${RED}Search term cannot be empty.${NC}"
                fi
                break
                ;;
            5)
                return 0
                ;;
            *)
                echo -e "${RED}Invalid selection. Please try again.${NC}"
                ;;
        esac
    done
    
    echo -e "\n${GREEN}==========================================${NC}"
    read -p "Press Enter to continue..."
}

# Function to open log file
open_log_file() {
    local log_file=$1
    local log_name=$2
    
    if [ ! -f "$log_file" ]; then
        echo -e "\n${RED}Log file not found: $log_file${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "\n${YELLOW}Opening $log_name...${NC}"
    
    # Try different editors/file viewers
    if command -v nano >/dev/null 2>&1; then
        nano "$log_file"
    elif command -v vim >/dev/null 2>&1; then
        vim "$log_file"
    elif command -v less >/dev/null 2>&1; then
        less "$log_file"
    else
        cat "$log_file"
    fi
}

# Function to view logs
view_logs() {
    while true; do
        show_log_menu
        read -p "Select option (1-9): " log_choice
        case $log_choice in
            1)
                view_logs_terminal "logs/software.log" "Software Logs"
                ;;
            2)
                open_log_file "logs/software.log" "Software Log File"
                ;;
            3)
                view_logs_terminal "logs/hotspot.log" "Hotspot Logs"
                ;;
            4)
                open_log_file "logs/hotspot.log" "Hotspot Log File"
                ;;
            5)
                view_logs_terminal "logs/capture.log" "Packet Capture Logs"
                ;;
            6)
                view_logs_terminal "logs/cookies.txt" "Cookies Log"
                ;;
            7)
                view_logs_terminal "logs/credentials.txt" "Credentials Log"
                ;;
            8)
                view_logs_terminal "logs/urls.txt" "URLs Log"
                ;;
            9)
                return 0
                ;;
            *)
                echo -e "${RED}Invalid selection. Please try again.${NC}"
                ;;
        esac
    done
}

# Function to update software
update_software() {
    log "INFO" "Checking for software updates..."
    software_log "UPDATE_CHECK" "Checking for software updates"
    echo -e "\n${YELLOW}Checking for software updates...${NC}"
    
    # Check when software was last updated
    local last_update=$(grep "SOFTWARE_UPDATE" logs/software.log | tail -n 1 | cut -d'[' -f2 | cut -d']' -f1)
    if [ -n "$last_update" ]; then
        echo -e "${YELLOW}Last update: $last_update${NC}"
    else
        echo -e "${YELLOW}No previous update records found${NC}"
    fi
    
    # Check if we're in a git repository
    if [ -d ".git" ] && command -v git >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Checking for updates from GitHub...${NC}"
        software_log "UPDATE_CHECK" "Checking for updates from GitHub repository"
        
        # Fetch latest changes
        if git fetch; then
            # Get the current and remote commit hashes
            LOCAL=$(git rev-parse HEAD)
            REMOTE=$(git rev-parse @{u})
            
            if [ "$LOCAL" = "$REMOTE" ]; then
                echo -e "\n${GREEN}Software is up to date!${NC}"
                log "INFO" "Software is up to date"
                software_log "UPDATE_CHECK" "Software is up to date. Local: $LOCAL"
                
                # Even if up to date, verify all files exist and are correct
                echo -e "\n${YELLOW}Verifying file integrity...${NC}"
                verify_file_integrity
            else
                echo -e "\n${YELLOW}Updates available!${NC}"
                echo -e "${YELLOW}Local commit: $LOCAL${NC}"
                echo -e "${YELLOW}Remote commit: $REMOTE${NC}"
                software_log "UPDATE_CHECK" "Updates available. Local: $LOCAL, Remote: $REMOTE"
                
                # Show what changes are available
                echo -e "\n${YELLOW}Changes available:${NC}"
                git log --oneline HEAD..@{u}
                
                # Ask user if they want to update
                echo -e "\n${YELLOW}Do you want to update to the latest version? [y/N]${NC}"
                read -p "Select option: " update_choice
                
                if [[ "$update_choice" =~ ^[Yy]$ ]]; then
                    echo -e "\n${YELLOW}Updating software...${NC}"
                    software_log "SOFTWARE_UPDATE" "Starting software update process"
                    
                    # Stash any local changes
                    if ! git stash; then
                        echo -e "\n${RED}Failed to stash local changes!${NC}"
                        log "ERROR" "Failed to stash local changes"
                        software_log "UPDATE_ERROR" "Failed to stash local changes"
                        read -p "Press Enter to continue..."
                        return 1
                    fi
                    
                    # Pull the latest changes
                    if git pull; then
                        echo -e "\n${GREEN}Software updated successfully!${NC}"
                        log "INFO" "Software updated successfully"
                        software_log "SOFTWARE_UPDATE" "Software updated successfully"
                        
                        # Make sure all scripts are executable
                        chmod +x *.sh 2>/dev/null || true
                        
                        # Verify all files after update
                        echo -e "\n${YELLOW}Verifying file integrity after update...${NC}"
                        verify_file_integrity
                        
                        # Restart the script to use the updated version
                        echo -e "\n${YELLOW}Restarting script with updated version...${NC}"
                        software_log "SOFTWARE_RESTART" "Restarting script with updated version"
                        exec "$0" "$@"
                    else
                        echo -e "\n${RED}Failed to update software!${NC}"
                        log "ERROR" "Failed to update software"
                        software_log "UPDATE_ERROR" "Failed to update software"
                        
                        # Try to restore stashed changes
                        git stash pop 2>/dev/null || true
                    fi
                else
                    echo -e "\n${YELLOW}Update cancelled by user.${NC}"
                    log "INFO" "Update cancelled by user"
                    software_log "UPDATE_CANCELLED" "Update cancelled by user"
                fi
            fi
        else
            echo -e "\n${RED}Failed to fetch updates from GitHub!${NC}"
            log "ERROR" "Failed to fetch updates from GitHub"
            software_log "UPDATE_ERROR" "Failed to fetch updates from GitHub"
        fi
    else
        echo -e "\n${RED}Not a git repository or git not available!${NC}"
        log "ERROR" "Not a git repository or git not available"
        software_log "UPDATE_ERROR" "Not a git repository or git not available"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to verify file integrity and download missing files
verify_file_integrity() {
    echo -e "\n${YELLOW}Starting file integrity verification...${NC}"
    software_log "FILE_VERIFY" "Starting file integrity verification"
    
    # List of required files
    local required_files=(
        "main.sh"
        "hotspot.sh"
        "capture.sh"
        "logger.sh"
        "cookie_extractor.py"
        "setup_hotspot.sh"
        "check_dependencies.sh"
        "install_deps.sh"
        "test_wifi.sh"
        "config.ini"
        "config.conf"
        "README.md"
        "LICENSE"
        "CONTRIBUTING.md"
        "Makefile"
    )
    
    local missing_files=()
    local corrupted_files=()
    
    # Check each required file
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}Missing file: $file${NC}"
            missing_files+=("$file")
        else
            # For script files, check if they're executable
            if [[ "$file" == *.sh ]]; then
                if [ ! -x "$file" ]; then
                    echo -e "${YELLOW}Fixing permissions for: $file${NC}"
                    chmod +x "$file" 2>/dev/null || echo -e "${RED}Failed to make $file executable${NC}"
                fi
            fi
            echo -e "${GREEN}Verified: $file${NC}"
        fi
    done
    
    # Check log directories
    local required_dirs=(
        "logs"
        "pcap_logs"
        "extracted_data"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo -e "${YELLOW}Creating missing directory: $dir${NC}"
            mkdir -p "$dir" 2>/dev/null || echo -e "${RED}Failed to create directory: $dir${NC}"
        else
            echo -e "${GREEN}Verified directory: $dir${NC}"
        fi
    done
    
    # Check for log files and create if missing
    local required_log_files=(
        "logs/hotspot.log"
        "logs/software.log"
        "logs/capture.log"
        "logs/cookies.txt"
        "logs/credentials.txt"
        "logs/urls.txt"
    )
    
    for log_file in "${required_log_files[@]}"; do
        if [ ! -f "$log_file" ]; then
            echo -e "${YELLOW}Creating missing log file: $log_file${NC}"
            mkdir -p "$(dirname "$log_file")" 2>/dev/null
            touch "$log_file" 2>/dev/null || echo -e "${RED}Failed to create log file: $log_file${NC}"
        else
            echo -e "${GREEN}Verified log file: $log_file${NC}"
        fi
    done
    
    # Report results
    if [ ${#missing_files[@]} -eq 0 ] && [ ${#corrupted_files[@]} -eq 0 ]; then
        echo -e "\n${GREEN}All required files are present and verified!${NC}"
        software_log "FILE_VERIFY" "All required files are present and verified"
    else
        echo -e "\n${YELLOW}Issues found during verification:${NC}"
        if [ ${#missing_files[@]} -gt 0 ]; then
            echo -e "${RED}Missing files: ${#missing_files[@]}${NC}"
            for file in "${missing_files[@]}"; do
                echo -e "  - $file"
            done
        fi
        
        if [ ${#corrupted_files[@]} -gt 0 ]; then
            echo -e "${RED}Corrupted files: ${#corrupted_files[@]}${NC}"
            for file in "${corrupted_files[@]}"; do
                echo -e "  - $file"
            done
        fi
        
        # Ask user if they want to attempt to restore missing files
        if [ ${#missing_files[@]} -gt 0 ]; then
            echo -e "\n${YELLOW}Do you want to attempt to restore missing files from GitHub? [y/N]${NC}"
            read -p "Select option: " restore_choice
            
            if [[ "$restore_choice" =~ ^[Yy]$ ]]; then
                echo -e "\n${YELLOW}Attempting to restore missing files...${NC}"
                software_log "FILE_RESTORE" "Attempting to restore missing files"
                
                # Try to restore each missing file
                for file in "${missing_files[@]}"; do
                    echo -e "${YELLOW}Restoring: $file${NC}"
                    if git checkout HEAD -- "$file" 2>/dev/null; then
                        echo -e "${GREEN}Successfully restored: $file${NC}"
                        software_log "FILE_RESTORE" "Successfully restored: $file"
                        
                        # Make scripts executable
                        if [[ "$file" == *.sh ]]; then
                            chmod +x "$file" 2>/dev/null
                        fi
                    else
                        echo -e "${RED}Failed to restore: $file${NC}"
                        software_log "FILE_RESTORE" "Failed to restore: $file"
                    fi
                done
                
                echo -e "\n${GREEN}File restoration attempt completed!${NC}"
            fi
        fi
    fi
}

# Function to check dependencies
check_dependencies() {
    log "INFO" "Checking dependencies..."
    echo -e "\n${YELLOW}Checking for required dependencies...${NC}"
    
    # Source the check_dependencies.sh script
    if [ -f "./check_dependencies.sh" ]; then
        bash ./check_dependencies.sh
    else
        echo -e "${RED}check_dependencies.sh not found!${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to run project setup
project_setup() {
    log "INFO" "Running project setup..."
    echo -e "\n${YELLOW}Running project setup...${NC}"
    
    # Check if git is installed
    if ! command -v git >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Installing git...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y git
        elif command -v yum >/dev/null 2>&1; then
            yum install -y git
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y git
        else
            echo -e "\n${RED}Could not install git. Please install it manually.${NC}"
        fi
    fi
    
    # Check if this is already a git repository
    if [ -d ".git" ]; then
        echo -e "\n${GREEN}Project is already initialized as a git repository.${NC}"
        echo -e "${YELLOW}Checking repository status...${NC}"
        git status
    else
        echo -e "\n${YELLOW}This appears to be a standalone installation.${NC}"
        echo -e "${YELLOW}For the best experience with updates, please clone the repository from GitHub.${NC}"
        echo -e "\n${YELLOW}If you have a repository URL, you can initialize it with:${NC}"
        echo -e "${YELLOW}git init${NC}"
        echo -e "${YELLOW}git remote add origin <repository-url>${NC}"
        echo -e "${YELLOW}git pull origin main${NC}"
    fi
    
    # Run the install_deps.sh script if it exists
    if [ -f "./install_deps.sh" ]; then
        echo -e "\n${YELLOW}Installing/updating dependencies...${NC}"
        bash ./install_deps.sh
    else
        echo -e "\n${RED}install_deps.sh not found!${NC}"
    fi
    
    # Make sure all scripts are executable
    echo -e "\n${YELLOW}Setting executable permissions...${NC}"
    chmod +x *.sh 2>/dev/null || true
    
    echo -e "\n${GREEN}Project setup completed!${NC}"
    read -p "Press Enter to continue..."
}

# Function to select WiFi adapter manually
select_wifi_adapter() {
    log "INFO" "Manual WiFi adapter selection..."
    
    # List available wireless interfaces
    log "INFO" "Detecting available wireless interfaces..."
    
    # Get the list of wireless interfaces
    interfaces=($(list_wireless_interfaces))
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        log "ERROR" "No wireless interfaces found. Please ensure you have a compatible wireless adapter."
        echo -e "\n${RED}No wireless interfaces found!${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Let user select interface for hotspot
    echo -e "\n${GREEN}Available wireless interfaces:${NC}"
    for i in "${!interfaces[@]}"; do
        iface="${interfaces[$i]}"
        capabilities=()
        
        # Check AP mode support
        if iw phy "$(cat "/sys/class/net/$iface/phy80211/name" 2>/dev/null)" info 2>/dev/null | grep -q "\* AP\>"; then
            capabilities+=("AP")
        fi
        
        # Check monitor mode support
        if iw phy "$(cat "/sys/class/net/$iface/phy80211/name" 2>/dev/null)" info 2>/dev/null | grep -q "\* monitor"; then
            capabilities+=("Monitor")
        fi
        
        # Display interface with capabilities
        if [ ${#capabilities[@]} -gt 0 ]; then
            echo "$((i+1)). $iface (${capabilities[*]})"
        else
            echo "$((i+1)). $iface"
        fi
    done
    
    # Show menu for multiple interfaces
    while true; do
        read -p "Select interface (1-${#interfaces[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#interfaces[@]} ]; then
            WIFI_IFACE="${interfaces[$((choice-1))]}"
            log "INFO" "Selected interface: $WIFI_IFACE"
            echo -e "\n${GREEN}Selected interface: $WIFI_IFACE${NC}"
            break
        else
            echo -e "${RED}Invalid selection. Please try again.${NC}"
        fi
    done
    
    return 0
}

# Function to auto-select WiFi adapter
auto_select_wifi_adapter() {
    log "INFO" "Auto-selecting WiFi adapter..."
    
    # Get the list of wireless interfaces
    interfaces=($(list_wireless_interfaces))
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        log "ERROR" "No wireless interfaces found. Please ensure you have a compatible wireless adapter."
        echo -e "\n${RED}No wireless interfaces found!${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Auto-select the first interface that supports AP mode
    WIFI_IFACE=""
    for iface in "${interfaces[@]}"; do
        if iw phy "$(cat "/sys/class/net/$iface/phy80211/name" 2>/dev/null)" info 2>/dev/null | grep -q "\* AP\>"; then
            WIFI_IFACE="$iface"
            break
        fi
    done
    
    if [ -z "$WIFI_IFACE" ]; then
        log "ERROR" "No interface with AP mode support found. Cannot create hotspot."
        echo -e "\n${RED}No interface with AP mode support found!${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    log "INFO" "Auto-selected interface: $WIFI_IFACE"
    echo -e "\n${GREEN}Auto-selected interface: $WIFI_IFACE${NC}"
    return 0
}

# Function to ask for terminal options
ask_terminal_options() {
    show_terminal_options
    while true; do
        read -p "Select option (1-3): " term_choice
        case $term_choice in
            1)
                OPEN_TERMINALS=true
                RUN_BACKGROUND=false
                echo -e "\n${GREEN}Will open separate terminals for each component${NC}"
                return 0
                ;;
            2)
                OPEN_TERMINALS=false
                RUN_BACKGROUND=false
                echo -e "\n${GREEN}Will run everything in current terminal${NC}"
                return 0
                ;;
            3)
                OPEN_TERMINALS=false
                RUN_BACKGROUND=true
                echo -e "\n${GREEN}Will run in background with logging only${NC}"
                return 0
                ;;
            *)
                echo -e "${RED}Invalid selection. Please try again.${NC}"
                ;;
        esac
    done
}

# Function to start hotspot with selected options
start_hotspot() {
    local wifi_iface=$1
    
    if [ -z "$wifi_iface" ]; then
        log "ERROR" "No WiFi interface specified"
        echo -e "\n${RED}No WiFi interface specified!${NC}"
        return 1
    fi
    
    # Auto-detect internet source
    INTERNET_IFACE=$(detect_internet)
    echo -e "\nDetected internet source: $INTERNET_IFACE"
    
    # Check if we're using the same interface for internet and hotspot
    if [ "$wifi_iface" = "$INTERNET_IFACE" ]; then
        echo -e "\n${YELLOW}Warning: You've selected the same interface for both internet and hotspot.${NC}"
        echo -e "${YELLOW}This will disconnect your internet connection.${NC}"
        read -p "Do you want to continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Operation cancelled by user"
            return 0
        fi
    fi
    
    # Ask for terminal options
    ask_terminal_options
    
    if [ "$OPEN_TERMINALS" = true ]; then
        # Open separate terminals for each component
        start_hotspot_with_separate_terminals "$wifi_iface"
    elif [ "$RUN_BACKGROUND" = true ]; then
        # Run in background with logging only
        start_hotspot_background "$wifi_iface"
    else
        # Run everything in current terminal
        start_hotspot_current_terminal "$wifi_iface"
    fi
}

# Function to start hotspot with separate terminals
start_hotspot_with_separate_terminals() {
    local wifi_iface=$1
    
    echo -e "\n${YELLOW}Opening separate terminals for each component...${NC}"
    
    # Start hotspot in a new terminal
    echo -e "\n${GREEN}Starting hotspot on $wifi_iface...${NC}"
    gnome-terminal --title="Hotspot - $wifi_iface" -- bash -c "bash hotspot.sh '$wifi_iface'; exec bash" 2>/dev/null || \
    xterm -title "Hotspot - $wifi_iface" -e "bash hotspot.sh '$wifi_iface'" 2>/dev/null || \
    echo -e "${RED}Could not open terminal for hotspot. Please install gnome-terminal or xterm.${NC}"
    
    # Wait a moment for hotspot to start
    sleep 5
    
    # Start packet capture in a new terminal
    echo -e "\n${GREEN}Starting packet capture on $wifi_iface...${NC}"
    gnome-terminal --title="Packet Capture - $wifi_iface" -- bash -c "bash capture.sh '$wifi_iface'; exec bash" 2>/dev/null || \
    xterm -title "Packet Capture - $wifi_iface" -e "bash capture.sh '$wifi_iface'" 2>/dev/null || \
    echo -e "${RED}Could not open terminal for packet capture. Please install gnome-terminal or xterm.${NC}"
    
    # Start log monitoring in a new terminal
    echo -e "\n${GREEN}Starting log monitoring...${NC}"
    gnome-terminal --title="Logs Monitor" -- bash -c "tail -f logs/hotspot.log; exec bash" 2>/dev/null || \
    xterm -title "Logs Monitor" -e "tail -f logs/hotspot.log" 2>/dev/null || \
    echo -e "${RED}Could not open terminal for log monitoring. Please install gnome-terminal or xterm.${NC}"
    
    # Start cookie monitoring in a new terminal
    echo -e "\n${GREEN}Starting cookie monitoring...${NC}"
    gnome-terminal --title="Cookies Monitor" -- bash -c "tail -f logs/cookies.txt; exec bash" 2>/dev/null || \
    xterm -title "Cookies Monitor" -e "tail -f logs/cookies.txt" 2>/dev/null || \
    echo -e "${RED}Could not open terminal for cookie monitoring. Please install gnome-terminal or xterm.${NC}"
    
    # Start visited URLs monitoring in a new terminal
    echo -e "\n${GREEN}Starting visited URLs monitoring...${NC}"
    gnome-terminal --title="Visited URLs Monitor" -- bash -c "tail -f logs/urls.txt; exec bash" 2>/dev/null || \
    xterm -title "Visited URLs Monitor" -e "tail -f logs/urls.txt" 2>/dev/null || \
    echo -e "${RED}Could not open terminal for URL monitoring. Please install gnome-terminal or xterm.${NC}"
    
    echo -e "\n${GREEN}All components started in separate terminals!${NC}"
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to start hotspot in background
start_hotspot_background() {
    local wifi_iface=$1
    
    echo -e "\n${GREEN}Starting hotspot in background...${NC}"
    
    # Start hotspot in the background
    log "INFO" "Starting hotspot on $wifi_iface"
    mkdir -p logs
    bash hotspot.sh "$wifi_iface" > logs/hotspot.log 2>&1 &
    HOTSPOT_PID=$!
    
    # Give the hotspot a moment to start
    log "INFO" "Waiting for hotspot to initialize..."
    sleep 10
    
    # Verify hotspot is running
    if ! ps -p $HOTSPOT_PID > /dev/null; then
        log "ERROR" "Failed to start hotspot. Check logs/hotspot.log for details."
        echo -e "\n${RED}Failed to start hotspot. Check logs/hotspot.log for details.${NC}"
        return 1
    fi
    
    # Extract hotspot credentials from config or use defaults
    CONFIG_FILE="config.ini"
    
    # Default values
    SSID="SecureHotspot_$(hostname | cut -d'.' -f1)"
    PASSWORD="SecurePass123"
    
    # Load configuration if config.ini exists
    if [ -f "$CONFIG_FILE" ]; then
        # Load hotspot configuration
        if grep -q "\[HOTSPOT\]" "$CONFIG_FILE"; then
            # Extract values, ignoring comments and whitespace
            SSID_PREFIX=$(grep -A 10 "\[HOTSPOT\]" "$CONFIG_FILE" | grep "^SSID_PREFIX=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -d'#' -f1 | tr -d ' ')
            if [ -n "$SSID_PREFIX" ]; then
                SSID="${SSID_PREFIX}$(hostname | cut -d'.' -f1)"
            fi
            
            NEW_WPA_PASSPHRASE=$(grep -A 10 "\[HOTSPOT\]" "$CONFIG_FILE" | grep "^WPA_PASSPHRASE=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -d'#' -f1 | tr -d ' ')
            if [ -n "$NEW_WPA_PASSPHRASE" ]; then
                PASSWORD="$NEW_WPA_PASSPHRASE"
            fi
        fi
    fi
    
    # Display hotspot information to user
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "${GREEN}WiFi Hotspot is now running!${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "SSID:     ${YELLOW}$SSID${NC}"
    echo -e "Password: ${YELLOW}$PASSWORD${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "Connect your devices to the hotspot now."
    echo -e "Logs are being saved to logs/hotspot.log"
    
    # Start packet capture in the background
    log "INFO" "Starting packet capture on $wifi_iface"
    mkdir -p pcap_logs
    bash capture.sh "$wifi_iface" > logs/capture.log 2>&1 &
    CAPTURE_PID=$!
    
    # Verify capture is running
    sleep 2
    if ! ps -p $CAPTURE_PID > /dev/null; then
        log "ERROR" "Failed to start packet capture. Check logs/capture.log for details."
        echo -e "\n${RED}Failed to start packet capture. Check logs/capture.log for details.${NC}"
        kill $HOTSPOT_PID 2>/dev/null
        return 1
    fi
    
    echo -e "\n${GREEN}Hotspot is running in background. Check logs for details.${NC}"
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to start hotspot in current terminal
start_hotspot_current_terminal() {
    local wifi_iface=$1
    
    echo -e "\n${GREEN}Starting hotspot in current terminal...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop and return to main menu.${NC}"
    
    # Set up trap to catch termination signals and return to menu
    trap 'echo -e "\n${YELLOW}Returning to main menu...${NC}"; return 0' INT
    
    # Start hotspot in foreground
    bash hotspot.sh "$wifi_iface"
}

# Function to extract and list visited websites
extract_websites() {
    local pcap_file="pcap_logs/capture.pcap"
    
    if [ ! -f "$pcap_file" ]; then
        echo -e "\n${RED}Packet capture file not found: $pcap_file${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "\n${YELLOW}Extracting visited websites from packet capture...${NC}"
    
    # Ask user if they want to save to file
    read -p "Do you want to save extracted websites to a file? [y/N]: " save_choice
    local save_to_file=false
    local output_file=""
    
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        save_to_file=true
        mkdir -p "extracted_data"
        output_file="extracted_data/visited_websites_$(date +%Y%m%d_%H%M%S).txt"
        echo -e "\n${YELLOW}Websites will be saved to: $output_file${NC}"
    fi
    
    # Extract URLs using tshark if available, otherwise use basic method
    if command -v tshark >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Extracting with tshark...${NC}"
        if [ "$save_to_file" = true ]; then
            tshark -r "$pcap_file" -Y "http.request" -T fields -e http.host -e http.request.uri 2>/dev/null | \
            while read host uri; do
                if [ -n "$host" ]; then
                    echo "http://$host$uri"
                fi
            done | sort -u > "$output_file"
            
            echo -e "\n${GREEN}Visited websites saved to $output_file${NC}"
            echo -e "\n${YELLOW}First 10 websites:${NC}"
            head -n 10 "$output_file" | nl -w 4
        else
            tshark -r "$pcap_file" -Y "http.request" -T fields -e http.host -e http.request.uri 2>/dev/null | \
            while read host uri; do
                if [ -n "$host" ]; then
                    echo "http://$host$uri"
                fi
            done | sort -u | head -n 20 | nl -w 4
        fi
    else
        # Fallback method using tcpdump and grep
        echo -e "\n${YELLOW}Extracting with grep (tshark not available)...${NC}"
        if [ "$save_to_file" = true ]; then
            strings "$pcap_file" | grep -E "GET|POST|Host:" | grep -oE "Host: [^ ]+" | cut -d' ' -f2 | \
            sort -u > "$output_file"
            
            echo -e "\n${GREEN}Visited websites saved to $output_file${NC}"
            echo -e "\n${YELLOW}First 10 websites:${NC}"
            head -n 10 "$output_file" | nl -w 4
        else
            strings "$pcap_file" | grep -E "GET|POST|Host:" | grep -oE "Host: [^ ]+" | cut -d' ' -f2 | \
            sort -u | head -n 20 | nl -w 4
        fi
    fi
    
    echo -e "\n${GREEN}==========================================${NC}"
    read -p "Press Enter to continue..."
}

# Function to extract and list cookies with simplified JSON view
extract_cookies() {
    local cookies_file="logs/cookies.txt"
    
    if [ ! -f "$cookies_file" ] || [ ! -s "$cookies_file" ]; then
        echo -e "\n${RED}Cookies file not found or is empty: $cookies_file${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "\n${YELLOW}Extracting cookies...${NC}"
    
    # Ask user if they want to save to file
    read -p "Do you want to save extracted cookies to a JSON file? [y/N]: " save_choice
    local save_to_file=false
    local output_file=""
    
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        save_to_file=true
        mkdir -p "extracted_data"
        output_file="extracted_data/cookies_$(date +%Y%m%d_%H%M%S).json"
        echo -e "\n${YELLOW}Cookies will be saved to: $output_file${NC}"
    fi
    
    # Process cookies and convert to simplified JSON format
    local count=0
    local json_content="{\n  \"cookies\": [\n"
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            # Generate unique ID
            local id=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 8 | head -n 1)
            
            # Extract domain from cookie (simplified approach)
            local domain="unknown"
            if [[ $line =~ ([^=]+)=([^;]*) ]]; then
                domain="extracted"
            fi
            
            # Create simplified JSON entry
            local json_entry="    {\n      \"id\": \"$id\",\n      \"domain\": \"$domain\",\n      \"content\": \"$line\"\n    }"
            
            if [ $count -gt 0 ]; then
                json_content="$json_content,\n$json_entry"
            else
                json_content="$json_content$json_entry"
            fi
            
            count=$((count + 1))
        fi
    done < "$cookies_file"
    
    json_content="$json_content\n  ]\n}"
    
    if [ "$save_to_file" = true ]; then
        echo -e "$json_content" > "$output_file"
        echo -e "\n${GREEN}Cookies saved to $output_file${NC}"
        echo -e "\n${YELLOW}First 5 cookies:${NC}"
        head -n 15 "$output_file" | sed 's/^/    /'
    else
        echo -e "\n${YELLOW}First 5 cookies (simplified JSON view):${NC}"
        echo -e "$json_content" | head -n 20 | sed 's/^/    /'
    fi
    
    echo -e "\n${GREEN}Total cookies extracted: $count${NC}"
    echo -e "\n${GREEN}==========================================${NC}"
    read -p "Press Enter to continue..."
}

# Function to extract and list credentials with simplified view
extract_credentials() {
    local credentials_file="logs/credentials.txt"
    
    if [ ! -f "$credentials_file" ] || [ ! -s "$credentials_file" ]; then
        echo -e "\n${RED}Credentials file not found or is empty: $credentials_file${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "\n${YELLOW}Extracting credentials...${NC}"
    
    # Ask user if they want to save to file
    read -p "Do you want to save extracted credentials to a file? [y/N]: " save_choice
    local save_to_file=false
    local output_file=""
    
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        save_to_file=true
        mkdir -p "extracted_data"
        output_file="extracted_data/credentials_$(date +%Y%m%d_%H%M%S).txt"
        echo -e "\n${YELLOW}Credentials will be saved to: $output_file${NC}"
    fi
    
    # Process credentials and create simplified view
    local count=0
    
    if [ "$save_to_file" = true ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                # Generate unique ID
                local id=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 8 | head -n 1)
                
                # Write to file with ID
                echo "ID: $id | Data: $line" >> "$output_file"
                count=$((count + 1))
            fi
        done < "$credentials_file"
        
        echo -e "\n${GREEN}Credentials saved to $output_file${NC}"
        echo -e "\n${YELLOW}First 5 credentials:${NC}"
        head -n 5 "$output_file" | nl -w 4
    else
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                # Generate unique ID
                local id=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 8 | head -n 1)
                
                # Display with ID
                echo "$((count + 1)). ID: $id | Data: $line"
                count=$((count + 1))
                
                # Limit display to first 10 credentials
                if [ $count -ge 10 ]; then
                    break
                fi
            fi
        done < "$credentials_file"
    fi
    
    echo -e "\n${GREEN}Total credentials extracted: $count${NC}"
    echo -e "\n${GREEN}==========================================${NC}"
    read -p "Press Enter to continue..."
}

# Function to open live logging in new terminal
open_live_logging() {
    echo -e "\n${YELLOW}Opening live logging in new terminal...${NC}"
    
    # Try different terminal emulators
    if command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --title="Live Logging" -- bash -c "echo 'Live Hotspot Logs:'; tail -f logs/hotspot.log; exec bash" 2>/dev/null || \
        gnome-terminal -e "bash -c \"echo 'Live Hotspot Logs:'; tail -f logs/hotspot.log; exec bash\"" 2>/dev/null
    elif command -v xterm >/dev/null 2>&1; then
        xterm -title "Live Logging" -e bash -c "echo 'Live Hotspot Logs:'; tail -f logs/hotspot.log; exec bash" 2>/dev/null
    elif command -v konsole >/dev/null 2>&1; then
        konsole --title "Live Logging" -e bash -c "echo 'Live Hotspot Logs:'; tail -f logs/hotspot.log; exec bash" 2>/dev/null
    else
        echo -e "\n${RED}No supported terminal emulator found!${NC}"
        echo -e "${YELLOW}Supported terminals: gnome-terminal, xterm, konsole${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "\n${GREEN}Live logging terminal opened successfully!${NC}"
    echo -e "${YELLOW}Check the new terminal window for live logs.${NC}"
    read -p "Press Enter to continue..."
}

# Function to delete all data
delete_all_data() {
    echo -e "\n${RED}WARNING: This will permanently delete all data!${NC}"
    echo -e "${YELLOW}This includes:${NC}"
    echo -e "${YELLOW}- All log files${NC}"
    echo -e "${YELLOW}- All packet capture files${NC}"
    echo -e "${YELLOW}- All extracted cookies${NC}"
    echo -e "${YELLOW}- All extracted credentials${NC}"
    echo -e "${YELLOW}- All extracted URLs${NC}"
    
    read -p "Are you sure you want to delete all data? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "DATA_DELETE" "Deleting all data initiated by user"
        
        # Delete logs directory
        if [ -d "logs" ]; then
            echo -e "\n${YELLOW}Deleting logs directory...${NC}"
            rm -rf logs/*
            echo -e "${GREEN}Logs directory cleared${NC}"
            software_log "DATA_DELETE" "Logs directory cleared"
        fi
        
        # Delete pcap_logs directory
        if [ -d "pcap_logs" ]; then
            echo -e "\n${YELLOW}Deleting packet capture directory...${NC}"
            rm -rf pcap_logs/*
            echo -e "${GREEN}Packet capture directory cleared${NC}"
            software_log "DATA_DELETE" "Packet capture directory cleared"
        fi
        
        # Recreate essential log files
        mkdir -p logs pcap_logs 2>/dev/null
        touch logs/hotspot.log logs/software.log
        echo "# Software Log - WiFi Hotspot and Activity Logger" > logs/software.log
        echo "# Format: [TIMESTAMP] [LOG_ID] [LEVEL] [ACTION] [DETAILS]" >> logs/software.log
        
        echo -e "\n${GREEN}All data has been deleted successfully!${NC}"
        software_log "DATA_DELETE" "All data deletion completed successfully"
    else
        echo -e "\n${YELLOW}Data deletion cancelled${NC}"
        software_log "DATA_DELETE" "Data deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete all logs
delete_all_logs() {
    echo -e "\n${RED}WARNING: This will permanently delete all log files!${NC}"
    echo -e "${YELLOW}This includes:${NC}"
    echo -e "${YELLOW}- Hotspot logs${NC}"
    echo -e "${YELLOW}- Software logs${NC}"
    echo -e "${YELLOW}- Capture logs${NC}"
    
    read -p "Are you sure you want to delete all logs? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "LOG_DELETE" "Deleting all logs initiated by user"
        
        # Delete all log files
        if [ -d "logs" ]; then
            echo -e "\n${YELLOW}Deleting all log files...${NC}"
            rm -f logs/*.log logs/*.txt
            echo -e "${GREEN}All log files deleted${NC}"
            software_log "LOG_DELETE" "All log files deleted"
        fi
        
        # Recreate essential log files
        touch logs/hotspot.log logs/software.log 2>/dev/null
        echo "# Software Log - WiFi Hotspot and Activity Logger" > logs/software.log
        echo "# Format: [TIMESTAMP] [LOG_ID] [LEVEL] [ACTION] [DETAILS]" >> logs/software.log
        
        echo -e "\n${GREEN}All logs have been deleted successfully!${NC}"
        software_log "LOG_DELETE" "All logs deletion completed successfully"
    else
        echo -e "\n${YELLOW}Log deletion cancelled${NC}"
        software_log "LOG_DELETE" "Log deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete hotspot logs
delete_hotspot_logs() {
    echo -e "\n${RED}WARNING: This will permanently delete hotspot logs!${NC}"
    
    read -p "Are you sure you want to delete hotspot logs? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "LOG_DELETE" "Deleting hotspot logs initiated by user"
        
        # Delete hotspot log file
        if [ -f "logs/hotspot.log" ]; then
            echo -e "\n${YELLOW}Deleting hotspot log file...${NC}"
            rm -f logs/hotspot.log
            echo -e "${GREEN}Hotspot log file deleted${NC}"
            software_log "LOG_DELETE" "Hotspot log file deleted"
        fi
        
        # Recreate hotspot log file
        touch logs/hotspot.log 2>/dev/null
        echo -e "\n${GREEN}Hotspot logs have been deleted successfully!${NC}"
        software_log "LOG_DELETE" "Hotspot logs deletion completed successfully"
    else
        echo -e "\n${YELLOW}Hotspot log deletion cancelled${NC}"
        software_log "LOG_DELETE" "Hotspot log deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete software logs
delete_software_logs() {
    echo -e "\n${RED}WARNING: This will permanently delete software logs!${NC}"
    
    read -p "Are you sure you want to delete software logs? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "LOG_DELETE" "Deleting software logs initiated by user"
        
        # Delete software log file
        if [ -f "logs/software.log" ]; then
            echo -e "\n${YELLOW}Deleting software log file...${NC}"
            rm -f logs/software.log
            echo -e "${GREEN}Software log file deleted${NC}"
            software_log "LOG_DELETE" "Software log file deleted"
        fi
        
        # Recreate software log file
        touch logs/software.log 2>/dev/null
        echo "# Software Log - WiFi Hotspot and Activity Logger" > logs/software.log
        echo "# Format: [TIMESTAMP] [LOG_ID] [LEVEL] [ACTION] [DETAILS]" >> logs/software.log
        
        echo -e "\n${GREEN}Software logs have been deleted successfully!${NC}"
        software_log "LOG_DELETE" "Software logs deletion completed successfully"
    else
        echo -e "\n${YELLOW}Software log deletion cancelled${NC}"
        software_log "LOG_DELETE" "Software log deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete capture logs
delete_capture_logs() {
    echo -e "\n${RED}WARNING: This will permanently delete capture logs!${NC}"
    
    read -p "Are you sure you want to delete capture logs? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "LOG_DELETE" "Deleting capture logs initiated by user"
        
        # Delete capture log file
        if [ -f "logs/capture.log" ]; then
            echo -e "\n${YELLOW}Deleting capture log file...${NC}"
            rm -f logs/capture.log
            echo -e "${GREEN}Capture log file deleted${NC}"
            software_log "LOG_DELETE" "Capture log file deleted"
        fi
        
        # Recreate capture log file
        touch logs/capture.log 2>/dev/null
        echo -e "\n${GREEN}Capture logs have been deleted successfully!${NC}"
        software_log "LOG_DELETE" "Capture logs deletion completed successfully"
    else
        echo -e "\n${YELLOW}Capture log deletion cancelled${NC}"
        software_log "LOG_DELETE" "Capture log deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete packet captures
delete_packet_captures() {
    echo -e "\n${RED}WARNING: This will permanently delete all packet capture files!${NC}"
    
    read -p "Are you sure you want to delete packet captures? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "DATA_DELETE" "Deleting packet captures initiated by user"
        
        # Delete pcap_logs directory contents
        if [ -d "pcap_logs" ]; then
            echo -e "\n${YELLOW}Deleting packet capture files...${NC}"
            rm -rf pcap_logs/*
            echo -e "${GREEN}Packet capture files deleted${NC}"
            software_log "DATA_DELETE" "Packet capture files deleted"
        fi
        
        echo -e "\n${GREEN}Packet captures have been deleted successfully!${NC}"
        software_log "DATA_DELETE" "Packet captures deletion completed successfully"
    else
        echo -e "\n${YELLOW}Packet capture deletion cancelled${NC}"
        software_log "DATA_DELETE" "Packet capture deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete cookies
delete_cookies() {
    echo -e "\n${RED}WARNING: This will permanently delete all cookie files!${NC}"
    
    read -p "Are you sure you want to delete cookies? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "DATA_DELETE" "Deleting cookies initiated by user"
        
        # Delete cookies file
        if [ -f "logs/cookies.txt" ]; then
            echo -e "\n${YELLOW}Deleting cookies file...${NC}"
            rm -f logs/cookies.txt
            echo -e "${GREEN}Cookies file deleted${NC}"
            software_log "DATA_DELETE" "Cookies file deleted"
        fi
        
        # Recreate cookies file
        touch logs/cookies.txt 2>/dev/null
        echo -e "\n${GREEN}Cookies have been deleted successfully!${NC}"
        software_log "DATA_DELETE" "Cookies deletion completed successfully"
    else
        echo -e "\n${YELLOW}Cookie deletion cancelled${NC}"
        software_log "DATA_DELETE" "Cookie deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete credentials
delete_credentials() {
    echo -e "\n${RED}WARNING: This will permanently delete all credential files!${NC}"
    
    read -p "Are you sure you want to delete credentials? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "DATA_DELETE" "Deleting credentials initiated by user"
        
        # Delete credentials file
        if [ -f "logs/credentials.txt" ]; then
            echo -e "\n${YELLOW}Deleting credentials file...${NC}"
            rm -f logs/credentials.txt
            echo -e "${GREEN}Credentials file deleted${NC}"
            software_log "DATA_DELETE" "Credentials file deleted"
        fi
        
        # Recreate credentials file
        touch logs/credentials.txt 2>/dev/null
        echo -e "\n${GREEN}Credentials have been deleted successfully!${NC}"
        software_log "DATA_DELETE" "Credentials deletion completed successfully"
    else
        echo -e "\n${YELLOW}Credential deletion cancelled${NC}"
        software_log "DATA_DELETE" "Credential deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete URLs
delete_urls() {
    echo -e "\n${RED}WARNING: This will permanently delete all URL files!${NC}"
    
    read -p "Are you sure you want to delete URLs? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        software_log "DATA_DELETE" "Deleting URLs initiated by user"
        
        # Delete URLs file
        if [ -f "logs/urls.txt" ]; then
            echo -e "\n${YELLOW}Deleting URLs file...${NC}"
            rm -f logs/urls.txt
            echo -e "${GREEN}URLs file deleted${NC}"
            software_log "DATA_DELETE" "URLs file deleted"
        fi
        
        # Recreate URLs file
        touch logs/urls.txt 2>/dev/null
        echo -e "\n${GREEN}URLs have been deleted successfully!${NC}"
        software_log "DATA_DELETE" "URLs deletion completed successfully"
    else
        echo -e "\n${YELLOW}URL deletion cancelled${NC}"
        software_log "DATA_DELETE" "URL deletion cancelled by user"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to delete data
delete_data() {
    while true; do
        show_delete_menu
        read -p "Select option (1-10): " delete_choice
        case $delete_choice in
            1)
                delete_all_data
                ;;
            2)
                delete_all_logs
                ;;
            3)
                delete_hotspot_logs
                ;;
            4)
                delete_software_logs
                ;;
            5)
                delete_capture_logs
                ;;
            6)
                delete_packet_captures
                ;;
            7)
                delete_cookies
                ;;
            8)
                delete_credentials
                ;;
            9)
                delete_urls
                ;;
            10)
                return 0
                ;;
            *)
                echo -e "${RED}Invalid selection. Please try again.${NC}"
                ;;
        esac
    done
}

# Function to handle data extraction
extract_data() {
    while true; do
        show_extraction_menu
        read -p "Select option (1-5): " extract_choice
        case $extract_choice in
            1)
                extract_websites
                ;;
            2)
                extract_cookies
                ;;
            3)
                extract_credentials
                ;;
            4)
                open_live_logging
                ;;
            5)
                return 0
                ;;
            *)
                echo -e "${RED}Invalid selection. Please try again.${NC}"
                ;;
        esac
    done
}

# Main menu function
main_menu() {
    # Log software execution
    software_log "SOFTWARE_START" "WiFi Hotspot and Activity Logger started"
    
    while true; do
        show_main_menu
        read -p "Select option (1-9): " choice
        case $choice in
            1)
                select_wifi_adapter
                if [ $? -eq 0 ]; then
                    start_hotspot "$WIFI_IFACE"
                fi
                ;;
            2)
                auto_select_wifi_adapter
                if [ $? -eq 0 ]; then
                    start_hotspot "$WIFI_IFACE"
                fi
                ;;
            3)
                update_software
                ;;
            4)
                check_dependencies
                ;;
            5)
                project_setup
                ;;
            6)
                view_logs
                ;;
            7)
                delete_data
                ;;
            8)
                extract_data
                ;;
            9)
                software_log "SOFTWARE_EXIT" "WiFi Hotspot and Activity Logger exited"
                echo -e "\n${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid selection. Please try again.${NC}"
                ;;
        esac
    done
}

# Main execution
main() {
    log "INFO" "Starting WiFi Hotspot and Activity Logger"
    
    # Check for required tools
    if ! check_wireless_tools; then
        log "ERROR" "Failed to install required wireless tools"
        exit 1
    fi
    
    # Run main menu
    main_menu
}

# Execute main function
main "$@"

exit 0

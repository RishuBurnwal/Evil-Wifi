#!/bin/bash

# Exit on error
set -e

# Import logger
source logger.sh

INTERFACE=$1

if [ -z "$INTERFACE" ]; then
    log "ERROR" "No interface specified for packet capture"
    exit 1
fi

# Verify interface exists
if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    log "ERROR" "Interface $INTERFACE not found"
    exit 1
fi

# Create necessary directories
mkdir -p pcap_logs logs

# Check if tcpdump is installed
if ! command -v tcpdump >/dev/null 2>&1; then
    log "ERROR" "tcpdump is not installed. Please install it with: sudo apt install tcpdump"
    exit 1
fi

# Clean up old capture file if it exists
rm -f "pcap_logs/capture.pcap"

# Start tcpdump with more detailed logging
log "INFO" "Starting packet capture on $INTERFACE..."
log "DEBUG" "Running command: tcpdump -i $INTERFACE -w pcap_logs/capture.pcap -U"

tcpdump -i "$INTERFACE" -w "pcap_logs/capture.pcap" -U 2>>"logs/capture_errors.log" &
CAPTURE_PID=$!

# Save PID to file for later reference
echo $CAPTURE_PID > "/tmp/wifi_capture_$INTERFACE.pid"

# Verify tcpdump started
sleep 2
if ! ps -p $CAPTURE_PID > /dev/null; then
    log "ERROR" "Failed to start tcpdump. Check logs/capture_errors.log for details."
    exit 1
fi

log "INFO" "Packet capture started with PID: $CAPTURE_PID"
log "INFO" "Capture file: pcap_logs/capture.pcap"

# Keep script running while tcpdump is running
wait $CAPTURE_PID || true

log "INFO" "Packet capture stopped"


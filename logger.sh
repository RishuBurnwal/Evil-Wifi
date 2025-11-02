#!/bin/bash

# Simple logger implementation
LOG_LEVEL="INFO"
LOG_DIR="logs"
HOTSPOT_LOG_FILE="$LOG_DIR/hotspot.log"
SOFTWARE_LOG_FILE="$LOG_DIR/software.log"

# Ensure log directory exists and is writable
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" || {
        echo "Failed to create log directory: $LOG_DIR" >&2
        exit 1
    }
    chmod 777 "$LOG_DIR" 2>/dev/null
fi

# Ensure log files exist and are writable
if [ ! -f "$HOTSPOT_LOG_FILE" ]; then
    touch "$HOTSPOT_LOG_FILE" 2>/dev/null || {
        echo "Failed to create log file: $HOTSPOT_LOG_FILE" >&2
        exit 1
    }
    chmod 666 "$HOTSPOT_LOG_FILE" 2>/dev/null
fi

if [ ! -f "$SOFTWARE_LOG_FILE" ]; then
    touch "$SOFTWARE_LOG_FILE" 2>/dev/null || {
        echo "Failed to create software log file: $SOFTWARE_LOG_FILE" >&2
        exit 1
    }
    chmod 666 "$SOFTWARE_LOG_FILE" 2>/dev/null
fi

# Generate 8-digit alphanumeric log ID
generate_log_id() {
    cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 8 | head -n 1
}

# Simple log function for hotspot activities
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Try to log to file, if that fails, log to stderr
    if [ -w "$HOTSPOT_LOG_FILE" ]; then
        echo "[$timestamp] [$level] $message" | tee -a "$HOTSPOT_LOG_FILE" >/dev/null
    else
        echo "[$timestamp] [$level] $message" >&2
    fi
}

# Software log function with ID tracking
software_log() {
    local action=$1
    local details=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_id=$(generate_log_id)
    
    # Try to log to software log file
    if [ -w "$SOFTWARE_LOG_FILE" ]; then
        echo "[$timestamp] [$log_id] [INFO] [$action] $details" | tee -a "$SOFTWARE_LOG_FILE" >/dev/null
    else
        echo "[$timestamp] [$log_id] [INFO] [$action] $details" >&2
    fi
}

# Clean up old logs
cleanup_logs() {
    local max_size_mb=10
    local max_logs=5
    
    if [ -f "$LOG_FILE" ]; then
        local size_mb=$(du -m "$LOG_FILE" 2>/dev/null | cut -f1)
        if [ "$size_mb" -gt $max_size_mb ] 2>/dev/null; then
            # Rotate logs
            for i in $(seq $((max_logs-1)) -1 1); do
                [ -f "${LOG_FILE}.$i" ] && mv -f "${LOG_FILE}.$i" "${LOG_FILE}.$((i+1))"
            done
            mv -f "$LOG_FILE" "${LOG_FILE}.1"
        fi
    fi
}

# Initialize logging
cleanup_logs

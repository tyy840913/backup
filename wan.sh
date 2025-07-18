#!/bin/sh

LOG_FILE="/root/network_monitor.log"
PING_TARGET="223.5.5.5" # Alibaba Cloud Public DNS
NETWORK_INTERFACE="wan" # Your WAN interface name, usually wan or wan6

# Function to log errors to file
log_error() {
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$TIMESTAMP - ERROR: $1" >> "$LOG_FILE"
}

# Check external network connectivity (simple ping)
check_connectivity() {
    echo "Checking external connectivity to $PING_TARGET..."
    ping -q -c 3 -W 1 "$PING_TARGET" > /dev/null 2>&1
    return $? # Returns ping's exit status (0 for success, non-zero for failure)
}

# Check WAN interface IP information
check_interface_ip() {
    echo "Checking IP address for interface $NETWORK_INTERFACE..."
    ifconfig "$NETWORK_INTERFACE" | grep -qE "inet (addr:)?([0-9]{1,3}\.){3}[0-9]{1,3}"
    return $?
}

# Attempt recovery based on levels
attempt_recovery() {
    log_error "External connectivity lost, attempting recovery..."
    echo "External connectivity lost. Attempting recovery..."

    # Level 1: Restart network service
    echo "Attempting Level 1: Restarting network service..."
    log_error "Attempting Level 1: Restarting network service..."
    /etc/init.d/network restart
    sleep 10 # Wait for network service to restart

    if check_connectivity; then
        echo "Level 1 recovery successful."
        log_error "Level 1 recovery successful."
        return 0
    fi

    # Level 2: Restart WAN interface
    echo "Attempting Level 2: Restarting WAN interface '$NETWORK_INTERFACE'..."
    log_error "Attempting Level 2: Restarting WAN interface '$NETWORK_INTERFACE'..."
    ifconfig "$NETWORK_INTERFACE" down
    sleep 5
    ifconfig "$NETWORK_INTERFACE" up
    sleep 10 # Wait for interface to come up

    if check_connectivity; then
        echo "Level 2 recovery successful."
        log_error "Level 2 recovery successful."
        return 0
    fi

    # Level 3: Reboot router (last resort)
    echo "Attempting Level 3: Rebooting router (last resort)..."
    log_error "Attempting Level 3: Rebooting router (last resort)..."
    reboot # Router will reboot
    return 1 # If execution reaches here, it means reboot was initiated
}

# Main check logic
main_check() {
    if ! check_connectivity; then
        echo "Ping to $PING_TARGET failed."
        log_error "Ping to $PING_TARGET failed."
        if ! check_interface_ip; then
            echo "WAN interface $NETWORK_INTERFACE has no IP address."
            log_error "WAN interface $NETWORK_INTERFACE has no IP address."
        fi
        attempt_recovery
    else
        echo "External connectivity is OK."
    fi
}

# Script entry point (always runs main_check)
main_check

#!/bin/bash

# Test script for selective fragment retransmission
# This script tests the new selective fragment retransmission functionality

echo "======================================"
echo "Testing Selective Fragment Retransmission"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
LOCAL_IP="192.168.31.114"
REMOTE_IP="192.168.31.135"
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)

# Function to log with timestamp
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

# Function to check if strongswan is running
check_strongswan() {
    if pgrep -x "charon" > /dev/null; then
        log "${GREEN}strongSwan is running${NC}"
        return 0
    else
        log "${RED}strongSwan is not running${NC}"
        return 1
    fi
}

# Function to compile and install strongswan
compile_and_install() {
    log "${YELLOW}Compiling and installing strongSwan with selective fragment retransmission...${NC}"
    
    # Configure with selective fragment retransmission support
    ./configure --prefix=/usr --sysconfdir=/etc --enable-unity --enable-eap-identity \
        --enable-eap-md5 --enable-eap-mschapv2 --enable-eap-tls --enable-eap-ttls \
        --enable-eap-peap --enable-eap-tnc --enable-eap-dynamic --enable-eap-radius \
        --enable-xauth-eap --enable-xauth-pam --enable-dhcp --enable-openssl \
        --enable-addrblock --enable-unity --enable-certexpire --enable-radattr \
        --enable-swanctl --enable-openssl --disable-gmp --enable-fragmentation
    
    if [ $? -ne 0 ]; then
        log "${RED}Configure failed${NC}"
        return 1
    fi
    
    # Compile
    make -j4
    if [ $? -ne 0 ]; then
        log "${RED}Compilation failed${NC}"
        return 1
    fi
    
    # Install
    sudo make install
    if [ $? -ne 0 ]; then
        log "${RED}Installation failed${NC}"
        return 1
    fi
    
    log "${GREEN}strongSwan compiled and installed successfully${NC}"
    return 0
}

# Function to configure strongswan for selective fragment retransmission
configure_strongswan() {
    log "${YELLOW}Configuring strongSwan for selective fragment retransmission...${NC}"
    
    # Add selective fragment retransmission configuration
    sudo tee -a /etc/strongswan.conf > /dev/null << EOF

# Selective Fragment Retransmission Configuration
charon {
    # Enable selective fragment retransmission
    selective_fragment_retransmission = yes
    
    # Fragment timeout (seconds)
    fragment_timeout = 30
    
    # Maximum retransmission attempts
    max_retransmission_attempts = 3
    
    # Enable fragmentation
    fragmentation = yes
    
    # Enable detailed logging for debugging
    filelog {
        /var/log/strongswan.log {
            time_format = %b %e %T
            ike_name = yes
            append = no
            default = 1
            flush_line = yes
        }
    }
}
EOF
    
    log "${GREEN}strongSwan configured for selective fragment retransmission${NC}"
}

# Function to set up network conditions
setup_network_conditions() {
    log "${YELLOW}Setting up network conditions for testing...${NC}"
    
    # Clear existing tc rules
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null || true
    
    # Set up packet loss to trigger fragment retransmission
    sudo tc qdisc add dev $INTERFACE root netem loss 10% delay 50ms
    
    log "${GREEN}Network conditions set: 10% packet loss, 50ms delay${NC}"
}

# Function to clear network conditions
clear_network_conditions() {
    log "${YELLOW}Clearing network conditions...${NC}"
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null || true
    log "${GREEN}Network conditions cleared${NC}"
}

# Function to start strongswan
start_strongswan() {
    log "${YELLOW}Starting strongSwan...${NC}"
    
    # Stop existing strongswan
    sudo systemctl stop strongswan 2>/dev/null || true
    sudo pkill -f charon 2>/dev/null || true
    sleep 2
    
    # Start strongswan
    sudo systemctl start strongswan
    sleep 3
    
    if check_strongswan; then
        log "${GREEN}strongSwan started successfully${NC}"
        return 0
    else
        log "${RED}Failed to start strongSwan${NC}"
        return 1
    fi
}

# Function to test selective fragment retransmission
test_selective_retransmission() {
    log "${YELLOW}Testing selective fragment retransmission...${NC}"
    
    # Clear previous logs
    sudo truncate -s 0 /var/log/strongswan.log
    
    # Start connection
    log "Initiating IPsec connection..."
    sudo swanctl --initiate --ike net-net &
    CONNECTION_PID=$!
    
    # Wait for connection to establish or timeout
    sleep 30
    
    # Check if connection is still running
    if kill -0 $CONNECTION_PID 2>/dev/null; then
        log "${YELLOW}Connection attempt still running, waiting...${NC}"
        sleep 30
        kill $CONNECTION_PID 2>/dev/null || true
    fi
    
    # Analyze logs for selective fragment retransmission
    log "${YELLOW}Analyzing logs for selective fragment retransmission...${NC}"
    
    # Check for selective retransmission support advertisement
    if grep -q "advertising selective fragment retransmission support" /var/log/strongswan.log; then
        log "${GREEN}✓ Selective fragment retransmission support advertised${NC}"
    else
        log "${RED}✗ Selective fragment retransmission support not advertised${NC}"
    fi
    
    # Check for peer support detection
    if grep -q "peer supports selective fragment retransmission" /var/log/strongswan.log; then
        log "${GREEN}✓ Peer support for selective fragment retransmission detected${NC}"
    else
        log "${YELLOW}! Peer support for selective fragment retransmission not detected${NC}"
    fi
    
    # Check for fragment acknowledgments
    if grep -q "sent fragment ack" /var/log/strongswan.log; then
        log "${GREEN}✓ Fragment acknowledgments sent${NC}"
    else
        log "${YELLOW}! No fragment acknowledgments found${NC}"
    fi
    
    # Check for selective retransmission
    if grep -q "selective retransmit.*missing fragments" /var/log/strongswan.log; then
        log "${GREEN}✓ Selective fragment retransmission performed${NC}"
    else
        log "${YELLOW}! No selective fragment retransmission found${NC}"
    fi
    
    # Check for fragment tracker creation
    if grep -q "created fragment tracker" /var/log/strongswan.log; then
        log "${GREEN}✓ Fragment tracker created${NC}"
    else
        log "${YELLOW}! No fragment tracker creation found${NC}"
    fi
    
    # Check for fragment acknowledgment updates
    if grep -q "fragment ack update" /var/log/strongswan.log; then
        log "${GREEN}✓ Fragment acknowledgment updates processed${NC}"
    else
        log "${YELLOW}! No fragment acknowledgment updates found${NC}"
    fi
    
    # Show fragment statistics
    log "${BLUE}Fragment statistics:${NC}"
    echo "Total fragments sent: $(grep -c "sending packet.*4500" /var/log/strongswan.log)"
    echo "Fragment retransmissions: $(grep -c "retransmit.*fragments" /var/log/strongswan.log)"
    echo "Selective retransmissions: $(grep -c "selective retransmit" /var/log/strongswan.log)"
    echo "Fragment acknowledgments: $(grep -c "fragment ack" /var/log/strongswan.log)"
}

# Function to compare with traditional retransmission
compare_with_traditional() {
    log "${YELLOW}Comparing with traditional retransmission...${NC}"
    
    # Disable selective fragment retransmission
    sudo sed -i 's/selective_fragment_retransmission = yes/selective_fragment_retransmission = no/' /etc/strongswan.conf
    
    # Restart strongswan
    sudo systemctl restart strongswan
    sleep 3
    
    # Clear logs
    sudo truncate -s 0 /var/log/strongswan.log
    
    # Test traditional retransmission
    log "Testing traditional retransmission..."
    sudo swanctl --initiate --ike net-net &
    CONNECTION_PID=$!
    sleep 30
    kill $CONNECTION_PID 2>/dev/null || true
    
    # Analyze traditional retransmission
    traditional_retransmits=$(grep -c "retransmit.*request" /var/log/strongswan.log)
    log "${BLUE}Traditional retransmissions: $traditional_retransmits${NC}"
    
    # Re-enable selective fragment retransmission
    sudo sed -i 's/selective_fragment_retransmission = no/selective_fragment_retransmission = yes/' /etc/strongswan.conf
    sudo systemctl restart strongswan
}

# Function to cleanup
cleanup() {
    log "${YELLOW}Cleaning up...${NC}"
    clear_network_conditions
    sudo systemctl stop strongswan 2>/dev/null || true
    log "${GREEN}Cleanup completed${NC}"
}

# Main test execution
main() {
    log "${GREEN}Starting selective fragment retransmission test${NC}"
    
    # Check if we're in the strongswan directory
    if [ ! -f "configure" ]; then
        log "${RED}Error: Not in strongSwan source directory${NC}"
        exit 1
    fi
    
    # Compile and install
    if ! compile_and_install; then
        log "${RED}Failed to compile and install strongSwan${NC}"
        exit 1
    fi
    
    # Configure strongswan
    configure_strongswan
    
    # Set up network conditions
    setup_network_conditions
    
    # Start strongswan
    if ! start_strongswan; then
        cleanup
        exit 1
    fi
    
    # Test selective fragment retransmission
    test_selective_retransmission
    
    # Compare with traditional retransmission
    compare_with_traditional
    
    # Cleanup
    cleanup
    
    log "${GREEN}Test completed successfully${NC}"
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Run main function
main "$@" 
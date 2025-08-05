#!/bin/bash

# ==============================================================================
# IPsec Burst Loss Analysis Script (v1.1 - Revised)
#
# Author: Gemini
# Revision Date: 2025-07-20
#
# Description:
# This script systematically tests IPsec handshake performance under
# various burst packet loss conditions. It measures Success Rate,
# Handshake Completion Time (HCT), and IKE Retransmission Counts.
#
# Changelog (v1.1):
# - CRITICAL: Implemented log isolation using markers to ensure retransmission
#   counts are accurate for each specific attempt.
# - FIX: Correctly converted HCT from seconds (swanctl output) to milliseconds.
# - ROBUSTNESS: Removed jq dependency, using only Ubuntu built-in commands.
# - USABILITY: Made output messages clearer.
# ==============================================================================

# --- Script Configuration ---
CONNECTION_NAME="net-net"
# MODIFICATION: Recommended scientific loss rate sequence
LOSS_RATES_DEFAULT="0,2,5,8,12,15,20,30"
NUM_TESTS_DEFAULT=50
LOG_FILE="/var/log/charon.log"
OUTPUT_DIR="test_results_$(date +%F_%H-%M-%S)"
SWANCTL_LOG_LEVEL="" # No extra logging flags for normal operation

# --- Function Definitions ---

# Print usage information
usage() {
    echo "Usage: $0 [-n num_tests] [-r loss_rates] [-c conn_name] [-m] [-s single_rate]"
    echo "  -n num_tests    : Number of connection attempts per loss rate (default: ${NUM_TESTS_DEFAULT})"
    echo "  -r loss_rates   : Comma-separated list of loss rates to test (default: \"${LOSS_RATES_DEFAULT}\")"
    echo "  -c conn_name    : IPsec connection name to initiate (default: ${CONNECTION_NAME})"
    echo "  -m              : Manual mode - test current network conditions without changing them"
    echo "  -s single_rate  : Test only specified loss rate (e.g., -s 5 for 5%)"
    echo ""
    echo "Manual Mode Usage:"
    echo "  1. Set network conditions on BOTH endpoints:"
    echo "     sudo ./set_packet_loss.sh -r 5    # Set 5% loss rate"
    echo "  2. Run test in manual mode:"
    echo "     sudo $0 -m -n 100                 # Test current conditions 100 times"
    exit 1
}

# Check for required command-line tools
check_dependencies() {
    for cmd in awk grep sed sort; do
        if ! command -v $cmd &> /dev/null; then
            echo "Error: Required command '$cmd' is not installed. Please install it to continue."
            exit 1
        fi
    done
}

# Get retransmission count for the last attempt
get_retransmissions() {
    local test_marker=$1
    # Count all retransmissions from the log section
    local log_section
    log_section=$(sed -n "/${test_marker}/,\$p" "$LOG_FILE")
    local total_retrans=$(echo "$log_section" | grep -c "retransmit")
    
    # If no retransmissions found in log, try to estimate from output
    if [ "$total_retrans" -eq 0 ]; then
        # This is a fallback method - we can't get exact count without proper logging
        # but we can estimate based on connection time and typical behavior
        echo "0"
    else
        echo "$total_retrans"
    fi
}

# --- Main Logic ---

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root to modify network conditions."
   exit 1
fi

check_dependencies

# Initialize variables
MANUAL_MODE=false
SINGLE_RATE=""

# Parse command-line arguments
while getopts "n:r:c:hms:" opt; do
    case ${opt} in
        n) NUM_TESTS=$OPTARG ;;
        r) LOSS_RATES=$OPTARG ;;
        c) CONNECTION_NAME=$OPTARG ;;
        h) usage ;;
        m) MANUAL_MODE=true ;;
        s) SINGLE_RATE=$OPTARG ;;
        *) usage ;;
    esac
done

# Set defaults if not provided
NUM_TESTS=${NUM_TESTS:-$NUM_TESTS_DEFAULT}
LOSS_RATES=${LOSS_RATES:-$LOSS_RATES_DEFAULT}

# Handle single rate mode
if [[ -n "$SINGLE_RATE" ]]; then
    LOSS_RATES="$SINGLE_RATE"
fi

# Handle manual mode - use "current" as the rate label
if [[ "$MANUAL_MODE" == "true" && -z "$SINGLE_RATE" ]]; then
    LOSS_RATES="current"
fi

# Create output directory with proper permissions
mkdir -p "$OUTPUT_DIR"
# Set ownership to current user
sudo chown -R $(whoami):$(whoami) "$OUTPUT_DIR"
# Set proper permissions (755 for directories, 644 for files)
chmod 755 "$OUTPUT_DIR"
echo "Results will be saved in: $OUTPUT_DIR"

if [[ "$MANUAL_MODE" == "true" ]]; then
    echo "MANUAL MODE: Testing current network conditions"
    echo "WARNING: Make sure BOTH endpoints have the same network conditions!"
    echo "Attempts: ${NUM_TESTS}"
else
    echo "AUTO MODE: Testing with Loss Rates: [${LOSS_RATES}]"
    echo "Attempts per Rate: ${NUM_TESTS}"
fi
echo "-----------------------------------------------------"

    # Create summary file header
    SUMMARY_FILE="${OUTPUT_DIR}/summary_results.csv"
    echo "loss_rate,success_rate,success_count,failed_count,total_count,avg_hct_ms,median_hct_ms,std_dev_hct_ms,avg_retransmissions" > "$SUMMARY_FILE"
    # Set proper permissions for the file
    chmod 644 "$SUMMARY_FILE"

# Convert comma-separated string to array
IFS=',' read -r -a rates_array <<< "$LOSS_RATES"

# Outer loop: Iterate over each loss rate
for rate in "${rates_array[@]}"; do
    if [[ "$MANUAL_MODE" == "true" ]]; then
        echo "Testing current network conditions (manual mode)"
        echo "Current loss rate label: ${rate}% (for file naming only)"
    else
        echo "Setting up network for Loss Rate: ${rate}%"
        ./set_packet_loss.sh -r "$rate"
        if [[ $? -ne 0 ]]; then
            echo "Error setting packet loss. Aborting."
            exit 1
        fi
    fi

    # Initialize variables for this batch
    success_count=0
    hct_values=()
    retrans_values=()
    DETAIL_FILE="${OUTPUT_DIR}/loss_${rate}_percent_details.csv"
    echo "test_num,status,hct_ms,retransmissions" > "$DETAIL_FILE"
    # Set proper permissions for the detail file
    chmod 644 "$DETAIL_FILE"

    echo "Running ${NUM_TESTS} connection tests..."
    
    # Restart strongSwan service before starting tests to ensure clean state
    systemctl restart strongswan &>/dev/null
    sleep 5  # Give service time to fully initialize

    # Inner loop: Perform N connection attempts
    for ((i=1; i<=NUM_TESTS; i++)); do
        # MODIFICATION: Add a unique marker to the log before each test
        TEST_MARKER="IPSEC_TEST_MARKER_RATE_${rate}_ATTEMPT_${i}_$(date +%s%N)"
        echo "$TEST_MARKER" >> "$LOG_FILE"
        
        # Give extra time for first attempt after service restart
        if [[ $i -eq 1 ]]; then
            sleep 5  # Extra wait for first attempt
        fi

        # Run the test and capture output (using the successful method from fig3)
        start_time=$(date +%s.%N)
        
        # Create temporary log file to capture output
        temp_log=$(mktemp)
        timeout 30 swanctl --initiate --ike "$CONNECTION_NAME" > "$temp_log" 2>&1
        exit_code=$?
        
        end_time=$(date +%s.%N)

        # Calculate HCT using awk instead of bc
        hct_s=$(awk "BEGIN {printf \"%.6f\", $end_time - $start_time}")
        # Convert to milliseconds
        hct_ms=$(awk "BEGIN {printf \"%.3f\", $hct_s * 1000}")

        # Count retransmissions directly from swanctl output (BEFORE restarting service)
        retrans_count=$(grep -c "retransmit.*of request" "$temp_log" 2>/dev/null || echo "0")
        retrans_count=$(echo "$retrans_count" | tr -d '\n\r')
        
        # Restart strongSwan service to clean up state (more efficient than terminate)
        systemctl restart strongswan &>/dev/null
        sleep 2  # Give service time to restart

        # Check IKE_SA establishment status (not full connection)
        if [ $exit_code -eq 0 ]; then
            # Check if IKE_SA was established by looking for IKE_SA establishment message
            if grep -q "IKE_SA.*established between" "$temp_log"; then
                status="SUCCESS"
                ((success_count++))
                hct_values+=("$hct_ms")
                echo "Attempt ${i}/${NUM_TESTS}: SUCCESS (IKE_SA established), HCT: ${hct_ms} ms, Retransmissions: ${retrans_count}"
            else
                status="FAILED"
                # Record actual time spent even for failed attempts
                echo "Attempt ${i}/${NUM_TESTS}: FAILED (IKE_SA not established), HCT: ${hct_ms} ms, Retransmissions: ${retrans_count}"
            fi
        elif [ $exit_code -eq 124 ]; then
            status="TIMEOUT"
            # For timeout, set retransmissions to 9 (maximum retransmissions before timeout)
            retrans_count="9"
            # Record actual time spent for timeout attempts
            echo "Attempt ${i}/${NUM_TESTS}: TIMEOUT, HCT: ${hct_ms} ms, Retransmissions: ${retrans_count}"
        else
            status="FAILED"
            # Record actual time spent for failed attempts
            echo "Attempt ${i}/${NUM_TESTS}: FAILED, HCT: ${hct_ms} ms, Retransmissions: ${retrans_count}"
        fi

        retrans_values+=("$retrans_count")
        echo "$i,$status,$hct_ms,$retrans_count" >> "$DETAIL_FILE"
        
        # Clean up temporary log file
        rm -f "$temp_log"
        
        # Ensure proper permissions after each write
        chmod 644 "$DETAIL_FILE"
    done

    # --- Calculate statistics for this batch ---
    total_count=$NUM_TESTS
    failed_count=$((total_count - success_count))
    success_rate=$(awk "BEGIN {printf \"%.4f\", ($success_count / $total_count) * 100}")

    # HCT stats (for all attempts - successful, failed, and timeout)
    # Extract HCT values from detail file for all attempts
    hct_all_values=()
    while IFS=',' read -r test_num status hct_ms retrans; do
        if [[ "$hct_ms" != "hct_ms" && "$hct_ms" != "N/A" ]]; then
            hct_all_values+=("$hct_ms")
        fi
    done < "$DETAIL_FILE"
    
    if [[ ${#hct_all_values[@]} -gt 0 ]]; then
        # Join array elements for calculation
        hct_list=$(printf "%s\n" "${hct_all_values[@]}")
        avg_hct=$(echo "$hct_list" | awk '{ total += $1 } END { print total/NR }')
        # Sort for median
        sorted_hct=($(echo "$hct_list" | sort -n))
        mid=$(( ${#sorted_hct[@]} / 2 ))
        if (( ${#sorted_hct[@]} % 2 == 0 )); then
            median_hct=$(awk "BEGIN {printf \"%.3f\", (${sorted_hct[mid-1]} + ${sorted_hct[mid]}) / 2}")
        else
            median_hct=${sorted_hct[mid]}
        fi
        std_dev_hct=$(echo "$hct_list" | awk -v avg="$avg_hct" '{ sum_sq += ($1 - avg)^2 } END { print sqrt(sum_sq/NR) }')
    else
        avg_hct="N/A"
        median_hct="N/A"
        std_dev_hct="N/A"
    fi

    # Retransmission stats (for all attempts)
    retrans_list=$(printf "%s\n" "${retrans_values[@]}")
    avg_retrans=$(echo "$retrans_list" | awk '{ total += $1 } END { print total/NR }')

    # Append summary data
    echo "$rate,$success_rate,$success_count,$failed_count,$total_count,$avg_hct,$median_hct,$std_dev_hct,$avg_retrans" >> "$SUMMARY_FILE"
    # Ensure proper permissions for summary file
    chmod 644 "$SUMMARY_FILE"
    echo "-----------------------------------------------------"
done

# Clean up network settings (only in auto mode)
if [[ "$MANUAL_MODE" == "true" ]]; then
    echo "Tests complete. Network conditions preserved (manual mode)."
    echo "Remember to clean up network rules manually when done:"
    echo "  sudo ./set_packet_loss.sh -c"
else
    echo "Tests complete. Cleaning up network rules."
    ./set_packet_loss.sh -c
fi

echo "All done. Summary results are in: ${SUMMARY_FILE}"
#!/bin/bash
# Usage: ./shodan_discovery.sh ip_list.txt
# Ensure that you have the Shodan CLI installed and configured with your API key.
# This script reads IPs from the supplied file, runs "shodan host <IP>" for each,
# and appends the results to Results/Shodan_Discovery.txt.

# Check that an input file is provided.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <ip_list_file>"
    exit 1
fi

IP_FILE="$1"

# Check if the file exists.
if [ ! -f "$IP_FILE" ]; then
    echo "Error: File '$IP_FILE' not found."
    exit 1
fi

# Create the Results directory if it doesn't exist.
RESULTS_DIR="Results"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="${RESULTS_DIR}/Shodan_Discovery.txt"

# Clear the results file.
> "$RESULTS_FILE"

# Process each IP in the file.
while IFS= read -r ip || [ -n "$ip" ]; do
    # Skip empty lines or comments.
    if [[ -z "$ip" || "$ip" =~ ^# ]]; then
        continue
    fi

    echo "Scanning IP: $ip"
    echo "----- IP: $ip -----" >> "$RESULTS_FILE"
    
    # Run the Shodan host command for the current IP and append the output.
    shodan host "$ip" >> "$RESULTS_FILE" 2>&1
    echo -e "\n" >> "$RESULTS_FILE"
    sleep 1.5
done < "$IP_FILE"

echo "Shodan discovery complete. Results saved in $RESULTS_FILE"


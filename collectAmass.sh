#!/bin/bash
# Usage: ./collect_amass_discovery.sh
#
# This script processes each domain folder under the Results directory.
# It expects that each domain folder (e.g., Results/myDomain.com) contains an "amass.txt" file.
# From each "amass.txt", the script extracts:
#   - The host names (assumed to be the first token on each line)
#   - The IP addresses (using a regex to match IPv4 addresses)
#
# It then deduplicates the combined lists and writes them to:
#   - Results/Amass_Discovery.txt (host names)
#   - Results/Amass_IP_Discovery.txt (IP addresses)

RESULTS_DIR="Results"
HOSTS_FILE="${RESULTS_DIR}/Amass_Discovery.txt"
IPS_FILE="${RESULTS_DIR}/Amass_IP_Discovery.txt"

# Temporary files to accumulate results
TEMP_HOSTS="/tmp/amass_hosts.tmp"
TEMP_IPS="/tmp/amass_ips.tmp"

# Clear the output and temporary files
> "$HOSTS_FILE"
> "$IPS_FILE"
> "$TEMP_HOSTS"
> "$TEMP_IPS"

# Iterate over each domain folder in RESULTS_DIR
for domain_folder in "$RESULTS_DIR"/*/; do
    # Check if the folder contains an amass.txt file
    if [ -f "$domain_folder/amass.txt" ]; then
        echo "[*] Processing $domain_folder/amass.txt"

        # Extract host names (first token from each line)
        # Remove any ANSI escape sequences in case they exist
        awk '{print $1}' "$domain_folder/amass.txt" | sed -r 's/\x1B\[[0-9;]*[mK]//g' >> "$TEMP_HOSTS"

        # Extract IP addresses using a regex for IPv4 addresses.
        # This will find any occurrence of a pattern like 192.168.1.1.
        grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$domain_folder/amass.txt" >> "$TEMP_IPS"
    fi
done

# Deduplicate and sort the host names and IPs, then save to final output files.
sort -u "$TEMP_HOSTS" > "$HOSTS_FILE"
sort -u "$TEMP_IPS" > "$IPS_FILE"

# Remove temporary files
rm "$TEMP_HOSTS" "$TEMP_IPS"

echo "Amass Discovery hosts saved in $HOSTS_FILE"
echo "Amass Discovery IPs saved in $IPS_FILE"

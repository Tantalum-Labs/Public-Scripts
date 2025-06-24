#!/bin/bash
# Usage: ./collect_harvester.sh
# This script expects a folder "Results" in the current directory,
# which contains subdirectories for each domain (e.g., Results/myDomain.com).
# Each domain folder should contain a file named "theharvester.txt".
# The script extracts the host names listed under the "[*] Hosts found:" section,
# ignoring entries that have an IP address after a colon,
# and aggregates them into Results/Harvester_Discovery.txt without duplicates.

RESULTS_DIR="Results"
OUTPUT_FILE="${RESULTS_DIR}/Harvester_Discovery.txt"
TEMP_FILE="${RESULTS_DIR}/Harvester_Discovery.tmp"

# Clear/create the temporary file.
> "$TEMP_FILE"

# Function to extract the hosts from theharvester.txt.
extract_hosts() {
    local harvester_file="$1"
    # Use awk to start processing when the line "[*] Hosts found:" is encountered.
    # Skip the next line (the separator line).
    # Then, for each subsequent line that is not empty, print the line until a blank line is reached.
    awk '
        BEGIN { found=0 }
        /\[\*\] Hosts found:/ { found=1; next }
        found==1 && /^[-]+/ { next } 
        found==1 && NF==0 { exit } 
        found==1 { print }
    ' "$harvester_file"
}

# Iterate over each domain folder in the Results directory.
for domain_folder in "$RESULTS_DIR"/*/; do
    HARVESTER_FILE="${domain_folder}/theharvester.txt"
    if [ -f "$HARVESTER_FILE" ]; then
        echo "Processing harvester file in: ${domain_folder}"
        # Extract hosts from the file.
        hosts=$(extract_hosts "$HARVESTER_FILE")
        # Filter out lines that have a colon followed by an IP address (i.e. any digits after colon).
        # This uses a regex to exclude lines matching ":<digit>".
        echo "$hosts" | grep -Ev ":[0-9]" >> "$TEMP_FILE"
        # Optionally add a newline separator.
        echo "" >> "$TEMP_FILE"
    else
        echo "No theharvester.txt found in ${domain_folder}"
    fi
done

# Deduplicate the list, removing blank lines.
sort "$TEMP_FILE" | sed '/^\s*$/d' | uniq > "$OUTPUT_FILE"

# Remove the temporary file.
rm "$TEMP_FILE"

echo "Deduplicated harvester host list is available in ${OUTPUT_FILE}"

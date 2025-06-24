#!/bin/bash
# Usage: ./combine_domain_sources.sh domains.txt
# This script assumes that:
#   - The final host list is available at Results/Combined_Subdomain_Discovery.txt
#   - A file (domains.txt) containing the original list of domains is supplied as the first argument.
# It combines both files and creates a deduplicated output file named Results/Combined_Domains.txt

RESULTS_DIR="Results"
FINAL_HOST_LIST="${RESULTS_DIR}/Combined_Subdomain_Discovery.txt"

# Ensure the domains file is provided and exists.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <domains.txt>"
    exit 1
fi

DOMAINS_FILE="$1"
if [ ! -f "$DOMAINS_FILE" ]; then
    echo "Error: File '$DOMAINS_FILE' not found."
    exit 1
fi

# Check that Combined_Subdomain_Discovery.txt exists.
if [ ! -f "$FINAL_HOST_LIST" ]; then
    echo "Error: ${FINAL_HOST_LIST} not found."
    exit 1
fi

OUTPUT_FILE="${RESULTS_DIR}/All_Domains.txt"
TEMP_FILE="${RESULTS_DIR}/Combined_Domains.tmp"

# Combine the two files into a temporary file.
cat "$FINAL_HOST_LIST" "$DOMAINS_FILE" > "$TEMP_FILE"

# Deduplicate and sort the list, while removing blank lines.
sort "$TEMP_FILE" | sed '/^\s*$/d' | uniq > "$OUTPUT_FILE"

# Remove the temporary file.
rm "$TEMP_FILE"

echo "Combined deduplicated domain list is available in ${OUTPUT_FILE}"

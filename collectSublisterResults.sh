#!/bin/bash
# Usage: ./collect_subdomains.sh
# This script expects a folder "Results" in the current directory,
# which contains subdirectories for each domain (e.g., Results/myDomain.com).
# Each domain folder should contain a file named "sublist3r.txt".
# The script aggregates the subdomains into Results/Subdomain_Discovery.txt,
# then deduplicates the list to ensure there are no duplicate entries.

RESULTS_DIR="Results"
OUTPUT_FILE="${RESULTS_DIR}/Sublister_Discovery.txt"
TEMP_FILE="${RESULTS_DIR}/Sublister_Discovery.tmp"

# Clear or create the temporary output file.
> "$TEMP_FILE"

# Iterate over each domain folder in the Results directory.
for domain_folder in "$RESULTS_DIR"/*/; do
    # Check if sublist3r.txt exists in this folder.
    SUBLIST_FILE="${domain_folder}/sublist3r.txt"
    if [ -f "$SUBLIST_FILE" ]; then
        echo "Collecting subdomains from: ${domain_folder}"
        cat "$SUBLIST_FILE" >> "$TEMP_FILE"
        # Optionally add a newline separator.
        echo "" >> "$TEMP_FILE"
    else
        echo "No sublist3r.txt found in ${domain_folder}"
    fi
done

# Deduplicate the list: sort the entries, remove blank lines, and then remove duplicates.
sort "$TEMP_FILE" | sed '/^\s*$/d' | uniq > "$OUTPUT_FILE"

# Remove the temporary file.
rm "$TEMP_FILE"

echo "Deduplicated subdomain list is available in ${OUTPUT_FILE}"

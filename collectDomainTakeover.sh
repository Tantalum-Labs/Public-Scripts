#!/bin/bash
# Usage: ./collect_takeover.sh
#
# This script expects a folder "Results" in the current directory,
# with each subdirectory representing a domain (e.g., Results/myDomain.com).
# Each domain folder should contain a file named "takeover.txt" with the
# subdomain takeover check output.
#
# For each domain where a takeover is detected (i.e. a "Takeover detected:" line is present),
# the script extracts:
#   - The URL from the takeover output. It first tries the line containing "Takeover detected:",
#     but if a separate line with a quoted URL is found, it uses that.
#   - The takeover type from the "Type of takeover is:" line.
#
# The output is appended to Results/Domain_takeover.txt in the format:
#
# beta.duggal.com
# Takeover successful
# Cargo Collective with match: 404 Not Found
#
# Leading/trailing whitespace and ANSI color markers are removed.

OUTPUT_FILE="Results/Domain_Takeover.txt"
RESULTS_DIR="Results"

# Clear or create the output file.
> "$OUTPUT_FILE"

# Define a regex pattern for ANSI escape sequences.
ansi_escape_pattern='\x1B\[[0-9;]*[a-zA-Z]'

# Process each domain folder in the Results directory.
for domain_folder in "$RESULTS_DIR"/*/; do
    [ -d "$domain_folder" ] || continue

    takeover_file="$domain_folder/theharvester.txt"
    [ -f "$takeover_file" ] || continue

    # Check if a takeover was detected.
    if grep -q "Takeover detected:" "$takeover_file"; then
        # Extract the "Takeover detected:" line, remove ANSI escape sequences and whitespace.
        detected_line=$(grep -E "Takeover detected:" "$takeover_file" | head -n1 | \
          sed -E "s/${ansi_escape_pattern}//g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Try to extract a URL from a separate quoted line.
        url_line=$(grep "^'" "$takeover_file" | head -n1 | \
          sed -E "s/${ansi_escape_pattern}//g" | sed -E "s/['\"]//g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -n "$url_line" ]; then
            takeover_url="$url_line"
        else
            takeover_url=$(echo "$detected_line" | sed -E 's/.*Takeover detected:[[:space:]]*//')
        fi

        # Extract the domain portion from the URL.
        takeover_domain=$(echo "$takeover_url" | sed -E 's#https?://##; s#[:/].*##')
        
        # Extract the takeover type.
        takeover_type=$(grep -E "Type of takeover is:" "$takeover_file" | head -n1 | \
          sed -E "s/${ansi_escape_pattern}//g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
          sed 's/Type of takeover is:[[:space:]]*//')
        if [ -z "$takeover_type" ]; then
            takeover_type="Unknown type"
        fi

        # Append the results to the output file.
        {
          echo "$takeover_domain"
          echo "Takeover successful"
          echo "$takeover_type"
          echo ""
        } >> "$OUTPUT_FILE"
    fi
done

echo "Domain takeover report generated at $OUTPUT_FILE"

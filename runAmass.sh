#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

DOMAIN="$1"
RESULTS_DIR="Results/$DOMAIN"
RAW_OUTPUT="$RESULTS_DIR/amass_output.tmp"
CLEAN_OUTPUT="$RESULTS_DIR/cleaned_output.tmp"
FINAL_OUTPUT="$RESULTS_DIR/amass.txt"

# Create the Results directory if it doesn't exist.
mkdir -p "$RESULTS_DIR"
rm -f "$RAW_OUTPUT" "$CLEAN_OUTPUT"

echo "[*] Running Amass enumeration for $DOMAIN..."
# Run Amass in passive mode and write output to RAW_OUTPUT.
amass enum -passive -d "$DOMAIN" -o "$RAW_OUTPUT" -timeout 3

if [ ! -f "$RAW_OUTPUT" ]; then
    echo "Error: Amass output file not found."
    exit 1
fi

echo "[*] Cleaning output (removing ANSI color codes)..."
# Remove ANSI escape sequences using sed.
sed -r 's/\x1B\[[0-9;]*[mK]//g' "$RAW_OUTPUT" > "$CLEAN_OUTPUT"

echo "[*] Processing cleaned output to extract subdomain:IP pairs..."
# The expected line format after cleaning is:
#   subdomain (FQDN) --> a_record --> IP (IPAddress)
# We use awk with a variable to ensure the subdomain contains the original domain.
awk -v domain="$DOMAIN" '/a_record/ {
    if ($1 ~ domain && $4 == "a_record") {
        print $1 ":" $6
    }
}' "$CLEAN_OUTPUT" | sort -u > "$FINAL_OUTPUT"

# Clean up temporary files.
rm -f "$RAW_OUTPUT" "$CLEAN_OUTPUT"

echo "[*] Subdomain:IP pairs saved in $FINAL_OUTPUT"

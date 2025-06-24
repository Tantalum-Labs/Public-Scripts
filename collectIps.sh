#!/bin/bash
RESULTS_DIR="Results"
HARVESTER_FILE="${RESULTS_DIR}/Harvester_IP_Discovery.txt"
AMASS_FILE="${RESULTS_DIR}/Amass_IP_Discovery.txt"
FINAL_OUTPUT="${RESULTS_DIR}/Combined_IP_Discovery.txt"
TEMP_FILE="${RESULTS_DIR}/Combined_IP_Discovery.tmp"

# Check that the expected input files exist.
if [ ! -f "$HARVESTER_FILE" ]; then
    echo "Error: ${HARVESTER_FILE} not found."
    exit 1
fi

if [ ! -f "$AMASS_FILE" ]; then
    echo "Error: ${AMASS_FILE} not found."
    exit 1
fi


# Combine the two files into a temporary file.
cat "$AMASS_FILE" "$HARVESTER_FILE" > "$TEMP_FILE"

# Deduplicate, remove blank lines, and sort the list.
sort "$TEMP_FILE" | sed '/^\s*$/d' | uniq > "$FINAL_OUTPUT"

# Remove the temporary file.
rm "$TEMP_FILE"

echo "Final deduplicated ip list is available in ${FINAL_OUTPUT}"


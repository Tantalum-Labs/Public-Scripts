#!/bin/bash
# Usage: ./process_shodan_ports.sh
#
# This script processes the file Results/Shodan_Discovery.txt,
# extracts open TCP and UDP port numbers from the "Ports:" sections,
# aggregates them (removing duplicates), and writes the results to:
#
# Results/Shodan_Ports_Discovery.txt
#
# Format:
# T:80,443,2082,2083,2086,2087
# U:53,445,...

INPUT_FILE="Results/Shodan_Discovery.txt"
OUTPUT_FILE="Results/Shodan_Ports_Discovery.txt"

# Verify the input file exists.
if [ ! -f "$INPUT_FILE" ]; then
  echo "Input file $INPUT_FILE not found."
  exit 1
fi

# Extract TCP ports:
tcp_ports=$(grep -oE '[0-9]+/tcp' "$INPUT_FILE" | sed 's#/tcp##' | sort -n | uniq | paste -sd, -)

# Extract UDP ports:
udp_ports=$(grep -oE '[0-9]+/udp' "$INPUT_FILE" | sed 's#/udp##' | sort -n | uniq | paste -sd, -)

# Write results to the output file.
{
  echo "T:$tcp_ports"
  echo "U:$udp_ports"
} > "$OUTPUT_FILE"

echo "Shodan ports discovery written to $OUTPUT_FILE"

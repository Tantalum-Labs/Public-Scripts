#!/bin/bash

# Usage: ./process_ips.sh input.txt output.txt

# Check for required arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <source_file> <result_file>"
    exit 1
fi

SOURCE_FILE="$1"
RESULT_FILE="$2"

# Clear (or create) the result file
> "$RESULT_FILE"

# Function to trim whitespace
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Process each line of the source file
while IFS= read -r line || [ -n "$line" ]; do
    # Trim the line
    entry=$(trim "$line")
    
    # Skip empty lines
    if [ -z "$entry" ]; then
        continue
    fi

    # Check if the entry is an IP address (basic IPv4 check)
    if [[ "$entry" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$entry" >> "$RESULT_FILE"
    else
        # Assume it's a hostname; try to resolve it.
        # Here we use 'getent hosts' which works well on many Linux systems.
        resolved_ip=$(getent hosts "$entry" | awk '{ print $1 }' | head -n 1)
        
        if [ -n "$resolved_ip" ]; then
            echo "$resolved_ip" >> "$RESULT_FILE"
        else
            echo "Error: Unable to resolve $entry" >> "$RESULT_FILE"
        fi
    fi
done < "$SOURCE_FILE"

echo "Processing complete. Results are in $RESULT_FILE."

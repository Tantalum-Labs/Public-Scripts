#!/bin/bash
SENDGRID_API_KEY=""
SENDER_EMAIL=""
RECIPIENT_EMAIL=""

OUTPUT_FILE="Results/Services_Overall.txt"
SIMPLE_OUTPUT_FILE="Results/Services_Simple_Overall.txt"
RESULTS_DIR="Results"

# Clear or create both output files.
> "$OUTPUT_FILE"
> "$SIMPLE_OUTPUT_FILE"

# Ensure xmlstarlet is installed.
if ! command -v xmlstarlet &>/dev/null; then
    echo "Error: xmlstarlet is required but not installed. Install it (e.g., sudo apt install xmlstarlet)."
    exit 1
fi

# Process each domain folder.
for domain_folder in "$RESULTS_DIR"/*/; do
    # Skip if not a directory.
    if [ ! -d "$domain_folder" ]; then
        continue
    fi

    domain=$(basename "$domain_folder")
    echo "$domain" >> "$OUTPUT_FILE"

    # Look for the Nmap XML scan file (expects a file matching "*_scan.xml")
    xml_file=$(find "$domain_folder" -maxdepth 1 -type f -name "*_scan.xml" | head -n1)

    if [ -z "$xml_file" ]; then
        echo "No XML scan file found for $domain" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "$domain; not scanned" >> "$SIMPLE_OUTPUT_FILE"
        continue
    fi

    # Extract detailed open port information along with script outputs.
    open_ports=$(xmlstarlet sel -T -t \
        -m "//port[state/@state='open']" \
            -o "Port: " -v "@portid" -o " - Service: " -v "service/@name" \
            -i "service/@product" -o " - " -v "service/@product" -o " " -v "service/@version" -n \
            -m "script[@id='banner' or @id='http-headers' or @id='http-title']" \
                -o "    [" -v "@id" -o "]: " -v "@output" -n \
            -b \
            -o "\n" \
        "$xml_file")

    if [ -z "$open_ports" ]; then
        echo "No open ports or service information found for $domain" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        # Simple report: scanned but no open ports.
        echo "$domain; no results" >> "$SIMPLE_OUTPUT_FILE"
    else
        # Use printf '%b' to interpret escape sequences.
        formatted_ports=$(printf "%b\n" "$open_ports" | sed 's/\([^[:space:]]\)\(Port:\)/\1\n\2/g')
        echo "$formatted_ports" >> "$OUTPUT_FILE"

        # For the simple report, extract only the port numbers, all on one line.
        ports=$(xmlstarlet sel -T -t \
            -m "//port[state/@state='open']" \
            -v "@portid" -o " " \
            "$xml_file" | sed 's/ *$//')
        if [ -z "$ports" ]; then
            echo "$domain; no results" >> "$SIMPLE_OUTPUT_FILE"
        else
            echo "$domain; $ports" >> "$SIMPLE_OUTPUT_FILE"
        fi
    fi

    # Extract any CVE information from the XML (including vulners output) and append to detailed report.
    cves=$(grep -o "CVE-[0-9]\{4\}-[0-9]\{1,7\}" "$xml_file" | sort -u | tr '\n' ', ' | sed 's/, $//')
    if [ -n "$cves" ]; then
        echo "$cves" >> "$OUTPUT_FILE"
    fi

    # Add a blank line after each domain's detailed report.
    echo "" >> "$OUTPUT_FILE"
done

echo "Detailed report generated at $OUTPUT_FILE"
echo "Simple report generated at $SIMPLE_OUTPUT_FILE"

# --- Email Sending Function using SendGrid API ---

send_email() {
    local report_file="$1"
    local subject="Nmap Service Report - $(date +'%Y-%m-%d %H:%M:%S')"

    # Base64 encode the report file and remove any newline characters.
    local attachment_content
    attachment_content=$(base64 "$report_file" | tr -d '\n')

    # Build the JSON payload including an attachment.
    read -r -d '' json_payload <<EOF
{
  "personalizations": [
    {
      "to": [
        {
          "email": "${RECIPIENT_EMAIL}"
        }
      ],
      "subject": "${subject}"
    }
  ],
  "from": {
    "email": "${SENDER_EMAIL}"
  },
  "content": [
    {
      "type": "text/plain",
      "value": "Please find attached the latest Nmap Service Report."
    }
  ],
  "attachments": [
    {
      "content": "${attachment_content}",
      "filename": "$(basename "$report_file")",
      "type": "text/plain",
      "disposition": "attachment"
    }
  ]
}
EOF

    # Send the email using the SendGrid API.
    curl --request POST \
         --url https://api.sendgrid.com/v3/mail/send \
         --header "Authorization: Bearer ${SENDGRID_API_KEY}" \
         --header "Content-Type: application/json" \
         --data "$json_payload"
}

# Ensure required environment variables are set.
if [ -z "$SENDGRID_API_KEY" ] || [ -z "$SENDER_EMAIL" ] || [ -z "$RECIPIENT_EMAIL" ]; then
    echo "Error: One or more required environment variables (SENDGRID_API_KEY, SENDER_EMAIL, RECIPIENT_EMAIL) are not set."
    exit 1
fi

# Call the email function to send the report.
send_email "$OUTPUT_FILE"

echo "Email sent to ${RECIPIENT_EMAIL}"


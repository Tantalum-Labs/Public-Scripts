#!/bin/bash
SENDGRID_API_KEY=""
SENDER_EMAIL=""
RECIPIENT_EMAIL=""

INPUT_FILE="Results/All_Domains.txt"

send_email() {
    local report_file="$INPUT_FILE"
    local subject="All Domain Report - $(date +'%Y-%m-%d %H:%M:%S')"
    local email_body
    # Use jq to safely encode the email body from the report file.
    if command -v jq &>/dev/null; then
        email_body=$(jq -Rs . < "$report_file")
    else
        # If jq is not available, do a simple replacement (note: this may not handle all special characters correctly).
        email_body=$(sed 's/"/\\"/g' "$report_file" | awk '{printf "%s\\n", $0}')
        email_body="\"$email_body\""
    fi

    # Build JSON payload.
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
      "value": ${email_body}
    }
  ]
}
EOF

    # Send the email via SendGrid API.
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

./collectHavesterResults.sh
./collectSublisterResults.sh
./collectSubdomains.sh
./collectAllDomains.sh domains.txt

# Call the email function to send the report.
send_email "$OUTPUT_FILE"

echo "Email sent to ${RECIPIENT_EMAIL}"

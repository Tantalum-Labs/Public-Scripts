#!/bin/bash
SENDGRID_API_KEY=""
SENDER_EMAIL=""
RECIPIENT_EMAIL=""

ZIP_PASSWORD=""

RESULTS_DIR="Results"
ZIP_FILE="Results.zip"
EMAIL_SUBJECT="Results Directory Archive - $(date +'%Y-%m-%d %H:%M:%S')"

# Create a high-compression, password-protected ZIP archive.
# -r: recursive, -9: maximum compression, -P: set password (note: -P is not as secure as encryption with a key)
zip -r -9 -P "$ZIP_PASSWORD" "$ZIP_FILE" "$RESULTS_DIR" > /dev/null 2>&1

if [ ! -f "$ZIP_FILE" ]; then
    echo "Failed to create ZIP archive. Exiting."
    exit 1
fi

# Base64 encode the ZIP file (remove newlines)
encoded_zip=$(base64 "$ZIP_FILE" | tr -d '\n')
fname=$(basename "$ZIP_FILE")

# Build the JSON payload for SendGrid.
read -r -d '' json_payload <<EOF
{
  "personalizations": [
    {
      "to": [
        {
          "email": "${RECIPIENT_EMAIL}"
        }
      ],
      "subject": "${EMAIL_SUBJECT}"
    }
  ],
  "from": {
    "email": "${SENDER_EMAIL}"
  },
  "content": [
    {
      "type": "text/plain",
      "value": "Please find attached the high compression, password-protected ZIP archive of the Results directory. The password is: ${ZIP_PASSWORD}"
    }
  ],
  "attachments": [
    {
      "content": "${encoded_zip}",
      "filename": "${fname}",
      "type": "application/zip",
      "disposition": "attachment"
    }
  ]
}
EOF

# Write the JSON payload to a temporary file.
temp_json=$(mktemp /tmp/email_payload.XXXXXX.json)
echo "$json_payload" > "$temp_json"

# Send the email using SendGrid API.
curl --request POST \
     --url https://api.sendgrid.com/v3/mail/send \
     --header "Authorization: Bearer ${SENDGRID_API_KEY}" \
     --header "Content-Type: application/json" \
     --data-binary @"$temp_json"

# Clean up the temporary JSON payload file.
rm "$temp_json"
rm "$ZIP_FILE"

echo "Email sent with Results directory archive attached."

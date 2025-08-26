#!/bin/bash
# Usage: ./securityTxtChecker.sh domains.txt

if [ $# -ne 1 ]; then
    echo -e "\033[0;36mUsage:\033[0m $0 <domain_list.txt>"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo -e "\033[0;31mError:\033[0m File '$1' not found!"
    exit 1
fi

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
ORANGE='\033[38;5;208m'   # Uses 256-color mode
BOLD='\033[1m'
ITALIC='\033[3m'
NC='\033[0m'  # No Color / reset

# Directories and log setup
RESULTS_DIR="./Results"
LOGS_DIR="$RESULTS_DIR/logs"
mkdir -p "$RESULTS_DIR"
mkdir -p "$LOGS_DIR"

# Error log file
TIMESTAMP=$(date +"%Y-%m-%d-%H%M")
ERROR_LOG="$LOGS_DIR/Error_Log_${TIMESTAMP}.txt"

# Initialize error log with header
echo "=== Security.txt Checker Error Log ===" > "$ERROR_LOG"
echo "Started: $(date)" >> "$ERROR_LOG"
echo "Hostname: $(hostname)" >> "$ERROR_LOG"
echo "========================================" >> "$ERROR_LOG"
echo "" >> "$ERROR_LOG"

# JSON output file
JSON_OUTPUT="$RESULTS_DIR/securityTxtChecker.json"
JSON_ARRAY="[]"

# AttackForge integration
USE_ATTACKFORGE=false
if [ -f "./attackforgeIntegration.sh" ]; then
    source ./attackforgeIntegration.sh
    USE_ATTACKFORGE=true
    echo -e "${CYAN}[i] AttackForge integration enabled.${NC}"
else
    echo -e "${YELLOW}[i] AttackForge integration not available. Running standalone.${NC}"
fi

# Check for projectID.txt and setup AttackForge integration
if [ "$USE_ATTACKFORGE" = true ]; then
    check_project_setup
fi

# Logging functions
log_error() {
    local error_msg="$1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] ERROR: $error_msg" >> "$ERROR_LOG"
    echo -e "${RED}[ERROR] $error_msg${NC}" >&2
}

log_info() {
    local info_msg="$1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] INFO: $info_msg" >> "$ERROR_LOG"
}

# JSON function
add_to_json() {
    local domain="$1"
    local asset_id="$2"
    local record_type="$3"
    local found_status="$4"
    local content="$5"
    local warnings="$6"

    log_info "Adding JSON entry for $domain - $record_type: $found_status"

    # Escape special characters in content and warnings
    content=$(echo "$content" | jq -Rs . 2>/dev/null || echo '""')
    warnings=$(echo "$warnings" | jq -Rs . 2>/dev/null || echo '""')

    # Create the JSON object
    local json_obj=$(jq -n \
        --arg domain "$domain" \
        --arg asset_id "$asset_id" \
        --arg record_type "$record_type" \
        --arg found_status "$found_status" \
        --argjson content "$content" \
        --argjson warnings "$warnings" \
        '{
            domain_name: $domain,
            af_asset_id: (if $asset_id == "null" then null else $asset_id end),
            record_type: $record_type,
            record_found_status: $found_status,
            record_content: $content,
            warnings: ($warnings | split("\n") | map(select(. != "")))
        }')

    # Add to the JSON array
    JSON_ARRAY=$(echo "$JSON_ARRAY" | jq ". += [$json_obj]")

    log_info "Successfully added $record_type entry for $domain to JSON"
}

print_logo() {
    echo -e "${PURPLE}"
    figlet "Security.txt Chkr"
    echo -e "${NC}"
    echo -e "${BLUE}${BOLD}Tantalum Labs 2025${NC}"
    echo -e "${YELLOW}${ITALIC}https://tantalumlabs.io${NC}"
    echo ""
}

# Function to extract the primary domain (last two labels)
get_primary() {
    domain="$1"
    IFS='.' read -ra parts <<< "$domain"
    len=${#parts[@]}
    if [ "$len" -ge 2 ]; then
        echo "${parts[$len-2]}.${parts[$len-1]}"
    else
        echo "$domain"
    fi
}

# Function to test a single domain.
# If the second argument is "indent", the output will be prefixed with a tab.
test_domain() {
    local domain="$1"
    local indent=""
    if [ "$2" == "indent" ]; then
        indent=$'\t'
    fi
    local url="https://${domain}/.well-known/security.txt"
    # Get HTTP status code (2s timeout)
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$url")
    local content=""
    local asset_id="${ASSET_MAP[$domain]:-null}"
    local found_status=""
    local warnings=""
    local record_type="security.txt"

    if [ "$http_code" == "200" ]; then
        content=$(curl -s --max-time 2 "$url")
        # Check that content contains both required fields.
        if echo "$content" | grep -qi '^Contact:' && echo "$content" | grep -qi '^Policy:'; then
            echo -e "${indent}${GREEN}[PASS]${NC} ${CYAN}${domain}${NC} - valid security.txt found at ${url}"
            found_status="found"
            warnings=""
        else
            echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC} - missing required fields or invalid"
            found_status="invalid"
            warnings="Missing required fields (Contact or Policy)"
        fi
    elif [ "$http_code" == "404" ]; then
        echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC} - security.txt not found (HTTP 404)"
        found_status="not-found"
        warnings="HTTP 404"
        content=""
    elif [ "$http_code" == "302" ]; then
        echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC} - Redirection (HTTP 302)"
        found_status="redirect"
        warnings="HTTP 302"
        content=""
    elif [ "$http_code" == "000" ]; then
        echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC} - No response"
        found_status="no-response"
        warnings="No response"
        content=""
    else
        echo -e "${indent}${YELLOW}[WARN]${NC} ${CYAN}${domain}${NC} - HTTP status code ${http_code}"
        found_status="warn"
        warnings="HTTP status code ${http_code}"
        content=""
    fi

    add_to_json "$domain" "$asset_id" "$record_type" "$found_status" "$content" "$warnings"
}

if [ $# -ne 1 ]; then
    echo -e "${CYAN}Usage:${NC} $0 <domain_list.txt>"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo -e "${RED}Error:${NC} File '$1' not found!"
    exit 1
fi

print_logo

echo -e "${CYAN}Starting security.txt checks...${NC}"
echo "-----------------------------------------"

# Declare an associative array to hold groups by primary domain.
declare -A groups

# Read each domain from the file and group them by primary domain.
declare -a ALL_DOMAINS
while IFS= read -r domain || [[ -n "$domain" ]]; do
    # Skip empty lines or comments.
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue
    primary=$(get_primary "$domain")
    # Append domain to the group (space-delimited list)
    groups["$primary"]+="$domain"$'\n'
    ALL_DOMAINS+=("$domain")
done < "$1"

# AttackForge asset mapping
if [ "$USE_ATTACKFORGE" = true ]; then
    fetch_existing_assets
    declare -a NEW_DOMAINS
    for domain in "${ALL_DOMAINS[@]}"; do
        if [[ -z "${ASSET_MAP[$domain]}" ]]; then
            NEW_DOMAINS+=("$domain")
            log_info "Domain $domain needs to be created in AttackForge"
        else
            log_info "Domain $domain already exists with ID: ${ASSET_MAP[$domain]}"
        fi
    done
    if [ ${#NEW_DOMAINS[@]} -gt 0 ]; then
        log_info "Creating ${#NEW_DOMAINS[@]} new assets in AttackForge"
        domains_json=$(printf '%s\n' "${NEW_DOMAINS[@]}" | jq -R . | jq -s .)
        create_scope_assets "$domains_json"
    else
        log_info "No new assets need to be created"
    fi
else
    declare -A ASSET_MAP
fi

# Get a sorted list of primary domains
primary_list=($(for key in "${!groups[@]}"; do echo "$key"; done | sort))

# For each primary group, sort the domains and print accordingly.
for primary in "${primary_list[@]}"; do
    # Get the list of domains for this primary and sort them alphabetically.
    IFS=$'\n' read -rd '' -a domain_arr <<< "$(echo -e "${groups[$primary]}" | sort)"

    # Flag to indicate if we've printed a header for this group.
    header_printed=false

    # If the primary domain is present in the array, print that first (unindented).
    # Otherwise, print the first element as the header.
    for d in "${domain_arr[@]}"; do
        if [ "$d" == "$primary" ]; then
            # Print the primary domain first.
            header_domain="$d"
            header_printed=true
            break
        fi
    done
    if [ "$header_printed" = false ]; then
        header_domain="${domain_arr[0]}"
        # Remove it from the array so it won't be printed twice.
        domain_arr=("${domain_arr[@]:1}")
    else
        # Remove the header domain from the array.
        new_arr=()
        for d in "${domain_arr[@]}"; do
            if [ "$d" != "$primary" ]; then
                new_arr+=("$d")
            fi
        done
        domain_arr=("${new_arr[@]}")
    fi

    # Test the header domain (unindented)
    test_domain "$header_domain"

    # Then test the rest with indentation
    for d in "${domain_arr[@]}"; do
        test_domain "$d" "indent"
    done

    echo ""
done

echo -e "${CYAN}Checks completed.${NC}"

# Write JSON output
echo "$JSON_ARRAY" | jq '.' > "$JSON_OUTPUT" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[+] JSON output saved to: ${JSON_OUTPUT}${NC}"
    log_info "JSON output saved to: ${JSON_OUTPUT}"

    # Send findings to AttackForge if integration is enabled
    if [ "$USE_ATTACKFORGE" = true ]; then
        echo -e "${CYAN}[*] Calling send_vulnerabilities_to_attackforge...${NC}"
        send_vulnerabilities_to_attackforge
        echo -e "${CYAN}[+] Finished send_vulnerabilities_to_attackforge.${NC}"
    fi
else
    log_error "Failed to write JSON output"
    echo -e "${RED}[-] Failed to write JSON output${NC}"
fi

echo -e "${CYAN}Checks completed.${NC}"

#!/bin/bash
# Usage: ./mailSecurityChecker.sh domains.txt
# Enhanced Mail Security Checker with AttackForge integration
#
# JSON results are always written to: ./Results/mailSecurityChkr.json
# This is the canonical output for integration and reporting.

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

# Optionally source AttackForge integration if present
if [ -f "./attackforgeIntegration.sh" ]; then
    source ./attackforgeIntegration.sh
    USE_ATTACKFORGE=true
    echo -e "${CYAN}[i] AttackForge integration enabled.${NC}"
else
    USE_ATTACKFORGE=false
    echo -e "${YELLOW}[i] AttackForge integration not available. Running standalone.${NC}"
fi

# Global variables for system info
HOSTNAME=$(hostname)
# Configuration

# Global variables for system info
HOSTNAME=$(hostname)
EXTERNAL_IP=$(curl -s checkip.amazonaws.com 2>/dev/null || echo "Unable to retrieve")
TIMESTAMP=$(date +"%Y-%m-%d-%H%M")
PROJECT_ID=""
SCRIPT_NAME="mailSecurityChecker"

# Create the Results directory and logs subdirectory if they don't exist
RESULTS_DIR="./Results"
LOGS_DIR="$RESULTS_DIR/logs"
mkdir -p "$RESULTS_DIR"
mkdir -p "$LOGS_DIR"

# Error log file
ERROR_LOG="$LOGS_DIR/Error_Log_${TIMESTAMP}.txt"

# Initialize error log with header
echo "=== Mail Security Checker Error Log ===" > "$ERROR_LOG"
echo "Started: $(date)" >> "$ERROR_LOG"
echo "Hostname: $HOSTNAME" >> "$ERROR_LOG"
echo "External IP: $EXTERNAL_IP" >> "$ERROR_LOG"
echo "========================================" >> "$ERROR_LOG"
echo "" >> "$ERROR_LOG"

# JSON output file (static for AttackForge integration)
# The JSON results will always be saved to ./Results/mailSecurityChkr.json
JSON_OUTPUT="$RESULTS_DIR/mailSecurityChkr.json"
JSON_ARRAY="[]"

# Function to log errors
log_error() {
    local error_msg="$1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] ERROR: $error_msg" >> "$ERROR_LOG"
    echo -e "${RED}[ERROR] $error_msg${NC}" >&2
}

# Function to log info
log_info() {
    local info_msg="$1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] INFO: $info_msg" >> "$ERROR_LOG"
}

# Function to add entries to JSON output
add_to_json() {
    local domain="$1"
    local asset_id="$2"
    local record_type="$3"
    local found_status="$4"
    local content="$5"
    local warnings="$6"
    
    # Log what we're adding
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
    
    # Log successful addition to JSON
    log_info "Successfully added $record_type entry for $domain to JSON"
}

# Function to display logo
print_logo() {
    echo -e "${PURPLE}"
    figlet "Mail Security Chkr" 2>/dev/null || echo "Mail Security Chkr"
    echo -e "${NC}"
    echo -e "${BLUE}${BOLD}Tantalum Labs 2025${NC}"
    echo -e "${YELLOW}${ITALIC}https://tantalumlabs.io${NC}"
    echo ""
}

# Main script execution starts here
if [ $# -ne 1 ]; then
    echo -e "${CYAN}Usage:${NC} $0 <domain_list.txt>"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo -e "${RED}Error:${NC} File '$1' not found!"
    log_error "Input file '$1' not found!"
    exit 1
fi

print_logo

log_info "Script started with input file: $1"

# Check for projectID.txt and setup AttackForge integration
if [ "$USE_ATTACKFORGE" = true ]; then
    echo -e "${CYAN}[*] Calling check_project_setup...${NC}"
    check_project_setup
    echo -e "${CYAN}[+] Finished check_project_setup. USE_ATTACKFORGE=$USE_ATTACKFORGE${NC}"
fi

# Read all domains first
declare -a ALL_DOMAINS
while IFS= read -r domain || [ -n "$domain" ]; do
    domain=$(echo "$domain" | xargs)
    if [[ -n "$domain" ]] && [[ ! "$domain" =~ ^# ]]; then
        ALL_DOMAINS+=("$domain")
    fi
done < "$1"

log_info "Found ${#ALL_DOMAINS[@]} domains to process"

# If AttackForge is enabled, check which domains need to be created
if [ "$USE_ATTACKFORGE" = true ]; then
    echo -e "${CYAN}[*] Calling fetch_existing_assets...${NC}"
    # Fetch existing assets
    fetch_existing_assets
    echo -e "${CYAN}[+] Finished fetch_existing_assets.${NC}"

    # Debug: log current asset map
    for domain in "${!ASSET_MAP[@]}"; do
        log_info "Asset map contains: $domain -> ${ASSET_MAP[$domain]}"
    done

    # Find domains that need to be created
    declare -a NEW_DOMAINS
    for domain in "${ALL_DOMAINS[@]}"; do
        if [[ -z "${ASSET_MAP[$domain]}" ]]; then
            NEW_DOMAINS+=("$domain")
            log_info "Domain $domain needs to be created in AttackForge"
        else
            log_info "Domain $domain already exists with ID: ${ASSET_MAP[$domain]}"
        fi
    done

    # Create new assets if needed
    if [ ${#NEW_DOMAINS[@]} -gt 0 ]; then
        log_info "Creating ${#NEW_DOMAINS[@]} new assets in AttackForge"
        # Convert array to JSON array string
        domains_json=$(printf '%s\n' "${NEW_DOMAINS[@]}" | jq -R . | jq -s .)
        echo -e "${CYAN}[*] Calling create_scope_assets...${NC}"
        create_scope_assets "$domains_json"
        echo -e "${CYAN}[+] Finished create_scope_assets.${NC}"
    else
        log_info "No new assets need to be created"
    fi
else
    # If not using AttackForge, initialize ASSET_MAP as empty associative array for compatibility
    declare -A ASSET_MAP
fi

# Process each domain
for domain in "${ALL_DOMAINS[@]}"; do
    log_info "Processing domain: $domain"
    
    DOMAIN_DIR="$RESULTS_DIR/$domain"
    mkdir -p "$DOMAIN_DIR"
    OUTPUT_FILE="$DOMAIN_DIR/mailsecurity.txt"
    
    # Get asset ID for this domain
    asset_id="${ASSET_MAP[$domain]:-null}"
    log_info "Domain $domain has asset_id: $asset_id"
    
    # Open output file for writing using file descriptor 3
    exec 3>"$OUTPUT_FILE"
    
    echo -e "${BLUE}${BOLD}==========================================">&3
    echo -e "    Mail Security Assessment for: ${domain}">&3
    echo -e "==========================================${NC}">&3
    echo "">&3
    
    # 1. MX Records
    echo -e "${BLUE}${BOLD}[MX] MX Records${NC}">&3
    mx_output=$(dig MX "$domain" +noall +answer 2>&1)
    if [[ -n "$mx_output" ]] && [[ ! "$mx_output" =~ "no servers could be reached" ]]; then
        echo -e "${CYAN}$mx_output${NC}">&3
        echo -e "[+] Overall MX Records: ${GREEN}${BOLD}OK${NC}">&3
        add_to_json "$domain" "$asset_id" "MX" "found" "$mx_output" ""
    else
        echo -e "[~] No MX records found for ${YELLOW}${BOLD}${domain}.${NC}">&3
        echo -e "[~] Overall MX Records: ${YELLOW}${BOLD}MISSING${NC}">&3
        add_to_json "$domain" "$asset_id" "MX" "not-found" "" "No MX records found"
    fi
    echo "">&3
    
    # 2. SPF Record
    echo -e "${BLUE}${BOLD}[SPF] SPF Records${NC}">&3
    spf_output=$(dig TXT "$domain" +noall +answer 2>&1 | grep -Fi "v=spf1")
    if [[ -n "$spf_output" ]] && [[ ! "$spf_output" =~ "no servers could be reached" ]]; then
        echo -e "${CYAN}$spf_output${NC}">&3
        echo -e "[+] Overall SPF Record: ${GREEN}${BOLD}FOUND${NC}">&3
        add_to_json "$domain" "$asset_id" "SPF" "found" "$spf_output" ""
    else
        echo -e "[-] No SPF record found for ${YELLOW}${domain}.${NC}">&3
        echo -e "[-] Overall SPF Record: ${RED}${BOLD}MISSING${NC}">&3
        add_to_json "$domain" "$asset_id" "SPF" "not-found" "" "No SPF record found"
    fi
    echo "">&3
    
    # 3. DKIM Records
    echo -e "${BLUE}${BOLD}[DKIM] DKIM Records${NC}">&3
    # DKIM check variables - avoid local declarations for compatibility
    selectors=("default" "selector1" "selector2" "google" "k1" "k2" "k3" "mandrill")
    dkim_found=0
    dkim_records=""
    dkim_warnings=""
    
    for selector in "${selectors[@]}"; do
        # DKIM selector check
        dkim_record=$(dig TXT "${selector}._domainkey.${domain}" +noall +answer 2>&1)
        if [[ -n "$dkim_record" ]] && [[ ! "$dkim_record" =~ "no servers could be reached" ]]; then
            echo -e "[+] DKIM (${selector}): ${GREEN}${BOLD}FOUND${NC}">&3
            echo -e "${CYAN}$dkim_record${NC}">&3
            echo "">&3
            dkim_records+="$dkim_record\n"
            dkim_found=1
        fi
    done
    
    if [ $dkim_found -eq 0 ]; then
        echo -e "[-] DKIM: ${RED}${BOLD}MISSING${NC} - No records for common selectors${NC}">&3
        echo "">&3
        dkim_warnings="No DKIM records found for common selectors"
        add_to_json "$domain" "$asset_id" "DKIM" "not-found" "" "$dkim_warnings"
        echo -e "[-] Overall DKIM Records: ${RED}${BOLD}MISSING${NC}">&3
    else
        add_to_json "$domain" "$asset_id" "DKIM" "found" "$dkim_records" ""
        echo -e "[+] Overall DKIM Records: ${GREEN}${BOLD}FOUND${NC}">&3
    fi
    echo "">&3
    
    # 4. DMARC Record
    echo -e "${BLUE}${BOLD}[DMARC] DMARC Record${NC}">&3
    dmarc=$(dig TXT _dmarc."$domain" +short 2>&1 | grep -Fi "v=DMARC1")
    
    if [[ -n "$dmarc" ]] && [[ ! "$dmarc" =~ "no servers could be reached" ]]; then
        echo -e "[+] DMARC: ${GREEN}${BOLD}FOUND${NC}">&3
        echo -e "${CYAN}$dmarc${NC}">&3
        echo "">&3
        add_to_json "$domain" "$asset_id" "DMARC" "found" "$dmarc" ""
        echo -e "[+] Overall DMARC: ${GREEN}${BOLD}FOUND${NC}">&3
    else
        echo -e "[-] DMARC: ${RED}${BOLD}MISSING${NC} - No DMARC record found${NC}">&3
        echo "">&3
        add_to_json "$domain" "$asset_id" "DMARC" "not-found" "" "No DMARC record found"
        echo -e "[-] Overall DMARC: ${RED}${BOLD}MISSING${NC}">&3
    fi
    echo "">&3

    # 4.5. CAA Record
    echo -e "${BLUE}${BOLD}[CAA] CAA Records${NC}">&3
    caa_output=$(dig CAA "$domain" +noall +answer 2>&1)
    if [[ -n "$caa_output" ]] && [[ ! "$caa_output" =~ "no servers could be reached" ]]; then
        echo -e "${CYAN}$caa_output${NC}">&3
        echo -e "[+] Overall CAA Records: ${GREEN}${BOLD}OK${NC}">&3
        add_to_json "$domain" "$asset_id" "CAA" "found" "$caa_output" ""
    else
        echo -e "[-] No CAA record found for ${YELLOW}${domain}${NC}">&3
        echo -e "[-] Overall CAA Records: ${RED}${BOLD}MISSING${NC}">&3
        add_to_json "$domain" "$asset_id" "CAA" "not-found" "" "No CAA record found"
    fi
    echo "">&3

    # 5. DNSSEC Test
    echo -e "${BLUE}${BOLD}[DNSSEC] DNSSEC Test${NC}">&3
    # DNSSEC check variables - avoid local declarations for compatibility
    dnssec_records=""
    dnssec_warnings=""
    dnssec_found=0
    
    echo -e "--- DNSKEY records ---">&3
    # DNSKEY check
    dnskey=$(dig DNSKEY "$domain" +short 2>&1)
    
    if [[ -n "$dnskey" ]] && [[ ! "$dnskey" =~ "no servers could be reached" ]]; then
        echo -e "[+] DNSKEY: ${GREEN}${BOLD}FOUND${NC}">&3
        echo -e "${CYAN}$dnskey${NC}">&3
        dnssec_records+="DNSKEY: $dnskey\n"
        dnssec_found=1
    else
        echo -e "[-] DNSKEY: ${RED}${BOLD}MISSING${NC} - ${YELLOW}DNSSEC likely disabled${NC}">&3
        dnssec_warnings+="DNSKEY missing - DNSSEC likely disabled\n"
    fi
    
    echo "">&3
    echo -e "--- DS records ---">&3
    # DS check
    ds=$(dig DS "$domain" +short 2>&1)
    
    if [[ -n "$ds" ]] && [[ ! "$ds" =~ "no servers could be reached" ]]; then
        echo -e "[+] DS: ${GREEN}${BOLD}FOUND${NC}">&3
        echo -e "${CYAN}$ds${NC}">&3
        dnssec_records+="DS: $ds\n"
        dnssec_found=1
    else
        echo -e "[-] DS: ${RED}${BOLD}MISSING${NC} - ${YELLOW}DNSSEC likely disabled${NC}">&3
        dnssec_warnings+="DS missing - DNSSEC likely disabled"
    fi
    
    echo "">&3
    
    # Fixed the comparison for dnssec_found
    if [ "$dnssec_found" -gt 0 ]; then
        add_to_json "$domain" "$asset_id" "DNSSEC" "found" "$dnssec_records" "$dnssec_warnings"
        echo -e "[+] Overall DNSSEC: ${GREEN}${BOLD}Enabled${NC}">&3
    else
        add_to_json "$domain" "$asset_id" "DNSSEC" "not-found" "" "$dnssec_warnings"
        echo -e "[-] Overall DNSSEC: ${RED}${BOLD}Disabled${NC}">&3
    fi
    echo "">&3
    
    # 6. DNS DANE Test
    echo -e "${BLUE}${BOLD}[DANE] DNS DANE Test (via MX hosts)${NC}">&3
    echo -e "DNS DANE Test:">&3
    
    # DANE check variables - avoid local declarations for compatibility
    dane_records=""
    dane_warnings=""
    dane_overall_found=0
    
    # Retrieve MX records
    mx_records=$(dig MX "$domain" +short 2>&1)
    
    if [[ -z "$mx_records" ]] || [[ "$mx_records" =~ "no servers could be reached" ]]; then
        echo -e "[~] ${YELLOW}${BOLD}No MX records found for ${domain}, skipping DNS DANE test.${NC}">&3
        dane_warnings="No MX records found - DNS DANE test skipped"
        add_to_json "$domain" "$asset_id" "DNS-DANE" "not-found" "" "$dane_warnings"
    else
        echo -e "[+] Found MX records:">&3
        echo -e "${BLUE}$mx_records${NC}">&3
        echo "">&3
        
        # DANE port array
        ports=(25 465 587)
        
        while IFS= read -r line; do
            # MX host extraction
            mx_host=$(echo "$line" | awk '{print $2}' | sed 's/\.$//')
            echo -e "MX host: ${CYAN}${BOLD}${mx_host}${NC}">&3
            found_tlsa=0
            
            for port in "${ports[@]}"; do
                echo -e "  Checking TLSA on port ${port} (_${port}._tcp.${mx_host}):">&3
                # TLSA output
                tlsa_output=$(dig TLSA "_${port}._tcp.${mx_host}" +noall +answer 2>&1)
                
                if [[ -n "$tlsa_output" ]] && [[ ! "$tlsa_output" =~ "no servers could be reached" ]]; then
                    echo -e "  [+] TLSA ${GREEN}${BOLD}FOUND${NC} for port ${port}:">&3
                    echo -e "  ${CYAN}$tlsa_output${NC}">&3
                    dane_records+="TLSA for ${mx_host}:${port}: $tlsa_output\n"
                    found_tlsa=1
                else
                    echo -e "  [-] TLSA record ${YELLOW}${BOLD}NOT FOUND${NC} for port ${port}.">&3
                    dane_warnings+="TLSA not found for ${mx_host}:${port}\n"
                fi
                echo "">&3
            done
            
            if [ $found_tlsa -eq 1 ]; then
                echo -e "Overall DNS DANE for ${mx_host}: ${GREEN}${BOLD}Enabled${NC}">&3
                dane_overall_found=1
            else
                echo -e "Overall DNS DANE for ${mx_host}: ${RED}${BOLD}Not enabled${NC}">&3
            fi
            echo -e "-------------------">&3
        done <<< "$mx_records"
        
        if [ $dane_overall_found -eq 1 ]; then
            echo -e "Overall DNS DANE for ${domain}: ${GREEN}${BOLD}Enabled${NC}">&3
            add_to_json "$domain" "$asset_id" "DNS-DANE" "found" "$dane_records" "$dane_warnings"
        else
            echo -e "Overall DNS DANE for ${domain}: ${RED}${BOLD}Not enabled${NC}">&3
            add_to_json "$domain" "$asset_id" "DNS-DANE" "not-found" "" "$dane_warnings"
        fi
    fi
    echo "">&3
    
    # 7. MTA-STS Policy
    echo -e "${BLUE}${BOLD}[MTA-STS] MTA-STS Policy${NC}">&3
    
    # First check for _mta-sts TXT record
    mta_sts_txt_record=$(dig TXT "_mta-sts.${domain}" +short 2>&1 | tr -d '"')
    
    if [[ -n "$mta_sts_txt_record" ]] && [[ ! "$mta_sts_txt_record" =~ "no servers could be reached" ]]; then
        if [[ "$mta_sts_txt_record" =~ v=STSv1 ]]; then
            echo -e "[+] TXT Record: _mta-sts record exists and contains v=STSv1 - ${GREEN}${BOLD}OK${NC}">&3
            echo -e "${CYAN}$mta_sts_txt_record${NC}">&3
            
            # Now fetch the policy file
            mta_sts_url="https://mta-sts.${domain}/.well-known/mta-sts.txt"
            echo -e "Fetching ${CYAN}$mta_sts_url${NC}">&3
            mta_sts_response=$(curl -ks -w "HTTPSTATUS:%{http_code}" "$mta_sts_url" 2>&1)
            
            # Extract HTTP status and body
            http_status=$(echo "$mta_sts_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
            policy_content=$(echo "$mta_sts_response" | sed 's/HTTPSTATUS:[0-9]*$//')
            
            if [[ "$http_status" == "200" ]] && [[ -n "$policy_content" ]] && [[ "$policy_content" =~ version.*STSv1 ]]; then
                echo -e "[+] Policy File: Valid MTA-STS policy found - ${GREEN}${BOLD}OK${NC}">&3
                echo -e "${CYAN}$policy_content${NC}">&3
                echo -e "[+] Overall MTA-STS: ${GREEN}${BOLD}Enabled${NC}">&3
                add_to_json "$domain" "$asset_id" "MTA-STS" "found" "$policy_content" ""
            else
                echo -e "[-] Policy File: Invalid or missing MTA-STS policy (HTTP $http_status) - ${RED}${BOLD}INVALID${NC}">&3
                if [[ -n "$policy_content" ]]; then
                    echo -e "${YELLOW}Response: $policy_content${NC}">&3
                fi
                echo -e "[-] Overall MTA-STS: ${RED}${BOLD}MISSING${NC}">&3
                add_to_json "$domain" "$asset_id" "MTA-STS" "not-found" "" "Policy file invalid or missing (HTTP $http_status)"
            fi
        else
            echo -e "[-] TXT Record: _mta-sts record found but missing or invalid version - ${RED}${BOLD}INVALID${NC}">&3
            echo -e "${YELLOW}Found: $mta_sts_txt_record${NC}">&3
            echo -e "[-] Overall MTA-STS: ${RED}${BOLD}MISSING${NC}">&3
            add_to_json "$domain" "$asset_id" "MTA-STS" "not-found" "" "_mta-sts TXT record missing v=STSv1"
        fi
    else
        echo -e "[-] TXT Record: _mta-sts record missing - ${RED}${BOLD}MISSING${NC}">&3
        echo -e "[-] Overall MTA-STS: ${RED}${BOLD}MISSING${NC}">&3
        add_to_json "$domain" "$asset_id" "MTA-STS" "not-found" "" "_mta-sts TXT record missing"
    fi
    echo "">&3

    # 8. WHOIS Domain Status
    echo -e "${BLUE}${BOLD}[WHOIS] Domain Status${NC}">&3
    whois_output=$(whois "$domain" 2>&1)
    status_lines=$(echo "$whois_output" | grep -iE 'status:' | grep -iE 'clientTransferProhibited|clientDeleteProhibited|clientUpdateProhibited' | sort -u)
    found_transfer=$(echo "$status_lines" | grep -i 'clientTransferProhibited')
    found_delete=$(echo "$status_lines" | grep -i 'clientDeleteProhibited')
    found_update=$(echo "$status_lines" | grep -i 'clientUpdateProhibited')
    missing_statuses=()
    whois_status_content=""
    if [[ -n "$found_transfer" ]]; then
        echo -e "clientTransferProhibited: ${GREEN}${BOLD}FOUND${NC}">&3
        whois_status_content+="clientTransferProhibited: FOUND\n"
    else
        echo -e "clientTransferProhibited: ${RED}${BOLD}MISSING${NC}">&3
        whois_status_content+="clientTransferProhibited: MISSING\n"
        missing_statuses+=("clientTransferProhibited")
    fi
    if [[ -n "$found_delete" ]]; then
        echo -e "clientDeleteProhibited: ${GREEN}${BOLD}FOUND${NC}">&3
        whois_status_content+="clientDeleteProhibited: FOUND\n"
    else
        echo -e "clientDeleteProhibited: ${RED}${BOLD}MISSING${NC}">&3
        whois_status_content+="clientDeleteProhibited: MISSING\n"
        missing_statuses+=("clientDeleteProhibited")
    fi
    if [[ -n "$found_update" ]]; then
        echo -e "clientUpdateProhibited: ${GREEN}${BOLD}FOUND${NC}">&3
        whois_status_content+="clientUpdateProhibited: FOUND\n"
    else
        echo -e "clientUpdateProhibited: ${RED}${BOLD}MISSING${NC}">&3
        whois_status_content+="clientUpdateProhibited: MISSING\n"
        missing_statuses+=("clientUpdateProhibited")
    fi

    if [[ ${#missing_statuses[@]} -eq 0 ]]; then
        echo -e "[+] Overall WHOIS Domain Status: ${GREEN}${BOLD}OK${NC}">&3
        add_to_json "$domain" "$asset_id" "WHOIS-STATUS" "found" "$whois_status_content" ""
    else
        echo -e "[-] Overall WHOIS Domain Status: ${RED}${BOLD}PROBLEM${NC} (${missing_statuses[*]} missing)">&3
        add_to_json "$domain" "$asset_id" "WHOIS-STATUS" "problem" "$whois_status_content" "${missing_statuses[*]} missing"
    fi
    echo "">&3

    # Close the output file
    exec 3>&-
    
    echo -e "${YELLOW}[!] Assessment for ${domain} completed. Results saved to ${OUTPUT_FILE}${NC}"
    echo ""
done

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

# Add completion info to error log
echo "" >> "$ERROR_LOG"
echo "========================================" >> "$ERROR_LOG"
echo "Completed: $(date)" >> "$ERROR_LOG"
echo "Total domains processed: ${#ALL_DOMAINS[@]}" >> "$ERROR_LOG"

# Always show the error log location
echo -e "${CYAN}[i] Log file saved to: ${ERROR_LOG}${NC}"

echo -e "${GREEN}${BOLD}[] All assessments completed!${NC}" 

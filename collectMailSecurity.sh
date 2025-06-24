#!/bin/bash
# Usage: ./mailSecurityChecker.sh domains.txt

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

print_logo() {
    echo -e "${PURPLE}"
    figlet "Mail Security Chkr"
    echo -e "${NC}"
    echo -e "${BLUE}${BOLD}Tantalum Labs 2025${NC}"
    echo -e "${YELLOW}${ITALIC}https://tantalumlabs.io${NC}"
    echo ""
}

# Create the Results directory if it doesn't exist
RESULTS_DIR="./Results"
mkdir -p "$RESULTS_DIR"

validate_spf_tool() {
    local domain="$1"
    local result=""
    # Use dummy parameters for testing; adjust as needed.
    local output
    output=$(spfquery -ip 8.8.8.8 -sender test@"$domain" -helo mail."$domain" 2>&1)
    if echo "$output" | grep -qi "pass"; then
        result="${GREEN}[+] SPF Tool Validation: PASS${NC}"
    else
        result="${RED}[-] SPF Tool Validation: FAIL${NC}\nOutput: $output"
    fi
    echo -e "$result"
}

validate_dmarc_tool() {
    local domain="$1"
    local result=""
    local output
    output=$(opendmarc-check -d "$domain" 2>&1)
    if echo "$output" | grep -qi "pass"; then
        result="${GREEN}[+] DMARC Tool Validation: PASS${NC}"
    else
        result="${RED}[-] DMARC Tool Validation: FAIL${NC}\nOutput: $output"
    fi
    echo -e "$result"
}

validate_dkim_tool() {
    local domain="$1"
    local selector="default"
    local result=""
    # Create a temporary minimal email message.
    local temp_email="/tmp/dkim_test_email.eml"
    cat > "$temp_email" <<EOF
From: test@$domain
To: test@$domain
Subject: DKIM Test
DKIM-Signature: v=1; a=rsa-sha256; d=$domain; s=$selector; c=relaxed/simple; q=dns/txt; t=0; bh=; h=From:To:Subject; b=
EOF
    local output
    output=$(dkimverify < "$temp_email" 2>&1)
    if echo "$output" | grep -qi "pass"; then
        result="${GREEN}[+] DKIM Tool Validation: PASS${NC}"
    else
        result="${RED}[-] DKIM Tool Validation: FAIL${NC}\nOutput: $output"
    fi
    rm -f "$temp_email"
    echo -e "$result"
}

# Function to perform DKIM lookup with common selectors
check_dkim() {
    local domain="$1"
    local selectors=("default" "selector1" "selector2", "google", "k1", "k2", "k3", "mandrill")
    local found_any=0
    local result=""
    for selector in "${selectors[@]}"; do
        local dkim_record
        dkim_record=$(dig TXT "${selector}._domainkey.${domain}" +noall +answer)
        if [[ -n "$dkim_record" ]]; then
            result+="[+] DKIM (${selector}): ${GREEN}${BOLD}FOUND${NC}\n"
            result+="${CYAN}$dkim_record${NC}\n\n"
            found_any=1
        fi
    done
    if [ $found_any -eq 0 ]; then
        result+="[-] DKIM: ${RED}${BOLD}MISSING${NC} - No records for common selectors (default, selector1, selector2)${NC}\n\n"
    fi
    echo -e "$result"
}

# Function to perform a DMARC test
check_dmarc() {
    local domain="$1"
    local result=""
    local dmarc
    dmarc=$(dig TXT _dmarc."$domain" +short | grep -Fi "v=DMARC1")
    if [[ -n "$dmarc" ]]; then
        result+="[+] DMARC: ${GREEN}${BOLD}FOUND${NC}\n"
        result+="${CYAN}$dmarc${NC}\n\n"
    else
        result+="[-] DMARC: ${RED}${BOLD}MISSING${NC} - No DMARC record found${NC}\n\n"
    fi
    echo -e "$result"
}

# Function to perform a DNSSEC test for a domain
check_dnssec() {
    local domain="$1"
    local result=""
    result+="--- DNSKEY records ---\n"
    local dnskey
    dnskey=$(dig DNSKEY "$domain" +short)
    if [[ -n "$dnskey" ]]; then
        result+="[+] DNSKEY: ${GREEN}${BOLD}FOUND${NC}\n${CYAN}$dnskey${NC}\n"
    else
        result+="[-] DNSKEY: ${RED}${BOLD}MISSING${NC} - ${YELLOW}DNSSEC likely disabled${NC}\n"
    fi
    result+="\n--- DS records ---\n"
    local ds
    ds=$(dig DS "$domain" +short)
    if [[ -n "$ds" ]]; then
        result+="[+] DS: ${GREEN}${BOLD}FOUND${NC}\n${CYAN}$ds${NC}\n"
    else
        result+="[-] DS: ${RED}${BOLD}MISSING${NC} - ${YELLOW}DNSSEC likely disabled${NC}\n"
    fi
    result+="\n"
    echo -e "$result"
}

# Function to perform a universal DNS DANE test using each MX record
# and querying for TLSA records on common SMTP ports.
check_dane() {
    local domain="$1"
    local ports=(25 465 587)
    local result=""
    local overall_found=0
    result+="DNS DANE Test:\n"
    # Retrieve MX records in a simplified format
    local mx_records
    mx_records=$(dig MX "$domain" +short)
    if [[ -z "$mx_records" ]]; then
         result+="[~] ${YELLOW}${BOLD}No MX records found for ${domain}, skipping DNS DANE test.${NC}\n"
         echo -e "$result"
         return
    fi
    result+="[+] Found MX records:\n${BLUE}$mx_records${NC}\n\n"
    while IFS= read -r line; do
         local mx_host
         mx_host=$(echo "$line" | awk '{print $2}' | sed 's/\.$//')
         result+="MX host: ${CYAN}${BOLD}${mx_host}${NC}\n"
         local found_tlsa=0
         for port in "${ports[@]}"; do
              result+="  Checking TLSA on port ${port} (_${port}._tcp.${mx_host}):\n"
              local tlsa_output
              tlsa_output=$(dig TLSA "_${port}._tcp.${mx_host}" +noall +answer)
              if [[ -n "$tlsa_output" ]]; then
                   result+="  [+] TLSA ${GREEN}${BOLD}FOUND${NC} for port ${port}:\n  ${CYAN}$tlsa_output${NC}\n"
                   found_tlsa=1
              else
                   result+="  [-] TLSA record ${YELLOW}${BOLD}NOT FOUND${NC} for port ${port}.\n"
              fi
              result+="\n"
         done
         if [ $found_tlsa -eq 1 ]; then
             result+="Overall DNS DANE for ${mx_host}: ${GREEN}${BOLD}Enabled${NC}\n"
             overall_found=1
         else
             result+="Overall DNS DANE for ${mx_host}: ${RED}${BOLD}Not enabled${NC}\n"
         fi
         result+="-------------------\n"
    done <<< "$mx_records"
    if [ $overall_found -eq 1 ]; then
         result+="Overall DNS DANE for ${domain}: ${GREEN}${BOLD}Enabled${NC}\n"
    else
         result+="Overall DNS DANE for ${domain}: ${RED}${BOLD}Not enabled${NC}\n"
    fi
    echo -e "$result"
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

while IFS= read -r domain || [ -n "$domain" ]; do
    domain=$(echo "$domain" | xargs)
    if [[ -z "$domain" || "$domain" =~ ^# ]]; then
        continue
    fi

    DOMAIN_DIR="$RESULTS_DIR/$domain"
    mkdir -p "$DOMAIN_DIR"
    OUTPUT_FILE="$DOMAIN_DIR/mailsecurity.txt"

    {
        echo -e "${BLUE}${BOLD}=========================================="
        echo -e "    Mail Security Assessment for: ${domain}"
        echo -e "==========================================${NC}"
        echo ""

        # 1. MX Records
        echo -e "${BLUE}${BOLD}[MX] MX Records${NC}"
        mx_output=$(dig MX "$domain" +noall +answer)
        if [[ -n "$mx_output" ]]; then
            echo -e "${CYAN}$mx_output${NC}"
            echo -e "[+] Overall MX Records: ${GREEN}${BOLD}OK${NC}"
        else
            echo -e "[~] No MX records found for ${YELLOW}${BOLD}${domain}.${NC}"
            echo -e "[~] Overall MX Records: ${YELLOW}${BOLD}MISSING${NC}"
        fi
        echo ""

        # 2. SPF Record
        echo -e "${BLUE}${BOLD}[SPF] SPF Record${NC}"
        spf_output=$(dig TXT "$domain" +noall +answer | grep -Fi "v=spf1")
        if [[ -n "$spf_output" ]]; then
            echo -e "${CYAN}$spf_output${NC}"
            echo -e "[+] Overall SPF Record: ${GREEN}${BOLD}FOUND${NC}"
            #echo -e "$(validate_spf_tool "$domain")"
        else
            echo -e "[-] No SPF record found for ${YELLOW}${domain}.${NC}"
            echo -e "[-] Overall SPF Record: ${RED}${BOLD}MISSING${NC}"
        fi
        echo ""

        # 3. DKIM Records
        echo -e "${BLUE}${BOLD}[DKIM] DKIM Records${NC}"
        dkim_results=$(check_dkim "$domain")
        echo -e "$dkim_results"
        #echo -e "$(validate_dkim_tool "$domain")"
        if echo -e "$dkim_results" | grep -Fqi "MISSING"; then
            echo -e "[-] Overall DKIM Records: ${RED}${BOLD}MISSING${NC}"
        else
            echo -e "[+] Overall DKIM Records: ${GREEN}${BOLD}FOUND${NC}"
        fi
        echo ""

        # 4. DMARC Record
        echo -e "${BLUE}${BOLD}[DMARC] DMARC Record${NC}"
        dmarc_results=$(check_dmarc "$domain")
        echo -e "$dmarc_results"
        #echo -e "$(validate_dmarc_tool "$domain")"
        if echo -e "$dmarc_results" | grep -Fqi "MISSING"; then
            echo -e "[-] Overall DMARC: ${RED}${BOLD}MISSING${NC}"
        else
            echo -e "[+] Overall DMARC: ${GREEN}${BOLD}FOUND${NC}"
        fi
        echo ""

        # 5. DNSSEC Test
        echo -e "${BLUE}${BOLD}[DNSSEC] DNSSEC Test${NC}"
        dnssec_results=$(check_dnssec "$domain")
        echo -e "$dnssec_results"
        if echo -e "$dnssec_results" | grep -Fqi "MISSING"; then
            echo -e "[-] Overall DNSSEC: ${RED}${BOLD}Disabled${NC}"
        else
            echo -e "[+] Overall DNSSEC: ${GREEN}${BOLD}Enabled${NC}"
        fi
        echo ""

        # 6. DNS DANE Test
        echo -e "${BLUE}${BOLD}[DANE] DNS DANE Test (via MX hosts)${NC}"
        dane_results=$(check_dane "$domain")
        echo -e "$dane_results"
        echo ""

        # 7. MTA-STS Policy
        echo -e "${BLUE}${BOLD}[MTA-STS] MTA-STS Policy${NC}"
        mta_sts_url="https://mta-sts.${domain}/.well-known/mta-sts.txt"
        echo -e "Fetching ${CYAN}$mta_sts_url${NC}"
        mta_sts_output=$(curl -ks "$mta_sts_url")
        if [[ -n "$mta_sts_output" ]]; then
            echo -e "${CYAN}$mta_sts_output${NC}"
            echo -e "[+] Overall MTA-STS: ${GREEN}${BOLD}Enabled${NC}"
        else
            echo -e "[-] No MTA-STS policy found for ${YELLOW}${BOLD}${domain}.${NC}"
            echo -e "[-] Overall MTA-STS: ${RED}${BOLD}MISSING${NC}"
        fi
        echo ""

    } > "$OUTPUT_FILE" 2>&1

    echo -e "${YELLOW}[!] Assessment for ${domain} completed. Results saved to ${OUTPUT_FILE}${NC}"
    echo ""
done < "$1"

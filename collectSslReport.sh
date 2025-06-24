#!/bin/bash
# Usage: ./check_tls_report.sh domains.txt

# ANSI color and style codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
ORANGE='\033[38;5;208m'
BOLD='\033[1m'
ITALIC='\033[3m'
NC='\033[0m'  # Reset

# Define lists of insecure ciphers.
# For TLS1.2, insecure ciphers (those that do NOT use ephemeral key exchange)
insecure_tls12_ciphers=(
  "TLS_RSA_WITH_RC4_128_SHA"
  "TLS_RSA_WITH_RC4_128_MD5"
  "TLS_RSA_WITH_3DES_EDE_CBC_SHA"
  "TLS_RSA_WITH_AES_128_CBC_SHA"
  "TLS_RSA_WITH_AES_256_CBC_SHA"
  "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256"
  "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA"
  "TLS_ECDHE_ECDSA_WITH_AES_256_CCM"
  "TLS_ECDHE_ECDSA_WITH_AES_128_CCM_8"
  "TLS_ECDHE_ECDSA_WITH_AES_128_CCM"
  "TLS_ECDHE_ECDSA_WITH_ARIA_128_GCM_SHA256"
  "TLS_ECDHE_ECDSA_WITH_CAMELLIA_128_CBC_SHA256"
  "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA"
  "TLS_ECDHE_ECDSA_WITH_AES_256_CCM_8"
  "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256"
  "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA"
  "TLS_ECDHE_ECDSA_WITH_ARIA_256_GCM_SHA384"
  "TLS_ECDHE_ECDSA_WITH_CAMELLIA_256_CBC_SHA384"
  "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384"
  "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384"
  "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA"
  "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA"
  "TLS_RSA_WITH_AES_256_GCM_SHA384"
  "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA"
  "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA"
  "TLS_RSA_WITH_AES_128_GCM_SHA256"
  "TLS_RSA_WITH_AES_256_CBC_SHA256"
  "TLS_RSA_WITH_AES_128_CBC_SHA256"
  "TLS_RSA_WITH_AES_128_GCM_SHA256"
  "TLS_RSA_WITH_AES_256_GCM_SHA384"
)
# For TLS1.3, leave empty unless you want to flag something.
insecure_tls13_ciphers=()

# Global arrays for overall reporting (only for issues other than compliance)
vuln_cipher=()      # Insecure cipher issues (TLS1.2/1.3)
diffie_weak=()      # Diffie-Hellman weakness (DH key < 2048)
deprecated_ssl=()   # Deprecated protocols (SSLv2, SSLv3, TLS1.1 accepted)
poodle=()           # SSL 3.0 accepted (POODLE vulnerability)
beast=()            # TLS 1.0 accepted (BEAST vulnerability)
rc4_vuln=()         # RC4 cipher vulnerability
# Global array for compliance issues (recorded but not causing FAIL)
compliance_fail=()

print_logo() {
    echo -e "${PURPLE}"
    figlet "SSL Chkr"
    echo -e "${NC}"
    echo -e "${BLUE}${BOLD}Tantalum Labs 2025${NC}"
    echo -e "${YELLOW}${ITALIC}https://tantalumlabs.io${NC}"
    echo ""
}

# Function to extract the primary domain (assumes primary is the last two labels)
get_primary() {
    local domain="$1"
    IFS='.' read -ra parts <<< "$domain"
    local len=${#parts[@]}
    if [ "$len" -ge 2 ]; then
        echo "${parts[$len-2]}.${parts[$len-1]}"
    else
        echo "$domain"
    fi
}

# Function to test TLS configuration using sslyze and output per-domain results.
test_tls() {
    local domain="$1"
    local indent="$2"
    local vuln_indent="${indent}\t"
    local target="${domain}:443"
    
    # Run sslyze and capture its output (errors suppressed)
    local output
    output=$(sslyze "$target" 2>/dev/null)
    
    # Check for connection errors.
    if [ -z "$output" ] || echo "$output" | grep -qiE "ERROR:|timed out"; then
        echo -e "${indent}${YELLOW}[SKIPPED]${NC} ${CYAN}${domain}${NC} - No response / Connection error"
        return
    fi

    local other_vuln_count=0
    local details=()
    local compliance_details=()
    local cipher_secure=false

    # --- Helper function to add a detail if not already present ---
    add_detail() {
        local new_detail="$1"
        local i
        for i in "${details[@]}"; do
            if [[ "$i" == "$new_detail" ]]; then
                return 0
            fi
        done
        details+=("$new_detail")
    }

    # --- Check Deprecated Protocols ---
    local ssl2_block
    ssl2_block=$(echo "$output" | awk '/\* SSL 2\.0 Cipher Suites:/,/^$/')
    if [ -n "$ssl2_block" ]; then
        if ! echo "$ssl2_block" | grep -qi "rejected all cipher suites"; then
            deprecated_ssl+=("$domain")
            add_detail "SSL 2.0 accepted"
            ((other_vuln_count++))
        fi
    fi

    local ssl3_block
    ssl3_block=$(echo "$output" | awk '/\* SSL 3\.0 Cipher Suites:/,/^$/')
    if [ -n "$ssl3_block" ]; then
        if ! echo "$ssl3_block" | grep -qi "rejected all cipher suites"; then
            deprecated_ssl+=("$domain")
            poodle+=("$domain")
            add_detail "SSL 3.0 accepted (POODLE vulnerable)"
            ((other_vuln_count++))
        fi
    fi

    local tls10_block
    tls10_block=$(echo "$output" | awk '/\* TLS 1\.0 Cipher Suites:/,/^$/')
    if [ -n "$tls10_block" ]; then
        if ! echo "$tls10_block" | grep -qi "rejected all cipher suites"; then
            beast+=("$domain")
            add_detail "TLS 1.0 accepted (BEAST vulnerability)"
            ((other_vuln_count++))
        fi
    fi

    local tls11_block
    tls11_block=$(echo "$output" | awk '/\* TLS 1\.1 Cipher Suites:/,/^$/')
    if [ -n "$tls11_block" ]; then
        if ! echo "$tls11_block" | grep -qi "rejected all cipher suites"; then
            deprecated_ssl+=("$domain")
            add_detail "TLS 1.1 accepted"
            ((other_vuln_count++))
        fi
    fi

    # --- Check TLS 1.2 Cipher Suites ---
    # Use sed to capture lines between the TLS 1.2 header and the next section.
    local tls12_block
    tls12_block=$(echo "$output" | sed -n '/\* TLS 1\.2 Cipher Suites:/,/^\*/p' | sed '1d;$d')
    local accepted_tls12
    accepted_tls12=$(echo "$tls12_block" | grep -E "^\s*TLS_")
    if [ -n "$accepted_tls12" ]; then
        local insecure_found=0
        while IFS= read -r line; do
            for insecure in "${insecure_tls12_ciphers[@]}"; do
                if echo "$line" | grep -q "$insecure"; then
                    insecure_found=1
                    add_detail "Insecure TLS 1.2 cipher detected: $insecure"
                fi
            done
        done <<< "$accepted_tls12"
        if [ "$insecure_found" -eq 1 ]; then
            vuln_cipher+=("$domain")
            ((other_vuln_count++))
        else
            cipher_secure=true
        fi
    else
        # If no accepted TLS 1.2 ciphers, try TLS 1.3.
        local tls13_block
        tls13_block=$(echo "$output" | awk '/\* TLS 1\.3 Cipher Suites:/,/SCANS COMPLETED/')
        local accepted_tls13
        accepted_tls13=$(echo "$tls13_block" | awk '/The server accepted the following/{flag=1;next} flag && NF')
        if [ -n "$accepted_tls13" ]; then
            local insecure_found=0
            while IFS= read -r line; do
                for insecure in "${insecure_tls13_ciphers[@]}"; do
                    if echo "$line" | grep -q "$insecure"; then
                        insecure_found=1
                        add_detail "Insecure TLS 1.3 cipher detected: $insecure"
                    fi
                done
            done <<< "$accepted_tls13"
            if [ "$insecure_found" -eq 1 ]; then
                vuln_cipher+=("$domain")
                ((other_vuln_count++))
            else
                cipher_secure=true
            fi
        else
            vuln_cipher+=("$domain")
            add_detail "No acceptable TLS 1.2/1.3 ciphers"
            ((other_vuln_count++))
        fi
    fi

    # --- Check RC4 Cipher Vulnerability ---
    if echo "$output" | grep -qi "RC4"; then
        rc4_vuln+=("$domain")
        add_detail "RC4 cipher detected"
        ((other_vuln_count++))
    fi

    # --- Check Diffie-Hellman Key Exchange Weakness ---
    local dh_line
    dh_line=$(echo "$output" | grep -i -m1 "DH key")
    if [ -n "$dh_line" ]; then
        local key_size
        key_size=$(echo "$dh_line" | grep -o -E '[0-9]+' | head -n1)
        if [ -n "$key_size" ] && [ "$key_size" -lt 2048 ]; then
            diffie_weak+=("$domain")
            add_detail "Weak DH key (${key_size} bits)"
            ((other_vuln_count++))
        fi
    fi

    # --- Check Mozilla TLS Compliance (but do not cause FAIL) ---
    local compliance_line
    compliance_line=$(echo "$output" | grep -iE "FAILED - Not compliant")
    if [ -n "$compliance_line" ]; then
        compliance_fail+=("$domain")
        local comp_details
        comp_details=$(echo "$compliance_line" | sed 's/.*FAILED - //')
        # Only add if not already in compliance_details array.
        local already_added=false
        for c in "${compliance_details[@]}"; do
            if [[ "$c" == "$comp_details" ]]; then
                already_added=true
                break
            fi
        done
        if [ "$already_added" = false ]; then
            compliance_details+=("Compliance issues: ${comp_details}")
        fi
    fi

    # --- Final Output for the Domain ---
    if [ "$other_vuln_count" -gt 0 ]; then
        echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC}"
        for msg in "${details[@]}"; do
            echo -e "${vuln_indent}- ${msg}"
        done
        #for comp in "${compliance_details[@]}"; do
        #    echo -e "${vuln_indent}- ${comp}"
        #done
    else
        echo -e "${indent}${GREEN}[PASS]${NC} ${CYAN}${domain}${NC} - Secure TLS configuration"
        #if [ ${#compliance_details[@]} -gt 0 ]; then
        #    for comp in "${compliance_details[@]}"; do
        #        echo -e "${vuln_indent}- ${comp}"
        #    done
        #fi
    fi
}

# --- Overall Report Function ---
report_category() {
    local title="$1"
    shift
    local arr=("$@")
    if [ ${#arr[@]} -eq 0 ]; then
        echo -e "${GREEN}${title}:${NC} None"
    else
        local unique
        unique=$(printf "%s\n" "${arr[@]}" | sort -u | paste -sd ', ' -)
        echo -e "${RED}${title}:${NC} ${unique}"
    fi
}

# --- Main Script ---
if [ $# -ne 1 ]; then
    echo -e "${CYAN}Usage:${NC} $0 <domain_list.txt>"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo -e "${RED}Error:${NC} File '$1' not found!"
    exit 1
fi

print_logo

echo -e "${BOLD}${CYAN}Starting TLS configuration checks with sslyze...${NC}"
echo "-----------------------------------------"

# Group domains by primary domain.
declare -A groups
while IFS= read -r domain || [[ -n "$domain" ]]; do
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue
    primary=$(get_primary "$domain")
    groups["$primary"]+="$domain"$'\n'
done < "$1"

primary_list=($(for key in "${!groups[@]}"; do echo "$key"; done | sort))

first_group=1
for primary in "${primary_list[@]}"; do
    IFS=$'\n' read -rd '' -a domain_arr <<< "$(echo -e "${groups[$primary]}" | sort)"
    header_printed=false
    header_domain=""
    new_arr=()
    for d in "${domain_arr[@]}"; do
        if [ "$d" == "$primary" ]; then
            header_domain="$d"
            header_printed=true
        else
            new_arr+=("$d")
        fi
    done
    if [ "$header_printed" = false ]; then
        header_domain="${domain_arr[0]}"
        domain_arr=("${domain_arr[@]:1}")
    else
        tmp=()
        for d in "${domain_arr[@]}"; do
            if [ "$d" != "$primary" ]; then
                tmp+=("$d")
            fi
        done
        domain_arr=("${tmp[@]}")
    fi
    if [ $first_group -eq 0 ]; then
        echo ""
    else
        first_group=0
    fi
    test_tls "$header_domain" ""
    for d in "${domain_arr[@]}"; do
        test_tls "$d" $'\t'
    done
done

echo -e "\n${BOLD}${CYAN}Overall Report:${NC}"
echo "-----------------------------------------"
report_category "Vulnerable Cipher Suites" "${vuln_cipher[@]}"
report_category "Diffie-Hellman Weakness" "${diffie_weak[@]}"
report_category "Deprecated SSLv2/SSLv3 Protocols in Use" "${deprecated_ssl[@]}"
report_category "POODLE Vulnerability (SSL 3.0)" "${poodle[@]}"
report_category "BEAST Attack Vulnerability (TLS 1.0)" "${beast[@]}"
report_category "RC4 Cipher Vulnerability" "${rc4_vuln[@]}"
report_category "Compliance Issues" "${compliance_fail[@]}"
# New overall category for legacy protocols (SSL, TLS1.0, TLS1.1)
legacy_protocols=($(printf "%s\n" "${deprecated_ssl[@]}" "${beast[@]}" | sort -u))
report_category "Legacy Protocols" "${legacy_protocols[@]}"

echo -e "${BOLD}${CYAN}Checks completed.${NC}"

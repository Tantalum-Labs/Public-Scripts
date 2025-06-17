#!/bin/bash
# Usage: ./securityTxtChecker.sh domains.txt

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
    if [ "$http_code" == "200" ]; then
        content=$(curl -s --max-time 2 "$url")
    fi

    if [ "$http_code" == "200" ]; then
        # Check that content contains both required fields.
        if echo "$content" | grep -qi '^Contact:' && echo "$content" | grep -qi '^Policy:'; then
            echo -e "${indent}${GREEN}[PASS]${NC} ${CYAN}${domain}${NC} - valid security.txt found at ${url}"
        else
            echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC} - missing required fields or invalid"
        fi
    elif [ "$http_code" == "404" ]; then
        echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC} - security.txt not found (HTTP 404)"
    elif [ "$http_code" == "302" ]; then
        echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC} - Redirection (HTTP 302)"
    elif [ "$http_code" == "000" ]; then
        echo -e "${indent}${RED}[FAIL]${NC} ${CYAN}${domain}${NC} - No response"
    else
        echo -e "${indent}${YELLOW}[WARN]${NC} ${CYAN}${domain}${NC} - HTTP status code ${http_code}"
    fi
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
while IFS= read -r domain || [[ -n "$domain" ]]; do
    # Skip empty lines or comments.
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue
    primary=$(get_primary "$domain")
    # Append domain to the group (space-delimited list)
    groups["$primary"]+="$domain"$'\n'
done < "$1"

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

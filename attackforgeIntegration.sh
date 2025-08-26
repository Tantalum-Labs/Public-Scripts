# AttackForge Integration Include for mailSecurityChecker.sh

# Load AttackForge credentials and webhooks from JSON config
if [ ! -f "attackforge_config.json" ]; then
    echo "Error: attackforge_config.json not found!"
    exit 1
fi

MAKE_API_KEY=$(jq -r '.make_api_key' attackforge_config.json)
WEBHOOK_GET_ASSETS=$(jq -r '.webhook_get_assets' attackforge_config.json)
WEBHOOK_CREATE_ASSETS=$(jq -r '.webhook_create_assets' attackforge_config.json)
WEBHOOK_CREATE_VULNS=$(jq -r '.webhook_create_vulns' attackforge_config.json)

# AttackForge asset mapping
declare -A ASSET_MAP

# Function to check for projectID.txt and set up AttackForge integration
check_project_setup() {
    log_info "Checking for projectID.txt..."
    if [ -f "projectID.txt" ]; then
        PROJECT_ID=$(cat projectID.txt | xargs)
        if [[ -n "$PROJECT_ID" ]]; then
            USE_ATTACKFORGE=true
            echo -e "${GREEN}[+] Found projectID.txt: $PROJECT_ID${NC}"
            echo -e "${GREEN}[+] AttackForge integration enabled${NC}"
            log_info "Found projectID.txt with ID: $PROJECT_ID"
            log_info "AttackForge integration enabled"
        else
            log_error "projectID.txt is empty"
            echo -e "${YELLOW}[!] projectID.txt is empty - AttackForge integration disabled${NC}"
        fi
    else
        echo -e "${YELLOW}[!] No projectID.txt found - AttackForge integration disabled${NC}"
        log_info "No projectID.txt found - AttackForge integration disabled"
    fi
}

# Function to fetch existing scope assets from AttackForge
fetch_existing_assets() {
    if [ "$USE_ATTACKFORGE" = false ]; then
        return
    fi

    echo -e "${CYAN}[*] Fetching existing scope assets from AttackForge...${NC}"
    log_info "Fetching existing scope assets from AttackForge..."

    local response
    local http_status
    response=$(curl -s -w "HTTP_STATUS:%{http_code}" -X POST "$WEBHOOK_GET_ASSETS" \
        -H "Content-Type: application/json" \
        -H "x-make-apikey: $MAKE_API_KEY" \
        --data-raw "{\"project_id\": \"$PROJECT_ID\", \"hostname\": \"$HOSTNAME\", \"external_ip\": \"$EXTERNAL_IP\", \"script_name\": \"$SCRIPT_NAME\"}" \
        --compressed 2>&1)

    # Extract HTTP status code and response body
    http_status=$(echo "$response" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
    response_body=$(echo "$response" | sed 's/HTTP_STATUS:[0-9]*$//')

    if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
        log_info "AF-GET-scopeAssets webhook [HTTP $http_status]: $response_body"
        # Parse the response and populate ASSET_MAP
        while IFS=: read -r name id; do
            if [[ -n "$name" ]] && [[ -n "$id" ]]; then
                ASSET_MAP["$name"]="$id"
                log_info "Found existing asset: $name -> $id"
            fi
        done < <(echo "$response_body" | jq -r '.[] | "\(.name):\(.id)"' 2>/dev/null)

        echo -e "${GREEN}[+] Successfully fetched existing assets${NC}"
        log_info "Successfully fetched ${#ASSET_MAP[@]} existing assets"
    else
        log_error "AF-GET-scopeAssets webhook failed [HTTP $http_status]: $response_body"
    fi
}

# Function to create new scope assets in AttackForge
create_scope_assets() {
    if [ "$USE_ATTACKFORGE" = false ]; then
        return
    fi

    local domains_array="$1"

    echo -e "${CYAN}[*] Creating new scope assets in AttackForge...${NC}"
    log_info "Creating new scope assets in AttackForge..."

    local response
    local http_status
    response=$(curl -s -w "HTTP_STATUS:%{http_code}" -X POST "$WEBHOOK_CREATE_ASSETS" \
        -H "Content-Type: application/json" \
        -H "x-make-apikey: $MAKE_API_KEY" \
        --data-raw "{
            \"project_id\": \"$PROJECT_ID\",
            \"hostname\": \"$HOSTNAME\",
            \"external_ip\": \"$EXTERNAL_IP\",
            \"script_name\": \"$SCRIPT_NAME\",
            \"scopeassets_array\": $domains_array
        }" \
        --compressed 2>&1)

    # Extract HTTP status code and response body
    http_status=$(echo "$response" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
    response_body=$(echo "$response" | sed 's/HTTP_STATUS:[0-9]*$//')

    if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
        log_info "AF-Create-Project-ScopeAssets webhook [HTTP $http_status]: $response_body"
        while IFS=: read -r name id; do
            if [[ -n "$name" ]] && [[ -n "$id" ]]; then
                ASSET_MAP["$name"]="$id"
                log_info "Created new asset: $name -> $id"
            fi
        done < <(echo "$response_body" | jq -r '.data[] | "\(.name):\(.id)"' 2>/dev/null)

        echo -e "${GREEN}[+] Successfully created new assets${NC}"
        log_info "Successfully created new assets"
    else
        log_error "AF-Create-Project-ScopeAssets webhook failed [HTTP $http_status]: $response_body"
    fi
}

# Function to send JSON to AttackForge for vulnerability creation
send_vulnerabilities_to_attackforge() {
    if [ "$USE_ATTACKFORGE" = false ]; then
        return
    fi

    echo -e "${CYAN}[*] Sending findings to AttackForge for vulnerability creation...${NC}"
    log_info "Sending JSON findings to AttackForge webhook..."

    local response
    local http_status
    response=$(curl -s -w "HTTP_STATUS:%{http_code}" -X POST "$WEBHOOK_CREATE_VULNS" \
        -H "Content-Type: application/json" \
        -H "x-make-apikey: $MAKE_API_KEY" \
        --data-raw "{
            \"project_id\": \"$PROJECT_ID\",
            \"hostname\": \"$HOSTNAME\",
            \"external_ip\": \"$EXTERNAL_IP\",
            \"script_name\": \"$SCRIPT_NAME\",
            \"findings\": $JSON_ARRAY
        }" \
        --compressed 2>&1)

    # Extract HTTP status code and response body
    http_status=$(echo "$response" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
    response_body=$(echo "$response" | sed 's/HTTP_STATUS:[0-9]*$//')

    if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
        echo -e "${GREEN}[+] Successfully sent findings to AttackForge${NC}"
        log_info "AF-Create-Vulnerability webhook [HTTP $http_status]: $response_body"
    else
        log_error "AF-Create-Vulnerability webhook failed [HTTP $http_status]: $response_body"
        echo -e "${RED}[-] Failed to send findings to AttackForge${NC}"
    fi
}

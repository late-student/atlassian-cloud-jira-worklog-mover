#!/bin/bash

# ==========================================
# Jira Worklog Mover (Interactive Session v4)
# ==========================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global Variables
JIRA_BASE=""
EMAIL=""
API_TOKEN=""
CURRENT_ISSUE_KEY=""
LAST_WORKLOG_DATA="" 

# --- Utility Functions ---

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

is_exit_command() {
    local input="$1"
    input=$(echo "$input" | tr -d '[:space:]')
    input_lower=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$input_lower" == "q" || "$input_lower" == "quit" || "$input_lower" == "exit" || "$input_lower" == "back" || "$input_lower" == "esc" ]]; then
        return 0
    fi
    return 1
}

validate_connection() {
    print_header "Validating Connection"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -u "$EMAIL:$API_TOKEN" "$JIRA_BASE/rest/api/3/myself")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" == "200" ]; then
        USER_NAME=$(echo "$BODY" | jq -r '.displayName')
        echo -e "${GREEN}✓ Connected successfully as: $USER_NAME${NC}"
        return 0
    else
        echo -e "${RED}✗ Connection failed (Status: $HTTP_CODE)${NC}"
        echo "Error: $BODY"
        return 1
    fi
}

parse_issue_key() {
    local input="$1"
    if [[ "$input" =~ browse/([A-Z]+-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    if [[ "$input" =~ ^[A-Z]+-[0-9]+$ ]]; then
        echo "$input" | tr '[:lower:]' '[:upper:]'
        return
    fi

    local trimmed=$(echo "$input" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    echo "$trimmed"
}

fetch_worklogs() {
    local source_key="$1"
    print_header "Fetching Worklogs for $source_key"

    DATA=$(curl -s -u "$EMAIL:$API_TOKEN" "$JIRA_BASE/rest/api/3/issue/$source_key/worklog?maxResults=50")
    
    if echo "$DATA" | jq -e '.errorMessages' > /dev/null 2>&1; then
        ERR_MSG=$(echo "$DATA" | jq -r '.errorMessages[0] // "Unknown error"')
        echo -e "${RED}✗ ERROR: Jira returned error: $ERR_MSG${NC}"
        LAST_WORKLOG_DATA=""
        return 1
    fi

    COUNT=$(echo "$DATA" | jq '.total')

    if [ "$COUNT" -eq 0 ] || [ -z "$COUNT" ]; then
        echo -e "${YELLOW}No worklogs found on $source_key.${NC}"
        LAST_WORKLOG_DATA=""
        return 1
    fi

    LAST_WORKLOG_DATA="$DATA"

    echo -e "${GREEN}Found $COUNT worklog(s):${NC}"
    echo "----------------------------------------"
    
    for i in $(seq 0 $((COUNT - 1))); do
        WL_ID=$(echo "$DATA" | jq -r ".worklogs[$i].id")
        TIME_SPENT=$(echo "$DATA" | jq -r ".worklogs[$i].timeSpent")
        STARTED_DATE=$(echo "$DATA" | jq -r ".worklogs[$i].started" | cut -d'T' -f1)
        AUTHOR=$(echo "$DATA" | jq -r ".worklogs[$i].author.displayName // .worklogs[$i].author.name")
        
        COMMENT_RAW=$(echo "$DATA" | jq -r ".worklogs[$i].comment")
        if [[ "$COMMENT_RAW" == *"content"* ]]; then
            COMMENT_TEXT=$(echo "$DATA" | jq -r ".worklogs[$i].comment.content[0].content[0].text // \"(No comment)\"")
        else
            COMMENT_TEXT=$(echo "$DATA" | jq -r ".worklogs[$i].comment // \"(No comment)\"")
        fi
        
        if [ ${#COMMENT_TEXT} -gt 40 ]; then
            COMMENT_TEXT="${COMMENT_TEXT:0:37}..."
        fi

        printf "%-8s | %-8s | %-10s | %-12s | %s\n" \
            "[$WL_ID]" "$TIME_SPENT" "$STARTED_DATE" "$AUTHOR" "$COMMENT_TEXT"
    done
    echo "----------------------------------------"
    return 0
}

# Validates if a list of IDs exists in the current cached data
validate_worklog_ids() {
    local ids_string="$1"
    local clean_ids=$(echo "$ids_string" | tr -d ' ')
    IFS=',' read -ra ID_ARRAY <<< "$clean_ids"
    
    local valid_ids=()
    local invalid_ids=()

    # Get all valid IDs from cache
    local available_ids=$(echo "$LAST_WORKLOG_DATA" | jq -r '.worklogs[].id')

    for id in "${ID_ARRAY[@]}"; do
        if [ -z "$id" ]; then continue; fi
        
        if echo "$available_ids" | grep -qx "$id"; then
            valid_ids+=("$id")
        else
            invalid_ids+=("$id")
        fi
    done

    if [ ${#invalid_ids[@]} -gt 0 ]; then
        echo -e "${RED}✗ ERROR: Invalid ID(s) detected: ${invalid_ids[*]}${NC}"
        echo "Available IDs: $available_ids"
        return 1
    fi

    if [ ${#valid_ids[@]} -eq 0 ]; then
        echo -e "${RED}✗ ERROR: No valid IDs provided.${NC}"
        return 1
    fi

    # Return valid IDs as a space-separated string for processing
    echo "${valid_ids[*]}"
    return 0
}

move_single_worklog() {
    local source_key="$1"
    local target_key="$2"
    local wl_id="$3"
    local use_cached_data="${4:-false}"

    if [ -z "$wl_id" ]; then
        echo -e "${RED}✗ ERROR: No worklog ID provided.${NC}"
        return 1
    fi

    local LIST_DATA
    if [ "$use_cached_data" == "true" ] && [ -n "$LAST_WORKLOG_DATA" ]; then
        LIST_DATA="$LAST_WORKLOG_DATA"
    else
        echo "Fetching fresh worklog list from $source_key..."
        LIST_DATA=$(curl -s -u "$EMAIL:$API_TOKEN" "$JIRA_BASE/rest/api/3/issue/$source_key/worklog?maxResults=100")
        if [ -z "$LIST_DATA" ]; then
            echo -e "${RED}✗ ERROR: Received empty response from Jira.${NC}"
            return 1
        fi
    fi

    if echo "$LIST_DATA" | jq -e '.errorMessages' > /dev/null 2>&1; then
        ERR_MSG=$(echo "$LIST_DATA" | jq -r '.errorMessages[0] // "Unknown error"')
        echo -e "${RED}✗ ERROR: Jira returned error: $ERR_MSG${NC}"
        return 1
    fi

    WL_DATA=$(echo "$LIST_DATA" | jq --arg id "$wl_id" '.worklogs[] | select((.id | tostring) == $id)')

    if [ -z "$WL_DATA" ]; then
        echo -e "${RED}✗ ERROR: Worklog ID $wl_id not found.${NC}"
        return 1
    fi

    TIME_SPENT_SEC=$(echo "$WL_DATA" | jq -r '.timeSpentSeconds')
    STARTED=$(echo "$WL_DATA" | jq -r '.started')
    COMMENT_JSON=$(echo "$WL_DATA" | jq -c '.comment // {}')

    if [ "$TIME_SPENT_SEC" == "null" ] || [ -z "$TIME_SPENT_SEC" ]; then
        echo -e "${RED}✗ ERROR: Could not extract 'timeSpentSeconds'.${NC}"
        return 1
    fi
    
    if [ "$STARTED" == "null" ] || [ -z "$STARTED" ]; then
        echo -e "${RED}✗ ERROR: Could not extract 'started' timestamp.${NC}"
        return 1
    fi

    PAYLOAD=$(printf '{"timeSpentSeconds":%s,"started":"%s","comment":%s,"adjustEstimate":"auto"}' \
        "$TIME_SPENT_SEC" \
        "$STARTED" \
        "$COMMENT_JSON")

    echo "Creating new worklog on $target_key..."
    
    CREATE_RESP=$(curl -s -w "\n%{http_code}" -X POST -u "$EMAIL:$API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$JIRA_BASE/rest/api/3/issue/$target_key/worklog")
    
    CREATE_CODE=$(echo "$CREATE_RESP" | tail -n1)
    CREATE_BODY=$(echo "$CREATE_RESP" | sed '$d')

    if [ "$CREATE_CODE" != "201" ]; then
        echo -e "${RED}✗ Failed to create new worklog (Status: $CREATE_CODE)${NC}"
        echo "Error: $CREATE_BODY"
        return 1
    fi

    NEW_WL_ID=$(echo "$CREATE_BODY" | jq -r '.id')
    echo -e "${GREEN}✓ Created new worklog ID: $NEW_WL_ID${NC}"

    echo "Deleting original worklog ID: $wl_id..."
    DELETE_RESP=$(curl -s -w "\n%{http_code}" -X DELETE -u "$EMAIL:$API_TOKEN" \
        "$JIRA_BASE/rest/api/3/issue/$source_key/worklog/$wl_id")
    
    DELETE_CODE=$(echo "$DELETE_RESP" | tail -n1)

    if [ "$DELETE_CODE" == "204" ] || [ "$DELETE_CODE" == "200" ]; then
        echo -e "${GREEN}✓ Deleted original worklog ID: $wl_id${NC}"
        echo -e "${GREEN}SUCCESS: Moved worklog from $source_key to $target_key.${NC}"
        LAST_WORKLOG_DATA="" 
        return 0
    else
        echo -e "${RED}⚠ WARNING: New worklog created ($NEW_WL_ID) but deletion failed (Status: $DELETE_CODE)!${NC}"
        LAST_WORKLOG_DATA=""
        return 1
    fi
}

process_worklog_batch() {
    local source_key="$1"
    local target_key="$2"
    local ids_string="$3"

    # Validate IDs first
    VALID_IDS=$(validate_worklog_ids "$ids_string")
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Convert space-separated back to array
    read -ra ID_ARRAY <<< "$VALID_IDS"

    if [ ${#ID_ARRAY[@]} -eq 0 ]; then
        echo -e "${RED}✗ ERROR: No valid IDs to process.${NC}"
        return 1
    fi

    echo -e "${BLUE}Processing ${#ID_ARRAY[@]} worklog(s)...${NC}"
    
    local success_count=0
    local fail_count=0

    for wl_id in "${ID_ARRAY[@]}"; do
        echo ""
        echo "--- Processing ID: $wl_id ---"
        if move_single_worklog "$source_key" "$target_key" "$wl_id" "true"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done

    echo ""
    echo "----------------------------------------"
    echo -e "${GREEN}Batch Complete: $success_count succeeded, $fail_count failed.${NC}"
    
    if [ $fail_count -eq 0 ]; then
        echo "Refreshing worklog list..."
        fetch_worklogs "$source_key"
    fi
}

issue_session_loop() {
    local src_key="$1"
    CURRENT_ISSUE_KEY="$src_key"
    
    while true; do
        print_header "Session: $src_key"
        echo "Commands:"
        echo "  m <id>     : Move worklog(s), bulk comma separation is OK"
        echo "  r          : Refresh list"
        echo "  q/back     : Return to Main Menu"
        
        # Fetch worklogs if we don't have them
        if [ -z "$LAST_WORKLOG_DATA" ]; then
            if ! fetch_worklogs "$src_key"; then
                # FIX: If no worklogs found, return to main menu
                echo -e "${YELLOW}Returning to Main Menu (No worklogs found).${NC}"
                LAST_WORKLOG_DATA=""
                return 0
            fi
        else
            COUNT=$(echo "$LAST_WORKLOG_DATA" | jq '.total')
            echo -e "${YELLOW}Cached data loaded ($COUNT logs). Use 'r' to refresh.${NC}"
            fetch_worklogs "$src_key" 
        fi

        read -p "Action [m/r/q]: " ACTION_INPUT
        
        if is_exit_command "$ACTION_INPUT"; then
            echo "Leaving session for $src_key."
            LAST_WORKLOG_DATA=""
            return 0
        fi

        local cmd=$(echo "$ACTION_INPUT" | awk '{print $1}')
        local args=$(echo "$ACTION_INPUT" | cut -d' ' -f2-)

        case $cmd in
            m|M)
                # FIX: Validate if ID was provided
                if [ -z "$args" ]; then
                    echo -e "${RED}✗ ERROR: No worklog ID provided. Example: m 123, 456${NC}"
                    continue
                fi
                
                read -p "Target Issue Key (or URL): " TGT_INPUT
                if is_exit_command "$TGT_INPUT"; then
                    continue
                fi
                TGT_KEY=$(parse_issue_key "$TGT_INPUT")
                
                if [[ ! "$TGT_KEY" =~ ^[A-Z]+-[0-9]+$ ]]; then
                    echo -e "${RED}✗ ERROR: Invalid Target Key format: '$TGT_KEY'.${NC}"
                    continue
                fi
                
                # FIX: Process batch (validation happens inside)
                process_worklog_batch "$src_key" "$TGT_KEY" "$args"
                ;;
            r|R)
                LAST_WORKLOG_DATA=""
                fetch_worklogs "$src_key"
                ;;
            *)
                echo -e "${YELLOW}Unknown command. Try 'm', 'r', or 'q'.${NC}"
                ;;
        esac
    done
}

# ==========================================
# MAIN LOOP
# ==========================================

print_header "Jira Worklog Mover"
echo "Enter your Jira Cloud details:"
read -p "Your Base URL (e.g., https://example.atlassian.net): " JIRA_BASE
read -p "Your Login Email: " EMAIL
echo "If you haven't already, set up an API token via https://id.atlassian.com/manage-profile/security/api-tokens"
read -sp "Provide Your API Token: " API_TOKEN
echo ""

if ! validate_connection; then
    echo "Exiting due to authentication failure."
    exit 1
fi

while true; do
    print_header "Main Menu"
    echo "1. Open Issue Session"
    echo "2. Change Login/API Credentials"
    echo "3. Exit"
    read -p "Select option [1-3]: " CHOICE

    case $CHOICE in
        1)
            LAST_WORKLOG_DATA=""
            CURRENT_ISSUE_KEY=""
            
            while true; do
                read -p "Source Issue Key (e.g., PROJ-123) or URL: " SRC_INPUT
                
                if is_exit_command "$SRC_INPUT"; then
                    break
                fi

                if [ -z "$SRC_INPUT" ]; then
                    echo -e "${YELLOW}Input cannot be empty. Please try again.${NC}"
                    continue
                fi

                SRC_KEY=$(parse_issue_key "$SRC_INPUT")
                
                if [[ ! "$SRC_KEY" =~ ^[A-Z]+-[0-9]+$ ]]; then
                    echo -e "${RED}✗ ERROR: '$SRC_KEY' is not a valid Jira Issue Key format (e.g., ABC-123).${NC}"
                    echo "Please enter a valid key or 'q' to cancel."
                    continue
                fi

                break
            done
            
            if is_exit_command "$SRC_INPUT"; then
                continue
            fi

            issue_session_loop "$SRC_KEY"
            ;;
        2)
            read -p "New Base URL: " JIRA_BASE
            read -p "New Email: " EMAIL
            read -sp "New API Token: " API_TOKEN
            echo ""
            if ! validate_connection; then
                echo "Credentials invalid. Exiting."
                exit 1
            fi
            ;;
        3)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
done

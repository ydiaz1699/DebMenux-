#!/usr/bin/env bash
# ==========================================================
# DebMenux - Menu-driven toolkit for Debian homelab/NAS
# ==========================================================
# File: scripts/menus/services_menu.sh
# Description: Interactive menu to browse and install services
#              from the service catalog.
# License: MIT
# ==========================================================

set -euo pipefail

# Paths
DEBMENUX_BASE_DIR="${DEBMENUX_BASE_DIR:-/usr/local/share/debmenux}"
DEBMENUX_SCRIPTS="${DEBMENUX_SCRIPTS:-${DEBMENUX_BASE_DIR}/scripts}"
DEBMENUX_LIB="${DEBMENUX_LIB:-${DEBMENUX_BASE_DIR}/lib}"
DEBMENUX_VERSION=$(cat "${DEBMENUX_BASE_DIR}/version.txt" 2>/dev/null || echo "dev")

CATALOG_FILE="${DEBMENUX_BASE_DIR}/services.json"

# Source libraries
source "${DEBMENUX_LIB}/utils.sh"
source "${DEBMENUX_LIB}/docker.sh"
source "${DEBMENUX_LIB}/integration.sh"

# ==============================================================================
# CATEGORY MENU
# ==============================================================================

show_categories_menu() {
    if [[ ! -f "$CATALOG_FILE" ]]; then
        dialog --backtitle "DebMenux" --title " Error " \
            --msgbox "\nServices catalog not found:\n${CATALOG_FILE}" 9 50
        exec bash "${DEBMENUX_SCRIPTS}/menus/main_menu.sh"
    fi

    # Extract unique categories
    local categories
    categories=$(jq -r '.services[].category' "$CATALOG_FILE" | sort -u)

    local menu_items=()
    local i=1
    local -A category_map

    while IFS= read -r cat; do
        [[ -z "$cat" ]] && continue
        local count
        count=$(jq -r --arg c "$cat" '[.services[] | select(.category == $c)] | length' "$CATALOG_FILE")
        menu_items+=("$i" "${cat} (${count} services)")
        category_map["$i"]="$cat"
        ((i++))
    done <<< "$categories"

    menu_items+=("A" "Show ALL services")
    menu_items+=("0" "Back to Main Menu")

    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux v${DEBMENUX_VERSION}" \
        --title " Install a Service " \
        --menu "\nSelect a category:" 20 55 12 \
        "${menu_items[@]}" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; exec bash "${DEBMENUX_SCRIPTS}/menus/main_menu.sh"; }

    local choice
    choice=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    case "$choice" in
        0) exec bash "${DEBMENUX_SCRIPTS}/menus/main_menu.sh" ;;
        A) show_services_list "" ;;
        *) show_services_list "${category_map[$choice]:-}" ;;
    esac
}

# ==============================================================================
# SERVICES LIST
# ==============================================================================

show_services_list() {
    local filter_category="$1"

    local jq_filter
    if [[ -n "$filter_category" ]]; then
        jq_filter=".services[] | select(.category == \"${filter_category}\")"
    else
        jq_filter=".services[]"
    fi

    local menu_items=()
    local -A service_ids

    while IFS='|' read -r id description; do
        [[ -z "$id" ]] && continue
        menu_items+=("$id" "$description")
        service_ids["$id"]=1
    done < <(jq -r "${jq_filter} | \"\(.id)|\(.description)\"" "$CATALOG_FILE")

    if [[ ${#menu_items[@]} -eq 0 ]]; then
        dialog --backtitle "DebMenux" --title " Services " \
            --msgbox "\nNo services found in this category." 8 45
        show_categories_menu
        return
    fi

    menu_items+=("0" "Back")

    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    local title="Services"
    [[ -n "$filter_category" ]] && title="Services: ${filter_category}"

    dialog --clear \
        --backtitle "DebMenux v${DEBMENUX_VERSION}" \
        --title " ${title} " \
        --menu "\nSelect a service to install:" 22 65 14 \
        "${menu_items[@]}" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; show_categories_menu; return; }

    local selected
    selected=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    if [[ "$selected" == "0" ]]; then
        show_categories_menu
        return
    fi

    confirm_and_install "$selected"
}

# ==============================================================================
# CONFIRM & INSTALL
# ==============================================================================

confirm_and_install() {
    local service_id="$1"

    # Get service details from catalog
    local name description category port image
    name=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .name' "$CATALOG_FILE")
    description=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .description' "$CATALOG_FILE")
    category=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .category' "$CATALOG_FILE")
    port=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .port // "N/A"' "$CATALOG_FILE")
    image=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .image // "N/A"' "$CATALOG_FILE")

    local info=""
    info+="Name:        ${name}\n"
    info+="Description: ${description}\n"
    info+="Category:    ${category}\n"
    info+="Image:       ${image}\n"
    info+="Port:        ${port}\n"
    info+="Install to:  ${DOCKER_DIR}/${service_id}/\n"

    dialog --backtitle "DebMenux" \
        --title " Install ${name}? " \
        --yesno "${info}\n\nProceed with installation?" 16 60

    local exit_status=$?
    if [[ $exit_status -ne 0 ]]; then
        show_services_list "$category"
        return
    fi

    # Execute installation
    clear
    msg_title "Installing ${name}"

    local script_file="${DEBMENUX_SCRIPTS}/services/${service_id}.sh"

    if [[ ! -f "$script_file" ]]; then
        msg_error "Install script not found: ${script_file}"
        echo -e "\n${TAB}Press ENTER to continue..."
        read -r
        show_categories_menu
        return
    fi

    # Check Docker
    if ! check_docker; then
        echo -e "\n${TAB}Press ENTER to continue..."
        read -r
        show_categories_menu
        return
    fi

    if ! check_compose; then
        echo -e "\n${TAB}Press ENTER to continue..."
        read -r
        show_categories_menu
        return
    fi

    # Run the install script
    source "$script_file"
    install_service

    echo -e "\n${TAB}Press ENTER to continue..."
    read -r

    show_categories_menu
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

show_categories_menu

#!/usr/bin/env bash
# ==========================================================
# DebMenux — Toolkit interactivo para homelab Debian + Docker
# ==========================================================
# Archivo: scripts/menus/services_menu.sh
# Descripción: Menú interactivo para explorar e instalar
#              servicios desde el catálogo.
# Licencia: MIT
# ==========================================================

set -euo pipefail

DEBMENUX_BASE_DIR="${DEBMENUX_BASE_DIR:-/usr/local/share/debmenux}"
DEBMENUX_SCRIPTS="${DEBMENUX_SCRIPTS:-${DEBMENUX_BASE_DIR}/scripts}"
DEBMENUX_LIB="${DEBMENUX_LIB:-${DEBMENUX_BASE_DIR}/lib}"
DEBMENUX_VERSION=$(cat "${DEBMENUX_BASE_DIR}/version.txt" 2>/dev/null || echo "dev")

CATALOG_FILE="${DEBMENUX_BASE_DIR}/services.json"

source "${DEBMENUX_LIB}/utils.sh"
source "${DEBMENUX_LIB}/docker.sh"
source "${DEBMENUX_LIB}/integration.sh"

# ==============================================================================
# MENÚ DE CATEGORÍAS
# ==============================================================================

show_categories_menu() {
    if [[ ! -f "$CATALOG_FILE" ]]; then
        dialog --backtitle "DebMenux" --title " ❌ Error " \
            --msgbox "\nCatálogo de servicios no encontrado:\n${CATALOG_FILE}" 9 50
        exec bash "${DEBMENUX_SCRIPTS}/menus/main_menu.sh"
    fi

    local categories
    categories=$(jq -r '.services[].category' "$CATALOG_FILE" | sort -u)

    local menu_items=()
    local i=1
    local -A category_map

    while IFS= read -r cat; do
        [[ -z "$cat" ]] && continue
        local count
        count=$(jq -r --arg c "$cat" '[.services[] | select(.category == $c)] | length' "$CATALOG_FILE")
        # Obtener emoji de la categoría
        local emoji
        emoji=$(jq -r --arg c "$cat" '.categories[] | select(.id == $c) | .icon // "📦"' "$CATALOG_FILE")
        menu_items+=("$i" "${emoji} ${cat} (${count} servicios)")
        category_map["$i"]="$cat"
        ((i++))
    done <<< "$categories"

    menu_items+=("A" "📋 Mostrar TODOS los servicios")
    menu_items+=("0" "↩️  Volver al Menú Principal")

    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "🐧 DebMenux v${DEBMENUX_VERSION}" \
        --title " 📦 Instalar un Servicio " \
        --menu "\nSelecciona una categoría:" 20 55 12 \
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
# LISTA DE SERVICIOS
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
        dialog --backtitle "DebMenux" --title " 📦 Servicios " \
            --msgbox "\n❌ No se encontraron servicios en esta categoría." 8 45
        show_categories_menu
        return
    fi

    menu_items+=("0" "↩️  Volver")

    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    local title="📦 Servicios"
    [[ -n "$filter_category" ]] && title="📦 Servicios: ${filter_category}"

    dialog --clear \
        --backtitle "🐧 DebMenux v${DEBMENUX_VERSION}" \
        --title " ${title} " \
        --menu "\nSelecciona un servicio para instalar:" 22 65 14 \
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
# CONFIRMAR E INSTALAR
# ==============================================================================

confirm_and_install() {
    local service_id="$1"

    local name description category port image
    name=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .name' "$CATALOG_FILE")
    description=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .description' "$CATALOG_FILE")
    category=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .category' "$CATALOG_FILE")
    port=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .port // "N/A"' "$CATALOG_FILE")
    image=$(jq -r --arg id "$service_id" '.services[] | select(.id == $id) | .image // "N/A"' "$CATALOG_FILE")

    local info=""
    info+="📦 Nombre:       ${name}\n"
    info+="📝 Descripción:  ${description}\n"
    info+="🏷️  Categoría:    ${category}\n"
    info+="🐳 Imagen:       ${image}\n"
    info+="🌐 Puerto:       ${port}\n"
    info+="📁 Instalar en:  ${DOCKER_DIR}/${service_id}/\n"

    dialog --backtitle "DebMenux" \
        --title " 🚀 ¿Instalar ${name}? " \
        --yesno "${info}\n\n¿Proceder con la instalación?" 16 60

    local exit_status=$?
    if [[ $exit_status -ne 0 ]]; then
        show_services_list "$category"
        return
    fi

    # Ejecutar instalación
    clear
    msg_title "🚀 Instalando ${name}"

    local script_file="${DEBMENUX_SCRIPTS}/services/${service_id}.sh"

    if [[ ! -f "$script_file" ]]; then
        msg_error "Script de instalación no encontrado: ${script_file}"
        echo -e "\n${TAB}Presiona ENTER para continuar..."
        read -r
        show_categories_menu
        return
    fi

    if ! check_docker; then
        echo -e "\n${TAB}Presiona ENTER para continuar..."
        read -r
        show_categories_menu
        return
    fi

    if ! check_compose; then
        echo -e "\n${TAB}Presiona ENTER para continuar..."
        read -r
        show_categories_menu
        return
    fi

    source "$script_file"
    install_service

    echo -e "\n${TAB}Presiona ENTER para continuar..."
    read -r

    show_categories_menu
}

# ==============================================================================
# PUNTO DE ENTRADA
# ==============================================================================

show_categories_menu

#!/bin/bash

# Configuration
CONFIG_DIR="$HOME/.config/agentic-user"
STATE_FILE="$CONFIG_DIR/state.json"
DEFAULT_USER_PREFIX="agentic-user"
DEFAULT_MOUNT_POINT="/home"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"
if [ ! -f "$STATE_FILE" ]; then
    echo "{\"users\": [], \"mounts\": []}" > "$STATE_FILE"
fi

# Check dependencies
check_dependencies() {
    local missing_deps=()
    if ! command -v whiptail &> /dev/null; then
        missing_deps+=("whiptail")
    fi
    if ! command -v setfacl &> /dev/null; then
        missing_deps+=("acl")
    fi
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Missing dependencies: ${missing_deps[*]}"
        echo "Please install them using your package manager (e.g., sudo apt install whiptail acl jq)"
        exit 1
    fi
}

# Helper function to read state
get_state() {
    cat "$STATE_FILE"
}

# Helper function to write state
save_state() {
    echo "$1" > "$STATE_FILE"
}

# TUI Functions
show_main_menu() {
    whiptail --title "Agentic User Management" --menu "Choose an option:" 20 78 10 \
        "1" "Start Shell (as Agentic User)" \
        "2" "Create Agentic User" \
        "3" "Remove Agentic User" \
        "4" "Mount Directory" \
        "5" "Unmount Directory" \
        "6" "List Status" \
        "7" "Settings" 3>&1 1>&2 2>&3
}

# PLACEHOLDER ACTIONS
start_shell() {
    whiptail --msgbox "Start Shell not implemented yet." 10 60
}

create_agentic_user() {
    whiptail --msgbox "Create Agentic User not implemented yet." 10 60
}

remove_agentic_user() {
    whiptail --msgbox "Remove Agentic User not implemented yet." 10 60
}

mount_directory() {
    whiptail --msgbox "Mount Directory not implemented yet." 10 60
}

unmount_directory() {
    whiptail --msgbox "Unmount Directory not implemented yet." 10 60
}

list_status() {
    whiptail --msgbox "List Status not implemented yet." 10 60
}

settings_menu() {
    whiptail --msgbox "Settings not implemented yet." 10 60
}

# Main Loop
main() {
    check_dependencies

    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -s|--start-shell)
                if [ -n "$2" ] && [[ "$2" != -* ]]; then
                    start_shell "$2"
                    exit 0
                else
                    start_shell
                    exit 0
                fi
                ;;
            *)
                echo "Unknown parameter passed: $1"
                exit 1
                ;;
        esac
        shift
    done

    while true; do
        CHOICE=$(show_main_menu)
        exit_status=$?

        if [ $exit_status -ne 0 ]; then
            clear
            echo "Exiting."
            exit 0
        fi

        case $CHOICE in
            1) start_shell ;;
            2) create_agentic_user ;;
            3) remove_agentic_user ;;
            4) mount_directory ;;
            5) unmount_directory ;;
            6) list_status ;;
            7) settings_menu ;;
        esac
    done
}

main "$@"

#!/bin/bash

# Configuration
CONFIG_DIR="$HOME/.config/abox"
STATE_FILE="$CONFIG_DIR/state.json"
DEFAULT_USER_PREFIX="agentic-user"
DEFAULT_MOUNT_POINT="/home"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"
if [ ! -f "$STATE_FILE" ]; then
    echo "{\"users\": [], \"mounts\": []}" > "$STATE_FILE"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check dependencies
check_dependencies() {
    local missing_deps=()
    if ! command -v setfacl &> /dev/null; then
        missing_deps+=("acl")
    fi
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    if ! command -v xhost &> /dev/null; then
        missing_deps+=("xhost")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing dependencies: ${missing_deps[*]}${NC}"
        echo "Please install them using your package manager."
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

# Helper for confirmation
confirm_action() {
    local prompt="$1"
    local response
    echo -e -n "${YELLOW}$prompt [y/N]: ${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# TUI Functions
print_header() {
    echo ""
    echo "  █████╗ ██████╗  ██████╗ ██╗  ██╗"
    echo " ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝"
    echo " ███████║██████╔╝██║   ██║ ╚███╔╝ "
    echo " ██╔══██║██╔══██╗██║   ██║ ██╔██╗ "
    echo " ██║  ██║██████╔╝╚██████╔╝██╔╝ ██╗"
    echo " ╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
    echo "========================================"
    echo "User based sandboxing for AI agents"
    echo "========================================"
}

show_main_menu() {
    echo
    echo "1. Start Shell (as Agentic User)"
    echo "2. Create Agentic User"
    echo "3. Remove Agentic User"
    echo "4. Mount Directory"
    echo "5. Unmount Directory"
    echo "6. List Status"
    echo "7. Advanced"
    echo "0. Exit"
    echo
    echo -n "Choose an option: "
}

# PLACEHOLDER ACTIONS
start_shell() {
    echo "Start Shell not implemented yet."
}

create_agentic_user() {
    echo
    echo "--- Create Agentic User ---"

    # Suggest username
    local count=$(jq '.users | length' "$STATE_FILE")
    local next_suffix=$((count + 1))
    local default_name="${DEFAULT_USER_PREFIX}-${next_suffix}"

    echo -n "Enter username [${default_name}]: "
    read -r input_name
    local username="${input_name:-$default_name}"

    # Check if user exists in system or state
    if id "$username" &>/dev/null; then
        echo -e "${RED}Error: User '$username' already exists in the system.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi

    # Create user
    echo "Creating user '$username'..."
    if sudo useradd -m -s /bin/bash "$username"; then
        echo -e "${GREEN}User '$username' created successfully.${NC}"
        # Lock password (default behavior but being explicit)
        sudo passwd -l "$username" &>/dev/null

        # Update state
        local tmp_file=$(mktemp)
        jq --arg u "$username" '.users += [$u]' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
    else
        echo -e "${RED}Failed to create user.${NC}"
    fi

    echo "Press Enter to continue..."
    read -r
}

remove_agentic_user() {
    echo
    echo "--- Remove Agentic User ---"

    # List users from state
    local users=$(jq -r '.users[]' "$STATE_FILE")
    if [ -z "$users" ]; then
        echo "No agentic users currently managed."
        echo "Press Enter to continue..."
        read -r
        return
    fi

    echo "Managed Agentic Users:"
    local i=1
    local user_array=()
    while read -r u; do
        if [ -n "$u" ]; then
            echo "$i. $u"
            user_array+=("$u")
            ((i++))
        fi
    done <<< "$users"

    echo
    echo -n "Select user to remove (1-${#user_array[@]}): "
    read -r selection

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#user_array[@]}" ]; then
        echo -e "${RED}Invalid selection.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi

    local target_user="${user_array[$((selection-1))]}"

    echo -e "${YELLOW}WARNING: This will delete user '$target_user' and their home directory!${NC}"
    echo -n "Are you sure? [y/N]: "
    read -r confirm
    if [[ ! "$confirm" =~ ^[yY] ]]; then
        echo "Cancelled."
        return
    fi

    # Remove user
    if sudo userdel -r "$target_user"; then
        echo -e "${GREEN}User '$target_user' removed.${NC}"
        # Update state
        local tmp_file=$(mktemp)
        jq --arg u "$target_user" '.users -= [$u]' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
    else
        echo -e "${RED}Failed to remove user.${NC}"
    fi

    echo "Press Enter to continue..."
    read -r
}

# Helper to select user
select_agentic_user() {
    local users=$(jq -r '.users[]' "$STATE_FILE")
    local count=$(jq '.users | length' "$STATE_FILE")

    if [ "$count" -eq 0 ]; then
        echo "No agentic users found." >&2
        return 1
    elif [ "$count" -eq 1 ]; then
        echo "$users"
        return 0
    fi

    echo "Select Agentic User:" >&2
    local i=1
    local user_array=()
    while read -r u; do
        if [ -n "$u" ]; then
            echo "$i. $u" >&2
            user_array+=("$u")
            ((i++))
        fi
    done <<< "$users"

    echo -n "Selection (1-${#user_array[@]}): " >&2
    read -r selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#user_array[@]}" ]; then
        echo "${user_array[$((selection-1))]}"
        return 0
    fi

    return 1
}

mount_directory() {
    echo
    echo "--- Mount Directory ---"

    local agent_user
    if ! agent_user=$(select_agentic_user); then
        echo -e "${RED}Invalid user or no users found.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi
    echo "Selected user: $agent_user"

    echo -n "Enter source directory path (absolute path): "
    read -r -e source_dir

    # Expand tilde if present
    source_dir="${source_dir/#\~/$HOME}"

    if [ ! -d "$source_dir" ]; then
        echo -e "${RED}Error: Directory '$source_dir' does not exist.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi
    source_dir=$(realpath "$source_dir")

    local default_name=$(basename "$source_dir")
    echo -n "Enter mount name (in agent home) [$default_name]: "
    read -r mount_name
    mount_name="${mount_name:-$default_name}"

    local target_dir="/home/$agent_user/$mount_name"

    if [ -d "$target_dir" ]; then
        echo -e "${RED}Error: Target directory '$target_dir' already exists.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi

    echo "Mounting '$source_dir' to '$target_dir'..."

    # Create target dir
    # Use sudo runuser to create dir as the agent user so ownership is correct?
    # Or sudo mkdir and sudo chown.
    if ! sudo mkdir -p "$target_dir"; then
         echo -e "${RED}Failed to create directory.${NC}"
         read -r; return
    fi
    sudo chown "$agent_user:$agent_user" "$target_dir"

    # Bind mount
    if ! sudo mount --bind "$source_dir" "$target_dir"; then
        echo -e "${RED}Failed to mount directory.${NC}"
        sudo rmdir "$target_dir"
        read -r; return
    fi

    # Set ACLs
    echo "Setting ACLs..."
    sudo setfacl -R -m u:"$agent_user":rwx "$source_dir"
    sudo setfacl -R -d -m u:"$agent_user":rwx "$source_dir"

    # Update state
    local tmp_file=$(mktemp)
    jq --arg u "$agent_user" --arg s "$source_dir" --arg t "$target_dir" \
       '.mounts += [{"user": $u, "source": $s, "target": $t}]' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"

    echo -e "${GREEN}Mounted successfully.${NC}"
    echo "Press Enter to continue..."
    read -r
}

unmount_directory() {
    echo
    echo "--- Unmount Directory ---"

    local mounts=$(jq -c '.mounts[]' "$STATE_FILE")
    if [ -z "$mounts" ]; then
        echo "No mounted directories."
        echo "Press Enter to continue..."
        read -r
        return
    fi

    echo "Mounted Directories:"
    local i=1
    local mount_array=()
    while read -r m; do
        if [ -n "$m" ]; then
            local u=$(echo "$m" | jq -r '.user')
            local s=$(echo "$m" | jq -r '.source')
            local t=$(echo "$m" | jq -r '.target')
            echo "$i. User: $u | Source: $s -> Target: $t"
            mount_array+=("$m")
            ((i++))
        fi
    done <<< "$mounts"

    echo
    echo -n "Select mount to remove (1-${#mount_array[@]}): "
    read -r selection

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#mount_array[@]}" ]; then
        echo -e "${RED}Invalid selection.${NC}"
        read -r; return
    fi

    local target_json="${mount_array[$((selection-1))]}"
    local user=$(echo "$target_json" | jq -r '.user')
    local source=$(echo "$target_json" | jq -r '.source')
    local target=$(echo "$target_json" | jq -r '.target')

    echo -e "${YELLOW}Unmounting '$target' and removing permissions for '$user'.${NC}"
    if ! confirm_action "Are you sure?"; then
        echo "Cancelled."
        return
    fi

    # Unmount
    local unmounted=false

    # Check if currently mounted using /proc/mounts (more reliable than mountpoint in some containers/chroots)
    if ! grep -qsF "$target" /proc/mounts; then
         echo "Directory appears to be already unmounted (according to /proc/mounts)."
         unmounted=true
    else
        # Attempt unmount
        if sudo umount "$target" 2>/dev/null; then
            unmounted=true
        else
            # Unmount failed. Re-check if it's still mounted.
            if grep -qsF "$target" /proc/mounts; then
                echo -e "${RED}Error: Target is busy.${NC}"
                echo "The following processes are using the directory:"

                # Try to show processes
                if command -v lsof &>/dev/null; then
                    sudo lsof +D "$target"
                elif command -v fuser &>/dev/null; then
                    sudo fuser -vm "$target"
                else
                    echo "  (Install lsof or fuser to see processes)"
                fi

                echo
                echo "Please close these applications and try again."
                echo "The mount has NOT been removed from the state file."

                echo "Press Enter to continue..."
                read -r
                return
            else
                # It disappeared from /proc/mounts? Assume success.
                unmounted=true
            fi
        fi
    fi

    if [ "$unmounted" = "true" ]; then
        # Double check one last time before rmdir
        if grep -qsF "$target" /proc/mounts; then
             echo -e "${RED}Critical Error: Directory still listed in /proc/mounts! Aborting cleanup.${NC}"
             read -r; return
        fi

        echo "Unmounted directory (or verified unmount)."
        sudo rmdir "$target" 2>/dev/null

        # Remove ACLs  (careful not to break other users if they exist, but simple -x is safe enough for specific user)
        # Note: removing -R might be tedious, but -x -R is likely intended to cleanup access
        sudo setfacl -R -x u:"$user" "$source" 2>/dev/null
        sudo setfacl -R -d -x u:"$user" "$source" 2>/dev/null

        # Update state
        local tmp_file=$(mktemp)
        # Remove the specific mount entry. simplistic match.
        jq --arg u "$user" --arg s "$source" --arg t "$target" \
           'del(.mounts[] | select(.user == $u and .source == $s and .target == $t))' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"

        echo -e "${GREEN}Unmount complete.${NC}"
    else
        echo -e "${RED}Operation aborted.${NC}"
    fi

    echo "Press Enter to continue..."
    read -r
}

start_shell() {
    local target_user="$1"

    # If no user specified, select one
    if [ -z "$target_user" ]; then
        echo
        echo "--- Start Shell ---"
        if ! target_user=$(select_agentic_user); then
            echo -e "${RED}Invalid user or no users found.${NC}"
            echo "Press Enter to continue..."
            read -r
            return
        fi
    fi

    echo "Starting shell for '$target_user'..."

    # Enable X11 access
    if command -v xhost &>/dev/null; then
        echo "Granting X11 access..."
        xhost +SI:localuser:"$target_user" >/dev/null
    fi

    # Prepare environment variables to pass
    local env_vars=""
    [ -n "$DISPLAY" ] && env_vars+="export DISPLAY='$DISPLAY';"
    [ -n "$WAYLAND_DISPLAY" ] && env_vars+="export WAYLAND_DISPLAY='$WAYLAND_DISPLAY';"

    # Start shell
    echo -e "${GREEN}Dropping into shell. Type 'exit' to return.${NC}"

    # Switch to user in home & start bash
    sudo -u "$target_user" bash -c "cd \"/home/$target_user\" && $env_vars exec bash -l"

    echo -e "${YELLOW}Shell session ended.${NC}"

    # Revoke X11 access after??
    # xhost -SI:localuser:"$target_user" >/dev/null

    if [ -z "$1" ]; then # Only pause if interactive (not CLI arg)
        echo "Press Enter to continue..."
        read -r
    fi
}

list_status() {
    echo
    echo "--- System Status ---"

    echo -e "${YELLOW}Agentic Users:${NC}"
    local users=$(jq -r '.users[]' "$STATE_FILE")
    if [ -z "$users" ]; then
        echo "  (None)"
    else
        while read -r u; do
            [ -n "$u" ] && echo "  - $u"
        done <<< "$users"
    fi

    echo
    echo -e "${YELLOW}Mounted Directories:${NC}"
    local mounts=$(jq -c '.mounts[]' "$STATE_FILE")
    if [ -z "$mounts" ]; then
        echo "  (None)"
    else
        while read -r m; do
            if [ -n "$m" ]; then
                local u=$(echo "$m" | jq -r '.user')
                local s=$(echo "$m" | jq -r '.source')
                local t=$(echo "$m" | jq -r '.target')
                echo "  - User: $u"
                echo "    Source: $s"
                echo "    Target: $t"
            fi
        done <<< "$mounts"
    fi

    echo
    echo "Press Enter to continue..."
    read -r
}

undo_all_changes() {
    echo
    echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
    echo -e "${RED}!!           UNDO ALL CHANGES TO SYSTEM           !!${NC}"
    echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
    echo "This will:"
    echo "1. Unmount ALL directories managed by this tool."
    echo "2. Remove permissions (ACLs) set by this tool."
    echo "3. DELETE ALL agentic users and their home directories."
    echo "4. Reset the configuration state."
    echo

    if ! confirm_action "Are you REALLY sure you want to proceed?"; then
        echo "Cancelled."
        read -r; return
    fi

    echo "Proceeding with cleanup..."

    # 1. Unmount directories
    echo "Unmounting directories..."
    local mounts=$(jq -c '.mounts[]' "$STATE_FILE")
    while read -r m; do
        if [ -n "$m" ]; then
            local u=$(echo "$m" | jq -r '.user')
            local s=$(echo "$m" | jq -r '.source')
            local t=$(echo "$m" | jq -r '.target')

            echo "  Unmounting $t..."
            sudo umount "$t" 2>/dev/null
            sudo rmdir "$t" 2>/dev/null

            echo "  Cleaning ACLs on $s..."
            sudo setfacl -R -x u:"$u" "$s" 2>/dev/null
            sudo setfacl -R -d -x u:"$u" "$s" 2>/dev/null
        fi
    done <<< "$mounts"

    # 2. Delete users
    echo "Deleting users..."
    local users=$(jq -r '.users[]' "$STATE_FILE")
    while read -r u; do
        if [ -n "$u" ]; then
            echo "  Deleting user $u..."
            sudo userdel -r "$u" 2>/dev/null
        fi
    done <<< "$users"

    # 3. Reset state
    echo "Resetting state file..."
    echo "{\"users\": [], \"mounts\": []}" > "$STATE_FILE"

    echo -e "${GREEN}Undo complete. System should be clean.${NC}"
    echo "Press Enter to continue..."
    read -r
}

settings_menu() {
    while true; do
        echo
        echo "--- Settings ---"
        echo "1. !! UNDO ALL CHANGES !!"
        echo "2. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice

        case $choice in
            1) undo_all_changes ;;
            2) return ;;
            *) echo -e "${RED}Invalid option.${NC}" ;;
        esac
    done
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

    print_header
    while true; do
        show_main_menu
        read -r CHOICE

        case $CHOICE in
            1) start_shell ;;
            2) create_agentic_user ;;
            3) remove_agentic_user ;;
            4) mount_directory ;;
            5) unmount_directory ;;
            6) list_status ;;
            7) settings_menu ;;
            0) echo "Exiting."; exit 0 ;;
            *) echo -e "${RED}Invalid option.${NC}" ;;
        esac
    done
}

main "$@"

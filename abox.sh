#!/bin/bash

# Configuration
CONFIG_DIR="$HOME/.config/abox"
STATE_FILE="$CONFIG_DIR/state.json"
DEFAULT_USER_PREFIX="agentic-user"
DEFAULT_MOUNT_POINT="/home"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"
if [ ! -f "$STATE_FILE" ]; then
    echo "{\"users\": [], \"mounts\": [], \"shared_directories\": []}" > "$STATE_FILE"
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
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing dependencies: ${missing_deps[*]}${NC}"
        echo "Please install them using your package manager."
        exit 1
    fi
}

# Ensure state schema has required keys
ensure_state_schema() {
    local tmp_file
    tmp_file=$(mktemp)
    jq '(.users //= []) | (.mounts //= []) | (.shared_directories //= [])' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
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
    echo "6. Create Shared Directory"
    echo "7. Mirror Git Config"
    echo "8. Fix Permissions"
    echo "9. List Status"
    echo "10. Advanced"
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

select_agentic_users_multi() {
    local users=$(jq -r '.users[]' "$STATE_FILE")
    local count=$(jq '.users | length' "$STATE_FILE")

    if [ "$count" -eq 0 ]; then
        echo "No agentic users found." >&2
        return 1
    fi

    echo "Select Agentic Users (comma-separated or 'all'):" >&2
    local i=1
    local user_array=()
    while read -r u; do
        if [ -n "$u" ]; then
            echo "$i. $u" >&2
            user_array+=("$u")
            ((i++))
        fi
    done <<< "$users"

    echo -n "Selection: " >&2
    read -r selection

    if [ "$selection" = "all" ] || [ "$selection" = "ALL" ]; then
        echo "${user_array[*]}"
        return 0
    fi

    local selected_users=()
    IFS=',' read -r -a selections <<< "$selection"
    for sel in "${selections[@]}"; do
        sel=$(echo "$sel" | xargs)
        if [[ ! "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "${#user_array[@]}" ]; then
            return 1
        fi
        selected_users+=("${user_array[$((sel-1))]}")
    done

    if [ "${#selected_users[@]}" -eq 0 ]; then
        return 1
    fi

    echo "${selected_users[*]}"
    return 0
}

path_in_user_home() {
    local candidate_path="$1"
    local home
    while IFS=: read -r _ _ _ _ _ home _; do
        [ -z "$home" ] && continue
        if [[ "$candidate_path" == "$home" || "$candidate_path" == "$home/"* ]]; then
            echo "$home"
            return 0
        fi
    done < <(getent passwd)
    return 1
}

create_shared_directory() {
    echo
    echo "--- Create Shared Directory ---"

    local shared_path
    echo -n "Enter shared directory path (absolute path): "
    read -r -e shared_path

    shared_path="${shared_path/#\~/$HOME}"

    if [[ ! "$shared_path" == /* ]]; then
        echo -e "${RED}Error: Shared directory path must be absolute.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi

    if command -v realpath &>/dev/null; then
        shared_path=$(realpath -m "$shared_path")
    fi

    local home_match
    if home_match=$(path_in_user_home "$shared_path"); then
        echo -e "${RED}Error: Shared directory cannot be inside a user's home directory: $home_match${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi

    if jq -e --arg p "$shared_path" '.shared_directories[]? | select(.path == $p)' "$STATE_FILE" >/dev/null; then
        echo -e "${RED}Error: Shared directory already exists in state.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi

    local selected_users
    if ! selected_users=$(select_agentic_users_multi); then
        echo -e "${RED}Invalid selection or no users found.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi

    if [ -e "$shared_path" ] && [ ! -d "$shared_path" ]; then
        echo -e "${RED}Error: Path exists and is not a directory.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi

    if [ ! -d "$shared_path" ]; then
        echo "Creating shared directory '$shared_path'..."
        if ! sudo mkdir -p "$shared_path"; then
            echo -e "${RED}Failed to create shared directory.${NC}"
            echo "Press Enter to continue..."
            read -r
            return
        fi
    fi

    echo "Setting ownership and ACLs..."
    sudo chown -R "$USER:$USER" "$shared_path" 2>/dev/null
    local acl_users=("$USER")
    IFS=' ' read -r -a selected_array <<< "$selected_users"
    acl_users+=("${selected_array[@]}")

    for u in "${acl_users[@]}"; do
        sudo setfacl -R -m u:"$u":rwX "$shared_path"
        sudo setfacl -R -d -m u:"$u":rwX "$shared_path"
    done

    local users_json
    users_json=$(printf '%s\n' "${acl_users[@]}" | jq -R . | jq -s .)

    local tmp_file=$(mktemp)
    jq --arg p "$shared_path" --argjson us "$users_json" \
       '.shared_directories += [{"path": $p, "users": $us}]' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"

    echo -e "${GREEN}Shared directory created and ACLs set.${NC}"
    echo "Press Enter to continue..."
    read -r
}

mirror_git_config() {
    echo
    echo "--- Mirror Git Config ---"

    local agent_user
    if ! agent_user=$(select_agentic_user); then
        echo -e "${RED}Invalid user or no users found.${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi
    echo "Selected user: $agent_user"

    echo
    echo "1. Basic (name and email only)"
    echo "2. Full (all global config, excluding includes)"
    echo -n "Choose level (1-2): "
    read -r level

    case "$level" in
        1)
            local host_name
            local host_email
            host_name=$(git config --global user.name)
            host_email=$(git config --global user.email)

            if [ -z "$host_name" ] && [ -z "$host_email" ]; then
                echo -e "${RED}Error: No host git user.name or user.email configured.${NC}"
                echo "Press Enter to continue..."
                read -r
                return
            fi

            [ -n "$host_name" ] && sudo -H -u "$agent_user" git config --global user.name "$host_name"
            [ -n "$host_email" ] && sudo -H -u "$agent_user" git config --global user.email "$host_email"

            echo -e "${GREEN}Basic git config mirrored.${NC}"
            ;;
        2)
            local host_config
            host_config=$(git config --global --list)

            if [ -z "$host_config" ]; then
                echo -e "${RED}Error: No host git global config found.${NC}"
                echo "Press Enter to continue..."
                read -r
                return
            fi

            local keys=()
            local values=()
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local key="${line%%=*}"
                local value="${line#*=}"
                if [[ "$key" == include.* || "$key" == includeIf.* ]]; then
                    continue
                fi
                keys+=("$key")
                values+=("$value")
            done <<< "$host_config"

            if [ "${#keys[@]}" -eq 0 ]; then
                echo -e "${RED}Error: No mirrorable git config found (only includes).${NC}"
                echo "Press Enter to continue..."
                read -r
                return
            fi

            declare -A seen_keys=()
            for key in "${keys[@]}"; do
                if [ -z "${seen_keys[$key]+x}" ]; then
                    sudo -H -u "$agent_user" git config --global --unset-all "$key" >/dev/null 2>&1
                    seen_keys[$key]=1
                fi
            done

            for i in "${!keys[@]}"; do
                sudo -H -u "$agent_user" git config --global --add "${keys[$i]}" "${values[$i]}"
            done

            echo -e "${GREEN}Full git config mirrored.${NC}"
            ;;
        *)
            echo -e "${RED}Invalid selection.${NC}"
            ;;
    esac

    echo "Press Enter to continue..."
    read -r
}

fix_permissions() {
    echo
    echo "--- Fix Permissions ---"

    local mounts=$(jq -c '.mounts[]' "$STATE_FILE")
    if [ -n "$mounts" ]; then
        echo "Fixing mount ACLs..."
        while read -r m; do
            [ -z "$m" ] && continue
            local u=$(echo "$m" | jq -r '.user')
            local s=$(echo "$m" | jq -r '.source')
            if [ -d "$s" ]; then
                sudo chown -R "$USER:$USER" "$s"
                sudo setfacl -R -m u:"$USER":rwx "$s"
                sudo setfacl -R -d -m u:"$USER":rwx "$s"
                sudo setfacl -R -m u:"$u":rwx "$s"
                sudo setfacl -R -d -m u:"$u":rwx "$s"
            else
                echo -e "${YELLOW}Warning: Mount source missing: $s${NC}"
            fi
        done <<< "$mounts"
    else
        echo "No mounts to fix."
    fi

    local shared=$(jq -c '.shared_directories[]' "$STATE_FILE")
    if [ -n "$shared" ]; then
        echo "Fixing shared directory ACLs..."
        while read -r sf; do
            [ -z "$sf" ] && continue
            local p=$(echo "$sf" | jq -r '.path')
            if [ -d "$p" ]; then
                sudo chown -R "$USER:$USER" "$p"
                sudo setfacl -R -m u:"$USER":rwX "$p"
                sudo setfacl -R -d -m u:"$USER":rwX "$p"
                local us=$(echo "$sf" | jq -r '.users[]')
                while read -r u; do
                    [ -z "$u" ] && continue
                    sudo setfacl -R -m u:"$u":rwX "$p"
                    sudo setfacl -R -d -m u:"$u":rwX "$p"
                done <<< "$us"
            else
                echo -e "${YELLOW}Warning: Shared directory missing: $p${NC}"
            fi
        done <<< "$shared"
    else
        echo "No shared directories to fix."
    fi

    echo -e "${GREEN}Permissions fix complete.${NC}"
    echo "Press Enter to continue..."
    read -r
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

    # Set ownership and ACLs
    echo "Setting ownership and ACLs..."
    sudo chown -R "$USER:$USER" "$source_dir"
    sudo setfacl -R -m u:"$USER":rwx "$source_dir"
    sudo setfacl -R -d -m u:"$USER":rwx "$source_dir"
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
    local initial_dir="$2"
    local run_command="$3"

    # If no user specified, select one
    if [ -z "$target_user" ]; then
        echo
        echo "--- Start Session ---"
        if ! target_user=$(select_agentic_user); then
            echo -e "${RED}Invalid user or no users found.${NC}"
            if [ "$HAS_CLI_ARGS" != true ]; then
                echo "Press Enter to continue..."
                read -r
            fi
            return 1
        fi
    fi

    if [ -z "$run_command" ]; then
        echo "Starting shell for '$target_user'..."
    else
        echo "Running command for '$target_user': $run_command"
    fi

    # Enable X11 access
    if command -v xhost &>/dev/null; then
        echo "Granting X11 access..."
        xhost +SI:localuser:"$target_user" >/dev/null
    fi

    # Prepare environment variables to pass
    local env_vars=""
    [ -n "$DISPLAY" ] && env_vars+="export DISPLAY='$DISPLAY';"
    [ -n "$WAYLAND_DISPLAY" ] && env_vars+="export WAYLAND_DISPLAY='$WAYLAND_DISPLAY';"

    # Switch to user in target directory & start bash
    local cd_dir="/home/$target_user"
    if [ -n "$initial_dir" ]; then
        cd_dir="$initial_dir"
    fi

    if [ -z "$run_command" ]; then
        echo -e "${GREEN}Dropping into shell. Type 'exit' to return.${NC}"
        sudo -u "$target_user" bash -c "cd \"$cd_dir\" && $env_vars exec bash -l"
    else
        sudo -u "$target_user" bash -c "cd \"$cd_dir\" && $env_vars exec bash -c '$run_command'"
    fi

    echo -e "${YELLOW}Session ended.${NC}"

    if [ "$HAS_CLI_ARGS" != true ]; then # Only pause if interactive
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
    echo -e "${YELLOW}Shared Directories:${NC}"
    local shared=$(jq -c '.shared_directories[]' "$STATE_FILE")
    if [ -z "$shared" ]; then
        echo "  (None)"
    else
        while read -r sf; do
            if [ -n "$sf" ]; then
                local p=$(echo "$sf" | jq -r '.path')
                local us=$(echo "$sf" | jq -r '.users | join(", ")')
                echo "  - Path: $p"
                echo "    Users: $us"
            fi
        done <<< "$shared"
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

    # 2.5. Remove shared directory ACLs
    echo "Cleaning shared directory ACLs..."
    local shared=$(jq -c '.shared_directories[]' "$STATE_FILE")
    while read -r sf; do
        if [ -n "$sf" ]; then
            local p=$(echo "$sf" | jq -r '.path')
            local us=$(echo "$sf" | jq -r '.users[]')
            while read -r u; do
                [ -z "$u" ] && continue
                sudo setfacl -R -x u:"$u" "$p" 2>/dev/null
                sudo setfacl -R -d -x u:"$u" "$p" 2>/dev/null
            done <<< "$us"
        fi
    done <<< "$shared"

    # 3. Reset state
    echo "Resetting state file..."
    echo "{\"users\": [], \"mounts\": [], \"shared_directories\": []}" > "$STATE_FILE"

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

check_and_translate_mount() {
    local piped_path="$1"
    local target_user="$2"

    local mounts=$(jq -c '.mounts[]' "$STATE_FILE" 2>/dev/null)
    if [ -z "$mounts" ]; then
        return 1
    fi

    local translated_path=""
    while read -r m; do
        if [ -n "$m" ]; then
            local u=$(echo "$m" | jq -r '.user')
            local s=$(echo "$m" | jq -r '.source')
            local t=$(echo "$m" | jq -r '.target')

            if [ "$target_user" != "$u" ]; then
                continue
            fi

            # Check if piped path is exactly the source or a subdirectory
            if [[ "$piped_path" == "$s" ]] || [[ "$piped_path" == "$s"/* ]]; then
                translated_path="${piped_path/#$s/$t}"
                if [ -f "$piped_path" ]; then
                    translated_path=$(dirname "$translated_path")
                fi
                echo "$translated_path"
                return 0
            fi
        fi
    done <<< "$mounts"

    return 1
}

check_and_translate_shared() {
    local piped_path="$1"
    local target_user="$2"

    local shared=$(jq -c '.shared_directories[]' "$STATE_FILE" 2>/dev/null)
    if [ -z "$shared" ]; then
        return 1
    fi

    local translated_path=""
    while read -r sf; do
        if [ -n "$sf" ]; then
            local p=$(echo "$sf" | jq -r '.path')

            if [[ "$piped_path" == "$p" ]] || [[ "$piped_path" == "$p"/* ]]; then
                # Check if target_user is in the users array for this shared folder
                local users=$(echo "$sf" | jq -r '.users[]')
                if echo "$users" | grep -qx "$target_user"; then
                    translated_path="$piped_path"
                    if [ -f "$piped_path" ]; then
                        translated_path=$(dirname "$translated_path")
                    fi
                    echo "$translated_path"
                    return 0
                fi
            fi
        fi
    done <<< "$shared"

    return 1
}

check_and_translate_path() {
    local piped_path="$1"
    local target_user="$2"

    piped_path=$(echo "$piped_path" | xargs)
    if [ -z "$piped_path" ]; then
        echo -e "${RED}Error: Path is empty.${NC}" >&2
        return 1
    fi

    # Try to resolve absolute path
    if [[ ! "$piped_path" == /* ]]; then
        piped_path="$(pwd)/$piped_path"
    fi
    if command -v realpath &>/dev/null; then
        piped_path=$(realpath -m "$piped_path")
    fi

    local translated

    # Check mounts first
    if translated=$(check_and_translate_mount "$piped_path" "$target_user"); then
        echo "$translated"
        return 0
    fi

    # Check shared directories
    if translated=$(check_and_translate_shared "$piped_path" "$target_user"); then
        echo "$translated"
        return 0
    fi

    echo -e "${RED}Path '$piped_path' is not accessible (not mounted or shared) for user '$target_user'.${NC}" >&2
    return 1
}

# Main Loop
main() {
    check_dependencies
    ensure_state_schema

    HAS_CLI_ARGS=false
    local CMD_START_SHELL=false
    local CMD_COMMAND=""
    local CMD_USER=""
    local CMD_PATH=""

    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        HAS_CLI_ARGS=true
        case $1 in
            -s|--start-shell)
                CMD_START_SHELL=true
                shift
                ;;
            -c|--command)
                CMD_COMMAND="$2"
                shift 2
                ;;
            -u|--user)
                CMD_USER="$2"
                shift 2
                ;;
            -p|--path)
                CMD_PATH="$2"
                shift 2
                ;;
            *)
                echo "Unknown parameter passed: $1"
                exit 1
                ;;
        esac
    done

    # Check for piped input (overrides explicit path)
    if [ ! -t 0 ]; then
        local piped_data
        read -r piped_data
        # Reconnect stdin to terminal so interactive prompts (like read, sudo) work
        exec < /dev/tty

        if [ -n "$piped_data" ]; then
            piped_data=$(echo "$piped_data" | xargs)
            CMD_PATH="$piped_data"
            HAS_CLI_ARGS=true
            # If no action specified, default to shell
            if [ "$CMD_START_SHELL" = false ] && [ -z "$CMD_COMMAND" ]; then
                CMD_START_SHELL=true
            fi
        fi
    fi

    # If any CLI arguments/pipes were used, do not show main menu
    if [ "$HAS_CLI_ARGS" = true ]; then
        # Default to shell if path or user given but no action
        if [ "$CMD_START_SHELL" = false ] && [ -z "$CMD_COMMAND" ]; then
            CMD_START_SHELL=true
        fi

        # Determine target user FIRST
        local target_user=""
        if [ -n "$CMD_USER" ]; then
            # Verify explicitly requested user
            if ! jq -e --arg u "$CMD_USER" '.users[] | select(. == $u)' "$STATE_FILE" >/dev/null; then
                echo -e "${RED}Error: User '$CMD_USER' is not a managed agentic user.${NC}"
                exit 1
            fi
            echo "Using user: $CMD_USER"
            target_user="$CMD_USER"
        else
            echo "No user specified, prompting for user..."
            # Prompt for user if none specified
            target_user=$(select_agentic_user) || exit 1
        fi

        local mapped_path=""
        if [ -n "$CMD_PATH" ]; then
            if ! mapped_path=$(check_and_translate_path "$CMD_PATH" "$target_user"); then
                exit 1
            fi
            echo "Translation result: $mapped_path"
        fi

        start_shell "$target_user" "$mapped_path" "$CMD_COMMAND"
        exit 0
    fi

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
            6) create_shared_directory ;;
            7) mirror_git_config ;;
            8) fix_permissions ;;
            9) list_status ;;
            10) settings_menu ;;
            0) echo "Exiting."; exit 0 ;;
            *) echo -e "${RED}Invalid option.${NC}" ;;
        esac
    done
}

main "$@"

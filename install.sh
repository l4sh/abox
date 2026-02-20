#!/usr/bin/env bash

set -e

BIN_DIR="$HOME/.local/bin"
REPO_DIR="$HOME/.abox"
REPO_URL="https://github.com/l4sh/abox.git"

check_dependencies() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Error: 'git' is required but not installed."
        exit 1
    fi
}

check_and_create_bin_dir() {
    if [ ! -d "$BIN_DIR" ]; then
        echo "Directory $BIN_DIR does not exist. Creating it now..."
        mkdir -p "$BIN_DIR"
    fi
}

check_path() {
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo ""
        echo "================================================================================"
        echo " NOTICE: $BIN_DIR is not in your PATH."
        echo " To use the script from anywhere without specifying the path, please add"
        echo " $BIN_DIR to your PATH."
        echo ""
        echo " For Bash or Zsh, add this to your ~/.bashrc or ~/.zshrc:"
        echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        echo " For Fish shell, run this command:"
        echo "   fish_add_path ~/.local/bin"
        echo "================================================================================"
        echo ""
    fi
}

create_symlink() {
    local target_file="$1"

    if [ ! -f "$target_file" ]; then
        echo "Error: Target file $target_file does not exist. Cannot create symlink."
        exit 1
    fi

    echo "Creating symlink for $target_file in $BIN_DIR..."
    ln -sf "$target_file" "$BIN_DIR/abox.sh"

    ln -sf "$target_file" "$BIN_DIR/abox"
}

main() {
    check_dependencies
    check_and_create_bin_dir

    if [ -f "./abox.sh" ]; then
        echo "Found abox.sh in current directory."
        abs_path=$(readlink -f "./abox.sh")
        create_symlink "$abs_path"
    else
        echo "abox.sh not found in the current directory."
        if [ -d "$REPO_DIR/.git" ]; then
            echo "Found git repository at $REPO_DIR."
            echo "Updating repository..."
            git -C "$REPO_DIR" pull
            create_symlink "$REPO_DIR/abox.sh"
        else
            echo "Repository not found at $REPO_DIR."
            echo "Cloning $REPO_URL into $REPO_DIR..."
            git clone "$REPO_URL" "$REPO_DIR"
            create_symlink "$REPO_DIR/abox.sh"
        fi
    fi

    check_path

    echo "Installation complete."
}

main

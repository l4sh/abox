# abox

User based sandboxing for AI agents (or other use cases where a restricted user is needed)

`abox` is a tool designed to create, manage, and sandbox restricted users ("agentic users") on your Linux system. It allows you to safely mount specific directories for these agents with strict Access Control Lists (ACLs) and easily drop into their isolated shell environments, providing a secure space for AI agents to operate without compromising your host system.

**Warning:** `abox` is a work in progress and is not yet ready for production use. No warranty is provided. Use at your own risk.

**Note:** Mounts are not persisted to `/etc/fstab` or similar. Although state is persisted across reboots. If you require mounts to persist across reboots, you will need to add them to `/etc/fstab` manually.

## Installation

You can install `abox` directly via `curl` and `bash`:

```bash
curl -sSL https://raw.githubusercontent.com/l4sh/abox/master/install.sh | bash
```

Alternatively, you can clone the repository and run the installation script manually:

```bash
git clone https://github.com/l4sh/abox.git ~/.abox
cd ~/.abox
./install.sh
```

**Note:** To update `abox` to the latest version, simply rerun the install script. It will automatically pull the latest changes and update the symlinks.

## Dependencies

`abox` requires the following dependencies to be installed on your system:
- `acl` (for `setfacl`)
- `jq` (for state management)
- `xhost` (for X11 forwarding if applicable)
- `git` (for installation and updates)

## Usage

You can use `abox` either through its interactive Text User Interface (TUI) or via Command Line Interface (CLI) arguments.

### Interactive Mode (TUI)

Simply run `abox` without any arguments to enter the interactive menu:

```
  █████╗ ██████╗  ██████╗ ██╗  ██╗
 ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝
 ███████║██████╔╝██║   ██║ ╚███╔╝
 ██╔══██║██╔══██╗██║   ██║ ██╔██╗
 ██║  ██║██████╔╝╚██████╔╝██╔╝ ██╗
 ╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝
========================================
User based sandboxing for AI agents
========================================

1. Start Shell (as Agentic User)
2. Create Agentic User
3. Remove Agentic User
4. Mount Directory
5. Unmount Directory
6. List Status
7. Advanced
0. Exit

Choose an option:
```

1. **Start Shell**: Drop into a bash shell as a selected agentic user.
2. **Create Agentic User**: Create a new sandboxed user (e.g., `agentic-user-1`).
3. **Remove Agentic User**: Delete an agentic user and their home directory.
4. **Mount Directory**: Bind mount a specific host directory into the agent's home directory with secure ACLs.
5. **Unmount Directory**: Safely unmount a directory and clean up the ACLs.
6. **List Status**: View currently managed agentic users and active mount points.
7. **Advanced**: Undo all changes (unmounts all directories, removes all ACLs, and deletes all agentic users).

### CLI Mode

You can bypass the TUI using the following arguments:

```bash
abox [OPTIONS]
```

**Options:**
- `-s, --start-shell`
  Start an interactive shell session as an agentic user.
- `-c, --command '<command>'`
  Execute a specific command as the agentic user instead of starting an interactive shell.
- `-u, --user '<username>'`
  Specify which agentic user to use for the session.
- `-p, --path '<path>'`
  Specify a host path. `abox` will translate this path and start the shell/command in the corresponding mounted directory inside the agent's environment.

**Examples:**

Start a shell as a specific user:
```bash
abox -s -u agentic-user-1
```

Run a command inside a specific path mapped to the agent:
```bash
abox -c "ls -la" -p /home/hostuser/projects/my-app -u agentic-user-1
```

### Piped Input

`abox` also supports receiving paths via standard input (pipes). It attempts to automatically map the piped host path to the correct agent user and directory.

```bash
echo "/absolute/path/to/project" | abox -s
```

### Cool examples

#### Open worktree from lazyworktree

Runs `lazyworktree` and open the selected worktree in a new shell as an agentic user:

```
lazyworktree --output-selection /dev/shm/lwt_sel > /dev/tty && cat /dev/shm/lwt_sel | abox
```

as a git alias run as `git wt`

```
[alias]
    # ...
    wtabox = "!f() { lazyworktree --output-selection /dev/shm/lwt_sel > /dev/tty && cat /dev/shm/lwt_sel | abox; }; f"
```

#### Git alias to run abox in current directory

run as `git abox`

```
[alias]
    # ...
    abox = !abox -s -p .
```
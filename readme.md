# Bare Dotfiles CLI

A minimal, zero-dependency `Bash CLI` tool to back up, sync, and deploy your development configuration files (dotfiles) using a native Bare Git Repository.

This method keeps your home directory clean by isolating Git tracking metadata inside a hidden folder, allowing you to manage configuration files directly from your home path without relying on complex symlink trees or heavy framework tools.

## Critical Requirement: SSH Authentication

> [!WARNING]
> You must use SSH key authentication for your Git remote repository (GitHub, GitLab, Gitea, etc.) rather than HTTPS.

Because this tool is designed to run non-interactively on fresh installations and via background cron automation, HTTPS connections will fail when Git pauses to prompt you for a username, password, or personal access token. Ensure your remote URLs look like `git@github.com:username/repo.git` and that your SSH keys are properly configured on your machine before running this tool.

---

## Features

- **Isolated Metadata:** Keeps your home directory clean by storing Git data in `~/.dotfiles`.
- **Automatic Placement:** Deploys tracked files precisely to their proper target destinations (~/.bashrc, ~/.config/nvim/, etc.) instantly.
- **Conflict Safeguards:** Automatically detects pre-existing system configuration files and moves them out of the way into a timestamped backup folder before completing setups.
- **Built-in Automation:** Includes an auto-sync command designed for background cron jobs to seamlessly commit and push local changes if modifications are detected.

---

## Installation and Quick Start

### 1. Install the CLI tool
Clone or download the `dotfiles` script, give it executable permissions, and place it inside your system path:

```bash
chmod +x dotfiles
mv dotfiles ~/.local/bin/
```
*(Make sure `~/.local/bin` is included in your shell's `$PATH` variable).*

### 2. First-Time Backup Setup (Machine A)
Initialize your configuration repository and map it directly to your remote repository provider:

```bash
# Initialize with your SSH Git repository URL
dotfiles init git@github.com:yourusername/dotfiles.git

# Track your desired configuration files
dotfiles add .bashrc
dotfiles add .config/nvim/init.lua

# Save (auto-commits and pushes in one step)
dotfiles save

# Or with a custom message
dotfiles save "Initial dotfiles backup"
```

---

## Deploying to a New Machine (Machine B)

On a completely fresh system, download the executable, ensure your SSH key is authorized with your Git host, and issue the restore command. The CLI automatically moves conflicting default files into a safe location and drops your configs into their exact required directories:

```bash
dotfiles restore git@github.com:yourusername/dotfiles.git
```

---

## Automated Background Backups

The CLI features an `auto-sync` function that checks tracked files for modifications. If changes are detected, it builds an automated commit and pushes it silently to your remote server.

### Setting up Cron Automation
To run checks in the background automatically (e.g., daily at midnight), edit your system crontab:

```bash
crontab -e
```

Append the following line (replace `yourusername` with your actual system username):

```cron
0 0 * * * /home/yourusername/.local/bin/dotfiles auto-sync >> /home/yourusername/.dotfiles_sync.log 2>&1
```

*(Note: If your SSH key requires a password/passphrase, you will need to look into exporting your `SSH_AUTH_SOCK` environment variable to cron so the background script can access your active SSH agent).*

---

## CLI Reference Directory

| Command | Action |
| :--- | :--- |
| `dotfiles init <url>` | Instantiates a clean bare repo at `~/.dotfiles` and maps the remote origin. |
| `dotfiles restore <url>` | Clones metadata and moves conflicting local configurations into a backup folder before deployment. |
| `dotfiles add <paths...>` | Stages configurations relative to your home directory. |
| `dotfiles save [msg]` | Commits and pushes in one step. Auto-generates a message if omitted. |
| `dotfiles list` | Lists all tracked (backed up) files. |
| `dotfiles status` | Reviews modifications across your explicitly tracked files. |
| `dotfiles commit "<msg>"`| Creates a local snapshot save-point (without pushing). |
| `dotfiles push` | Syncs local configurations upstream to your remote branch. |
| `dotfiles auto-sync` | Scans for file edits, snapshots, and updates your remote silently. |
| `dotfiles git <args...>` | Runs standard git commands inside your bare setup context (e.g., `dotfiles git log`). |


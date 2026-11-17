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
- **Failure-Only Notifications:** Auto-sync stays silent on success and alerts you only when something goes wrong, via Slack or cron's local mail.

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

When run non-interactively (e.g., from cron), `auto-sync` produces **no output on success**. If any step fails (checking for changes, staging, committing, or pushing), it reports which step failed along with Git's output and exits with a non-zero status. Progress messages are still shown when you run it from a terminal.

### Setting up Cron Automation
To run checks in the background automatically (e.g., daily at midnight), edit your system crontab:

```bash
crontab -e
```

Append the following line (replace `yourusername` with your actual system username):

```cron
0 0 * * * /home/yourusername/.local/bin/dotfiles auto-sync > /dev/null
```

Cron emails any output a job produces to your local mailbox. Since `auto-sync` is silent on success, you'll only receive mail when something goes wrong. If you'd rather keep a log file instead of mail, redirect both streams:

```cron
0 0 * * * /home/yourusername/.local/bin/dotfiles auto-sync >> /home/yourusername/.dotfiles_sync.log 2>&1
```

*(Note: If your SSH key requires a password/passphrase, you will need to look into exporting your `SSH_AUTH_SOCK` environment variable to cron so the background script can access your active SSH agent).*

### Failure Notifications via Slack
Instead of local mail, `auto-sync` can post failures to Slack using a webhook. When a webhook is configured and the message is delivered, nothing is written to cron's mail. If delivery fails, the error falls back to stderr (and therefore cron's local mail), so failures are never lost.

**1. Create a webhook** using either option:

- **Workflow Builder** (usually allowed without admin approval): in Slack, open **Tools → Workflow Builder → New workflow → From a webhook**, add a variable named exactly `text` (type: text), add a **Send a message to a person** step targeting yourself with the `text` variable as the message, then publish and copy the URL (`https://hooks.slack.com/triggers/...`).
- **Incoming Webhook app** (may require admin approval): at <https://api.slack.com/apps>, choose **Create New App → From scratch**, enable **Incoming Webhooks**, click **Add New Webhook**, pick a channel or your DM, and copy the URL (`https://hooks.slack.com/services/...`).

**2. Store the URL** in a private file. Do not track it with `dotfiles add`, as anyone with the URL can post to your Slack:

```bash
mkdir -p ~/.config/dotfiles
echo 'https://hooks.slack.com/...' > ~/.config/dotfiles/slack-webhook-url
chmod 600 ~/.config/dotfiles/slack-webhook-url
```

Alternatively, set the `DOTFILES_SLACK_WEBHOOK` environment variable, which takes precedence over the file.

**3. Verify the setup:**

```bash
dotfiles test-notify
```

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
| `dotfiles auto-sync` | Scans for file edits, snapshots, and updates your remote silently. Reports only on failure. |
| `dotfiles test-notify` | Sends a test notification to the configured Slack webhook. |
| `dotfiles git <args...>` | Runs standard git commands inside your bare setup context (e.g., `dotfiles git log`). |
| `dotfiles version` | Prints the installed version (also `--version` / `-v`). |


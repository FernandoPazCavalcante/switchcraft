# switchcraft 🪄

**switch** + witch**craft** — the magic of switching accounts without doing a thing.

A multi-account dev environment (GitHub + Claude Code) where **the directory
defines the identity**:

```
~/projects/
├── account-a/   → commits with GitHub account A + Claude Code logged into account A
└── account-b/   → commits with GitHub account B + Claude Code logged into account B
```

No manual switching, no incantations: enter the folder and the spell is
already cast. Both accounts work in parallel (different terminals) without
conflict.

## How it works

| Layer                     | Mechanism                                                               |
| ------------------------- | ----------------------------------------------------------------------- |
| Git identity (name/email) | `includeIf "gitdir:..."` in `~/.gitconfig`                              |
| SSH key per account       | `core.sshCommand` in each profile (remotes stay plain `git@github.com`) |
| Claude Code account       | `CLAUDE_CONFIG_DIR` exported via `.envrc` (direnv) per directory        |

## Usage on a new machine

```bash
# First time only: edit setup.conf with your names/emails
./install.sh
```

The script is **idempotent** (you can run it again after changing `setup.conf`) and does:

1. Installs/configures **direnv** and adds the hook to your shell rc.
2. Generates each account's **SSH keys**, _if they don't already exist_ on this machine
   (private keys are never versioned — each machine has its own).
3. Writes the git profiles to `~/.config/git-profiles/` and the `includeIf`
   block in `~/.gitconfig` (between markers, without duplicating).
4. Creates `~/projects/account-a` and `~/projects/account-b` with their `.envrc`
   pointing to `~/.claude-account-a` and `~/.claude-account-b`.

## Manual steps (once per machine)

1. Register the public keys (`~/.ssh/id_ed25519_*.pub`) on each GitHub account.
2. Log in to Claude Code in each profile:
   ```bash
   CLAUDE_CONFIG_DIR=~/.claude-account-a claude
   CLAUDE_CONFIG_DIR=~/.claude-account-b claude
   ```
3. Reopen the terminal.

## Quick check

```bash
cd ~/projects/account-a && git init test && cd test
git config user.email      # → account A's email
echo $CLAUDE_CONFIG_DIR    # → /home/you/.claude-account-a
ssh -i ~/.ssh/id_ed25519_account-a -o IdentitiesOnly=yes -T git@github.com  # → "Hi user-a!"
```

## What NEVER goes into this repository

- Private SSH keys (`~/.ssh/id_ed25519_*`)
- Claude Code credentials (`~/.claude-*/`)
- Tokens of any kind

The repo versions only **structure and templates** — secrets are generated/obtained
per machine. That's why it can even be public (but if `setup.conf` has
emails you don't want to expose, keep it private).

## Customizing

- Always clone via **SSH** (`git@github.com:...`); HTTPS remotes don't use the keys.
- To share `settings.json`/`CLAUDE.md` between the two Claude Code
  profiles, create symlinks between `~/.claude-account-a` and `~/.claude-account-b`.
- For a 3rd account, add the variables to `setup.conf`, a new template, and
  replicate the corresponding lines in `install.sh`.

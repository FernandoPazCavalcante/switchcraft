# switchcraft 🪄

**switch** + witch**craft** — the magic of switching accounts without doing a thing.

For developers working across **multiple organizations at the same time** — a
day job and a client, an employer and your own side projects — where every
context has its own GitHub account, its own SSH key and its own Claude Code
login. Forget to switch once and you push a commit signed with the wrong
identity to the wrong org.

switchcraft makes **the directory define the identity**:

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
| Commit signing            | `user.signingkey` per profile + global `gpg.format = ssh`               |
| Claude Code account       | `CLAUDE_CONFIG_DIR` exported via `.envrc` (direnv) per directory        |

Commits are signed with the same SSH key that authenticates the account — no
GPG to manage. Enable it globally once:

```bash
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```

## Usage on a new machine

```bash
# First time only: copy the example and fill in your names/emails (and optional tokens)
cp .env.example .env
./install.sh
```

`.env` is gitignored — personal data and tokens live only there. `.env.example`
documents every variable.

The script is **idempotent** (you can run it again after changing `.env`) and does:

1. Installs/configures **direnv** and adds the hook to your shell rc.
2. Generates each account's **SSH keys**, _if they don't already exist_ on this machine
   (private keys are never versioned — each machine has its own).
3. Writes the git profiles to `~/.config/git-profiles/` and the `includeIf`
   block in `~/.gitconfig` (between markers, without duplicating).
4. Creates `~/projects/account-a` and `~/projects/account-b` with their `.envrc`
   pointing to `~/.claude-account-a` and `~/.claude-account-b`.

## Manual steps (once per machine)

1. Register the public keys (`~/.ssh/id_ed25519_*.pub`) on each GitHub account.
   Add each key **twice**: once as an *Authentication key* (clone/push) and once
   as a *Signing key* (so commits show as Verified).
2. Reopen the terminal, so the direnv hook loads.
3. Log in to Claude Code once per profile, from inside the account's folder:
   ```bash
   cd ~/projects/account-a && claude   # /login, then exit with /exit
   cd ~/projects/account-b && claude   # /login, then exit with /exit
   ```
   ⚠️ **Do not Ctrl+C after logging in.** Credentials are flushed to disk on a
   graceful shutdown; SIGINT kills the process first and the login is silently
   lost — the next session starts unauthenticated again. Wait for the prompt,
   then leave with `/exit` (or Ctrl+D).

   Confirm it persisted:
   ```bash
   ls -l ~/.claude-account-a/.credentials.json
   grep -o '"emailAddress":"[^"]*"' ~/.claude-account-a/.claude.json
   ```

## Quick check

```bash
cd ~/projects/account-a && git init test && cd test
git config user.email       # → account A's email
git config user.signingkey  # → ~/.ssh/id_ed25519_account-a.pub
echo $CLAUDE_CONFIG_DIR     # → /home/you/.claude-account-a
ssh -i ~/.ssh/id_ed25519_account-a -o IdentitiesOnly=yes -T git@github.com  # → "Hi user-a!"
```

## Gotchas

- **`cd` inside a running Claude session does not switch accounts.** Environment
  variables are fixed when the process starts, so direnv cannot retroactively
  change a live session. Exit and start `claude` again from the target folder.
- **Signatures show as "No signature" in local `git log`** until you configure
  `gpg.ssh.allowedSignersFile`. GitHub verifies against the uploaded signing
  keys regardless, so this is cosmetic.
- **Each Claude profile starts empty** — no shared history, rules or plugins.
  See *Customizing* below to share the parts you want.

## What NEVER goes into this repository

- Private SSH keys (`~/.ssh/id_ed25519_*`)
- Claude Code credentials (`~/.claude-*/`)
- Tokens of any kind

- Your names/emails/tokens (they live in the gitignored `.env`)

The repo versions only **structure and templates** — secrets are generated/obtained
per machine. That's why it can even be public.

## Customizing

- Always clone via **SSH** (`git@github.com:...`); HTTPS remotes don't use the keys.
- To share config between the Claude Code profiles, symlink the pieces you want
  from one profile into the other:
  ```bash
  cd ~/.claude-account-b
  for f in CLAUDE.md rules agents skills plugins settings.json; do
    ln -sfn ~/.claude-account-a/$f $f
  done
  ```
  Never symlink `.credentials.json`, `.claude.json`, `projects/` or
  `history.jsonl` — those are what keep the accounts and their conversation
  history separate. Note that a shared `plugins/` means installing a plugin in
  one profile changes both.
- If one account should simply reuse your existing `~/.claude` setup, point the
  whole profile at it: `ln -s ~/.claude ~/.claude-account-a`. Bear in mind
  `/logout` there then logs out your main profile too.
- For a 3rd account, add its prefix to `PROFILES` in `.env` (e.g.
  `PROFILES="A B C"`) plus the `C_*` variables, and rerun `./install.sh`.
  No template or `install.sh` changes needed.

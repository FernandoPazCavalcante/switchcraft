#!/usr/bin/env bash
# ============================================================
# install.sh — bootstrap for the multi-account dev environment
# (GitHub + Claude Code per directory)
#
# Idempotent: run it as many times as you want.
# Usage:  git clone git@github.com:YOU/switchcraft.git && cd switchcraft
#         cp .env.example .env   # fill in your data
#         ./install.sh
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$REPO_DIR/.env" ]] || { echo "Missing .env — run: cp .env.example .env and fill it in." >&2; exit 1; }
source "$REPO_DIR/.env"
PROFILES="${PROFILES:-A B}"

[[ -n "${PROJECTS_ROOT:-}" ]] || { echo "Missing PROJECTS_ROOT — run: cp .env.example .env and fill it in." >&2; exit 1; }
for P in $PROFILES; do
  for suffix in SLUG GIT_NAME GIT_EMAIL GITHUB_USER; do
    v="${P}_${suffix}"
    [[ -n "${!v:-}" ]] || { echo "Missing $v — run: cp .env.example .env and fill it in." >&2; exit 1; }
  done
done

info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m ✓\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m !\033[0m %s\n" "$*"; }

# ------------------------------------------------------------
# 0. Detect shell rc
# ------------------------------------------------------------
SHELL_RC="$HOME/.bashrc"
[[ "${SHELL:-}" == *zsh* ]] && SHELL_RC="$HOME/.zshrc"

# ------------------------------------------------------------
# 1. direnv
# ------------------------------------------------------------
info "Checking direnv..."
if ! command -v direnv >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install direnv || warn "Failed to install direnv via brew"
  elif command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y direnv || warn "Failed to install direnv via apt"
  elif command -v sudo >/dev/null 2>&1 && command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm direnv || warn "Failed to install direnv via pacman"
  else
    warn "Install direnv manually: https://direnv.net/docs/installation.html"
  fi
fi
if command -v direnv >/dev/null 2>&1; then
  HOOK_LINE='eval "$(direnv hook '"$(basename "${SHELL:-bash}")"')"'
  grep -qF "direnv hook" "$SHELL_RC" 2>/dev/null || {
    printf "\n# direnv (switchcraft)\n%s\n" "$HOOK_LINE" >> "$SHELL_RC"
    ok "direnv hook added to $SHELL_RC"
  }
fi

# ------------------------------------------------------------
# 2. SSH keys (generated per machine — NEVER versioned)
# ------------------------------------------------------------
info "Checking SSH keys..."
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
gen_key() {
  local slug="$1" email="$2" keyfile="$HOME/.ssh/id_ed25519_$1"
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    warn "ssh-keygen not found; install openssh-client and run again."
    return 0
  fi
  if [[ ! -f "$keyfile" ]]; then
    ssh-keygen -t ed25519 -C "$email" -f "$keyfile" -N ""
    ok "Key created: $keyfile"
    warn "Add the public key below to the corresponding GitHub account:"
    echo "------------------------------------------------------------"
    cat "$keyfile.pub"
    echo "------------------------------------------------------------"
  else
    ok "Key already exists: $keyfile"
  fi
}
for P in $PROFILES; do
  SLUG_V="${P}_SLUG" EMAIL_V="${P}_GIT_EMAIL"
  gen_key "${!SLUG_V}" "${!EMAIL_V}"
done

# ------------------------------------------------------------
# 3. Git: profiles + conditional include per directory
# ------------------------------------------------------------
info "Configuring git profiles..."
render() { # render <slug> <name> <email> <destination> — substitutes {{VARS}}
  local slug="$1" name="$2" email="$3" dst="$4"
  sed -e "s|{{PROJECTS_ROOT}}|$PROJECTS_ROOT|g" \
      -e "s|{{SLUG}}|$slug|g" \
      -e "s|{{NAME}}|$name|g" \
      -e "s|{{EMAIL}}|$email|g" \
      -e "s|{{HOME}}|$HOME|g" \
      "$REPO_DIR/templates/gitconfig-profile" > "$dst"
}

mkdir -p "$HOME/.config/git-profiles"
for P in $PROFILES; do
  SLUG_V="${P}_SLUG" NAME_V="${P}_GIT_NAME" EMAIL_V="${P}_GIT_EMAIL"
  render "${!SLUG_V}" "${!NAME_V}" "${!EMAIL_V}" "$HOME/.config/git-profiles/${!SLUG_V}"
done

# Includes block in ~/.gitconfig (between markers, so it's re-runnable)
GITCONFIG="$HOME/.gitconfig"
touch "$GITCONFIG"
TMP="$(mktemp)"
awk '/# >>> switchcraft >>>/{skip=1} /# <<< switchcraft <<</{skip=0; next} !skip' "$GITCONFIG" > "$TMP"
{
  echo "# >>> switchcraft >>>"
  for P in $PROFILES; do
    SLUG_V="${P}_SLUG" SLUG="${!SLUG_V}"
    printf '[includeIf "gitdir:%s/%s/"]\n    path = %s/.config/git-profiles/%s\n' \
      "$PROJECTS_ROOT" "$SLUG" "$HOME" "$SLUG"
  done
  echo "# <<< switchcraft <<<"
} >> "$TMP"
mv "$TMP" "$GITCONFIG"
ok "Conditional includes written to ~/.gitconfig"

# ------------------------------------------------------------
# 3b. Arquivos .git-credentials por conta (remotes HTTPS)
# ------------------------------------------------------------
info "Checking .git-credentials..."
for P in $PROFILES; do
  SLUG_V="${P}_SLUG" USER_V="${P}_GITHUB_USER" TOKEN_V="${P}_GITHUB_TOKEN"
  SLUG="${!SLUG_V}" GHUSER="${!USER_V}" TOKEN="${!TOKEN_V:-}"
  CRED="$PROJECTS_ROOT/$SLUG/.git-credentials"
  mkdir -p "$PROJECTS_ROOT/$SLUG"
  if [[ -n "$TOKEN" ]]; then
    touch "$CRED" && chmod 600 "$CRED"
    printf 'https://%s:%s@github.com\n' "$GHUSER" "$TOKEN" > "$CRED"
    ok "Filled from .env: $CRED"
  elif [[ -f "$CRED" ]]; then
    chmod 600 "$CRED"
    ok "Already exists: $CRED"
  else
    touch "$CRED" && chmod 600 "$CRED"
    warn "Created new empty: $CRED"
    warn "  Fill with: https://USER:TOKEN@github.com  (or set ${P}_GITHUB_TOKEN in .env)"
    warn "  Or just 'git push' HTTPS inside the account folder."
  fi
done

# ------------------------------------------------------------
# 4. Project structure + .envrc (Claude Code per directory)
# ------------------------------------------------------------
info "Creating project structure and .envrc..."
for P in $PROFILES; do
  SLUG_V="${P}_SLUG" SLUG="${!SLUG_V}"
  DIR="$PROJECTS_ROOT/$SLUG"
  mkdir -p "$DIR" "$HOME/.claude-$SLUG"
  cat > "$DIR/.envrc" <<EOF
# Generated by switchcraft — account: $SLUG
export CLAUDE_CONFIG_DIR=\$HOME/.claude-$SLUG
EOF
  command -v direnv >/dev/null 2>&1 && direnv allow "$DIR" >/dev/null 2>&1 || true
  ok "$DIR ready (.envrc + ~/.claude-$SLUG)"
done

# ------------------------------------------------------------
# 5. Summary / next manual steps
# ------------------------------------------------------------
cat <<EOF

============================================================
 Setup complete. Manual steps (once per machine):
============================================================
 1. Add the public keys to the GitHub accounts:
EOF
for P in $PROFILES; do
  SLUG_V="${P}_SLUG" USER_V="${P}_GITHUB_USER"
  echo "      ~/.ssh/id_ed25519_${!SLUG_V}.pub  → account ${!USER_V}"
done
FIRST_P="${PROFILES%% *}" FIRST_SLUG_V="${FIRST_P}_SLUG"
cat <<EOF
    Test:  ssh -i ~/.ssh/id_ed25519_${!FIRST_SLUG_V} -o IdentitiesOnly=yes -T git@github.com

 2. Log in to Claude Code in each profile:
EOF
for P in $PROFILES; do
  SLUG_V="${P}_SLUG"
  echo "      CLAUDE_CONFIG_DIR=~/.claude-${!SLUG_V} claude   # login account $P"
done
cat <<EOF

 3. Reopen the terminal (so the direnv hook loads).

 After that: any repo inside $PROJECTS_ROOT/<slug>
 commits and uses Claude as that account.
============================================================
EOF

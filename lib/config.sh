#!/usr/bin/env bash
# shellcheck shell=bash
# config.sh — read/write ~/.config/switchcraft/config
#
# The config is data, not shell: it is parsed, never sourced, so a stray
# backtick in a display name cannot execute. Format:
#
#   projects_root = /home/you/projects
#   sign_commits  = true
#
#   [profile work]
#   name        = Your Name
#   email       = you@company.com
#   github_user = you-at-work
#   dir         = /home/you/projects/work      # repeatable
#   remote      = git@github.com:company/*     # repeatable
#   token_cmd   = pass show github/work        # optional, printed to stdout

sc_cfg_path() {
	printf '%s\n' "${SWITCHCRAFT_CONFIG:-$(sc_xdg_config)/switchcraft/config}"
}

sc_cfg_exists() { [[ -f "$(sc_cfg_path)" ]]; }

sc_cfg_require() {
	sc_cfg_exists || die "no config yet — run: switchcraft init"
}

# Shared awk helper: turns "[profile work]" into "work", anything else into "".
_SC_AWK_SEC='
function secname(s) {
  if (s !~ /^[[:space:]]*\[profile[[:space:]]+/) return ""
  sub(/^[[:space:]]*\[profile[[:space:]]+/, "", s)
  sub(/[[:space:]]*\][[:space:]]*$/, "", s)
  return s
}
function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
'

# sc_cfg_get_all <profile|""> <key> — every value for a key ("" = global keys).
sc_cfg_get_all() {
	local profile="$1" key="$2"
	sc_cfg_exists || return 0
	awk -v want="$profile" -v key="$key" "$_SC_AWK_SEC"'
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[/ { cur = secname($0); next }
    index($0, "=") == 0 { next }
    cur != want { next }
    {
      k = $0; sub(/=.*/, "", k)
      v = $0; sub(/^[^=]*=/, "", v)
      k = trim(k); v = trim(v)
      sub(/[[:space:]]+#.*$/, "", v)
      if (k == key && v != "") print v
    }
  ' "$(sc_cfg_path)"
}

# sc_cfg_get <profile> <key> [default] — first value only.
sc_cfg_get() {
	local v
	v="$(sc_cfg_get_all "$1" "$2" | head -n 1)"
	[[ -n "$v" ]] && printf '%s\n' "$v" && return 0
	[[ -n "${3:-}" ]] && printf '%s\n' "$3"
	return 0
}

sc_cfg_global() { sc_cfg_get "" "$1" "${2:-}"; }

sc_cfg_profiles() {
	sc_cfg_exists || return 0
	awk "$_SC_AWK_SEC"'
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[/ { s = secname($0); if (s != "") print s }
  ' "$(sc_cfg_path)"
}

sc_cfg_has() {
	local p
	while IFS= read -r p; do [[ "$p" == "$1" ]] && return 0; done < <(sc_cfg_profiles)
	return 1
}

sc_cfg_require_profile() {
	sc_cfg_has "$1" || die "unknown profile '$1' — see: switchcraft list"
}

sc_cfg_init() {
	local root="$1" sign="$2"
	sc_write "$(sc_cfg_path)" 600 <<EOF
# switchcraft configuration — https://github.com/FernandoPazCavalcante/switchcraft
# Edit by hand or through: switchcraft add / link / unlink
projects_root = $root
sign_commits  = $sign
EOF
}

# sc_cfg_append <profile|""> <key> <value> — add a line inside a section.
sc_cfg_append() {
	local profile="$1" key="$2" val="$3" body
	body="$(SC_CFG_VALUE="$val" awk -v want="$profile" -v key="$key" "$_SC_AWK_SEC"'
    /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
    /^[[:space:]]*\[/ {
      if (cur == want && !done) { print key " = " ENVIRON["SC_CFG_VALUE"]; done = 1 }
      printf "%s", blanks; blanks = ""
      cur = secname($0); print; next
    }
    { printf "%s", blanks; blanks = ""; print }
    END {
      if (cur == want && !done) print key " = " ENVIRON["SC_CFG_VALUE"]
      printf "%s", blanks
    }
  ' "$(sc_cfg_path)")"
	printf '%s\n' "$body" | sc_write "$(sc_cfg_path)" 600
}

# sc_cfg_set <profile|""> <key> <value> — replace a single-valued key.
sc_cfg_set() {
	local profile="$1" key="$2" val="$3" body
	body="$(SC_CFG_VALUE="$val" awk -v want="$profile" -v key="$key" "$_SC_AWK_SEC"'
    /^[[:space:]]*\[/ { cur = secname($0); print; next }
    {
      if (cur == want && index($0, "=") > 0) {
        k = $0; sub(/=.*/, "", k)
        if (trim(k) == key) {
          if (!done) { print key " = " ENVIRON["SC_CFG_VALUE"]; done = 1 }
          next
        }
      }
      print
    }
  ' "$(sc_cfg_path)")"
	printf '%s\n' "$body" | sc_write "$(sc_cfg_path)" 600
	grep -q . <<<"$(sc_cfg_get_all "$profile" "$key")" || sc_cfg_append "$profile" "$key" "$val"
}

# sc_cfg_remove_value <profile> <key> <value>
sc_cfg_remove_value() {
	local profile="$1" key="$2" val="$3" body
	body="$(awk -v want="$profile" -v key="$key" -v val="$val" "$_SC_AWK_SEC"'
    /^[[:space:]]*\[/ { cur = secname($0); print; next }
    {
      if (cur == want && index($0, "=") > 0) {
        k = $0; sub(/=.*/, "", k)
        v = $0; sub(/^[^=]*=/, "", v)
        if (trim(k) == key && trim(v) == val) next
      }
      print
    }
  ' "$(sc_cfg_path)")"
	printf '%s\n' "$body" | sc_write "$(sc_cfg_path)" 600
}

sc_cfg_add_profile() {
	local name="$1" body
	body="$(
		cat "$(sc_cfg_path)"
		printf '\n[profile %s]\n' "$name"
	)"
	printf '%s\n' "$body" | sc_write "$(sc_cfg_path)" 600
}

sc_cfg_remove_profile() {
	local name="$1" body
	body="$(awk -v want="$name" "$_SC_AWK_SEC"'
    /^[[:space:]]*\[/ {
      s = secname($0)
      drop = (s == want)
      if (drop) next
      print; next
    }
    drop { next }
    { print }
  ' "$(sc_cfg_path)")"
	printf '%s\n' "$body" | sc_write "$(sc_cfg_path)" 600
}

# sc_cfg_profile_for_dir <abs-dir> — the profile owning the deepest matching
# directory, so a nested link wins over its parent. Prints "" when none.
sc_cfg_profile_for_dir() {
	local target="$1" p d best_p='' best_len=0
	# Both sides canonical, so a lookup from a symlinked path still finds its
	# profile and agrees with the includeIf rule git will apply.
	target="$(sc_real "$target")"
	while IFS= read -r p; do
		[[ -n "$p" ]] || continue
		while IFS= read -r d; do
			[[ -n "$d" ]] || continue
			d="$(sc_real "$d")"
			if [[ "$target" == "$d" || "$target" == "$d"/* ]]; then
				if ((${#d} > best_len)); then
					best_len=${#d}
					best_p="$p"
				fi
			fi
		done < <(sc_cfg_get_all "$p" dir)
	done < <(sc_cfg_profiles)
	printf '%s\n' "$best_p"
}

# Per-profile derived locations. Overridable via claude_dir / gh_dir.
sc_profile_claude_dir() {
	sc_cfg_get "$1" claude_dir "$HOME/.claude-$1"
}
sc_profile_gh_dir() {
	sc_cfg_get "$1" gh_dir "$(sc_xdg_config)/gh-$1"
}
sc_profile_key() { printf '%s\n' "$HOME/.ssh/id_ed25519_$1"; }

# sc_profile_token <profile> — resolves token_cmd, never stores the secret.
sc_profile_token() {
	local cmd
	cmd="$(sc_cfg_get "$1" token_cmd)"
	[[ -n "$cmd" ]] || return 0
	# shellcheck disable=SC2086 # token_cmd is a command line by design
	eval $cmd 2>/dev/null | head -n 1
}

#!/usr/bin/env bats
load test_helper

@test "apply is idempotent" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	cp "$SANDBOX/.gitconfig" "$SANDBOX/first"
	cp "$SANDBOX/projects/work/.envrc" "$SANDBOX/envrc.first"
	sc apply >/dev/null 2>&1
	sc apply >/dev/null 2>&1
	diff -q "$SANDBOX/first" "$SANDBOX/.gitconfig"
	diff -q "$SANDBOX/envrc.first" "$SANDBOX/projects/work/.envrc"
	[ "$(grep -c 'switchcraft >>>' "$SANDBOX/.gitconfig")" -eq 1 ]
}

@test "link binds a directory outside the projects root" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	mkdir -p "$SANDBOX/elsewhere/client"
	run sc link work "$SANDBOX/elsewhere/client"
	[ "$status" -eq 0 ]
	[ -f "$SANDBOX/elsewhere/client/.envrc" ]
	git -C "$SANDBOX/elsewhere/client" init -q
	[ "$(git -C "$SANDBOX/elsewhere/client" config user.email)" = "work@company.com" ]
}

@test "link refuses an unknown profile" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	run sc link nosuch "$SANDBOX/x"
	[ "$status" -ne 0 ]
}

@test "the deepest linked directory wins" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile outer outer@x.com
	add_profile inner inner@x.com
	mkdir -p "$SANDBOX/tree/sub"
	sc link outer "$SANDBOX/tree" >/dev/null 2>&1
	sc link inner "$SANDBOX/tree/sub" >/dev/null 2>&1
	git -C "$SANDBOX/tree/sub" init -q
	[ "$(git -C "$SANDBOX/tree/sub" config user.email)" = "inner@x.com" ]
}

@test "unlink stops managing a directory but keeps its files" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	echo 'keep me' >"$SANDBOX/projects/work/file.txt"
	run sc unlink "$SANDBOX/projects/work"
	[ "$status" -eq 0 ]
	[ -f "$SANDBOX/projects/work/file.txt" ]
	! gitconfig | grep -q "projects/work/"
}

@test "unlink removes a path containing a literal backslash-n sequence" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	local dir="$SANDBOX/elsewhere/work\\new"
	mkdir -p "$dir"
	sc link work "$dir" >/dev/null 2>&1
	grep -Fq "$dir" "$SANDBOX/.config/switchcraft/config"

	run sc unlink "$dir"
	[ "$status" -eq 0 ]
	! grep -Fq "$dir" "$SANDBOX/.config/switchcraft/config"

	run sc status "$dir"
	[ "$status" -eq 0 ]
	[[ "$output" == *"unmanaged"* ]]
}

@test "status reports the profile and warns when unmanaged" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc status "$SANDBOX/projects/work"
	[[ "$output" == *work* ]]
	run sc status "$SANDBOX"
	[[ "$output" == *unmanaged* ]]
}

@test "remove drops the profile and its includeIf" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	add_profile personal me@gmail.com
	run sc remove work
	[ "$status" -eq 0 ]
	! gitconfig | grep -q 'git-profiles/work'
	gitconfig | grep -q 'git-profiles/personal'
	[ ! -f "$SANDBOX/.config/git-profiles/work" ]
	# the key is kept unless --purge
	[ -f "$SANDBOX/.ssh/id_ed25519_work" ]
}

@test "remove --purge deletes the key and config dirs" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc remove work --purge
	[ "$status" -eq 0 ]
	[ ! -e "$SANDBOX/.ssh/id_ed25519_work" ]
	[ ! -e "$SANDBOX/.claude-work" ]
}

@test "uninstall reverses every block it wrote" {
	printf '[alias]\n\tst = status\n' >"$SANDBOX/.gitconfig"
	printf '# my rc\n' >"$SANDBOX/.bashrc"
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc uninstall
	[ "$status" -eq 0 ]
	! grep -q 'switchcraft' "$SANDBOX/.gitconfig"
	grep -q 'st = status' "$SANDBOX/.gitconfig"
	! grep -q 'direnv hook' "$SANDBOX/.bashrc"
	grep -q '# my rc' "$SANDBOX/.bashrc"
	[ ! -e "$SANDBOX/projects/work/.envrc" ]
	[ ! -f "$SANDBOX/.config/git-profiles/work" ]
	# keys and history are kept without --purge
	[ -f "$SANDBOX/.ssh/id_ed25519_work" ]
	[ -f "$SANDBOX/.config/switchcraft/config" ]
}

@test "uninstall --purge removes keys and the config" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc uninstall --purge
	[ "$status" -eq 0 ]
	[ ! -e "$SANDBOX/.ssh/id_ed25519_work" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
}

@test "signing is enabled globally and cleared on uninstall" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	[ "$(git config --global gpg.format)" = "ssh" ]
	[ "$(git config --global commit.gpgsign)" = "true" ]
	[ -f "$SANDBOX/.config/switchcraft/allowed_signers" ]
	grep -q 'namespaces="git"' "$SANDBOX/.config/switchcraft/allowed_signers"
	sc uninstall >/dev/null 2>&1
	[ -z "$(git config --global commit.gpgsign || true)" ]
}

@test "a directory reached through a symlink still gets its identity" {
	# Not exotic: on macOS /var is a symlink to /private/var, so anything under
	# $TMPDIR is reached through one. git resolves the path before matching
	# includeIf, so the rule has to be written canonical.
	mkdir -p "$SANDBOX/real/code"
	ln -s "$SANDBOX/real" "$SANDBOX/via-link"
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	sc link work "$SANDBOX/via-link/code" >/dev/null 2>&1

	git -C "$SANDBOX/via-link/code" init -q
	[ "$(git -C "$SANDBOX/via-link/code" config user.email)" = "work@company.com" ]

	local resolved
	resolved="$(cd "$SANDBOX/real/code" && pwd -P)"
	gitconfig | grep -qF "gitdir:$resolved/"
}

@test "status and unlink work from a symlinked path" {
	mkdir -p "$SANDBOX/real/code"
	ln -s "$SANDBOX/real" "$SANDBOX/via-link"
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	sc link work "$SANDBOX/real/code" >/dev/null 2>&1

	run sc status "$SANDBOX/via-link/code"
	[[ "$output" == *work* ]]
	[[ "$output" != *unmanaged* ]]

	local resolved
	resolved="$(cd "$SANDBOX/real/code" && pwd -P)"
	gitconfig | grep -qF "gitdir:$resolved/"

	run sc unlink "$SANDBOX/via-link/code"
	[ "$status" -eq 0 ]
	# only that directory's rule goes; the profile still owns projects/work
	! gitconfig | grep -qF "gitdir:$resolved/"
	gitconfig | grep -q 'git-profiles/work'
}

@test "apply is idempotent with the terraform layer" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	cp "$(tfrc work)" "$SANDBOX/tfrc.first"
	cp "$SANDBOX/projects/work/.envrc" "$SANDBOX/envrc.first"
	sc apply >/dev/null 2>&1
	sc apply >/dev/null 2>&1
	diff -q "$SANDBOX/tfrc.first" "$(tfrc work)"
	diff -q "$SANDBOX/envrc.first" "$SANDBOX/projects/work/.envrc"
}

@test "remove deletes the generated tfrc but keeps the key" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	[ -f "$(tfrc work)" ]
	run sc remove work
	[ "$status" -eq 0 ]
	# regenerable from tf_token_cmd and it holds a live token, so it goes
	# without waiting for --purge — unlike the key
	[ ! -e "$(tfrc work)" ]
	[ -f "$SANDBOX/.ssh/id_ed25519_work" ]
}

@test "uninstall deletes the generated tfrc" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	run sc uninstall
	[ "$status" -eq 0 ]
	[ ! -e "$(tfrc work)" ]
	[ -f "$SANDBOX/.ssh/id_ed25519_work" ]
}

@test "doctor names what is wrong with the terraform layer" {
	# doctor exits non-zero in the sandbox regardless (no gh login, no key on
	# GitHub), so these assert on the output, never on the status.
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1

	run sc doctor
	[[ "$output" == *"terraform config is 600"* ]]
	[[ "$output" == *"token present for app.terraform.io"* ]]

	# a machine-global login can disagree with the profile, because
	# $HOME/.terraform.d is relocatable by no environment variable
	mkdir -p "$SANDBOX/.terraform.d"
	echo '{}' >"$SANDBOX/.terraform.d/credentials.tfrc.json"
	printf 'plugin_cache_dir = "/x"\n' >"$SANDBOX/.terraformrc"
	run sc doctor
	[[ "$output" == *"machine-global terraform login"* ]]
	[[ "$output" == *".terraformrc is ignored inside managed directories"* ]]

	rm -f "$(tfrc work)"
	run sc doctor
	[[ "$output" == *"terraform config missing"* ]]
}

@test "doctor warns about a TF_TOKEN_ in the environment without printing it" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	TF_TOKEN_app_terraform_io=leakme run sc doctor
	[[ "$output" == *"TF_TOKEN_* is set in your environment"* ]]
	[[ "$output" == *"TF_TOKEN_app_terraform_io in your environment overrides"* ]]
	[[ "$output" != *"leakme"* ]]
}

@test "doctor stops nagging about an rc once tf_rc_extra carries it" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	printf 'plugin_cache_dir = "/x"\n' >"$SANDBOX/.terraformrc"
	run sc doctor
	[[ "$output" == *".terraformrc is ignored inside managed directories"* ]]

	load_libs
	sc_cfg_append work tf_rc_extra "$SANDBOX/.terraformrc"
	run sc doctor
	[[ "$output" != *"is ignored inside managed directories"* ]]
}

@test "a profile without Terraform gets no Terraform diagnostics" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	# the whole section is gated, so someone who does not use the layer is not
	# told about TF_TOKEN_ or a global login they do not care about
	mkdir -p "$SANDBOX/.terraform.d"
	echo '{}' >"$SANDBOX/.terraform.d/credentials.tfrc.json"
	TF_TOKEN_app_terraform_io=leakme run sc doctor
	[[ "$output" != *"TF_TOKEN"* ]]
	[[ "$output" != *"terraform login"* ]]
}

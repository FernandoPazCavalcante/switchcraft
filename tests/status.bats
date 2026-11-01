#!/usr/bin/env bats
load test_helper

@test "status --json reports a managed profile and effective git email" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	mkdir -p "$SANDBOX/projects/work"
	git -C "$SANDBOX/projects/work" init -q
	git -C "$SANDBOX/projects/work" config user.email work@company.com
	export CLAUDE_CONFIG_DIR="$SANDBOX/.claude-work"
	export GH_CONFIG_DIR="$SANDBOX/.config/gh-work"

	run sc status --json "$SANDBOX/projects/work"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"profile": "work"'* ]]
	[[ "$output" == *'"name": "Test User"'* ]]
	[[ "$output" == *'"email": "work@company.com"'* ]]
	[[ "$output" == *'"claude_active": true'* ]]
	[[ "$output" == *'"gh_active": true'* ]]
	[[ "$output" == *'"effective_email": "work@company.com"'* ]]
	[[ "$output" != *'unmanaged'* ]]
}

@test "status --json uses null profile fields for unmanaged directories" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	mkdir -p "$SANDBOX/unmanaged"

	run sc status --json "$SANDBOX/unmanaged"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"profile": null'* ]]
	[[ "$output" == *'"name": null'* ]]
	[[ "$output" == *'"email": null'* ]]
	[[ "$output" == *'"signing_key": null'* ]]
	[[ "$output" == *'"claude_config_dir": null'* ]]
	[[ "$output" == *'"gh_config_dir": null'* ]]
	[[ "$output" == *'"claude_active": false'* ]]
	[[ "$output" == *'"gh_active": false'* ]]
	[[ "$output" == *'"effective_email": null'* ]]
	[[ "$output" != *'bind it with'* ]]
}

@test "status --json escapes quotes and backslashes in profile names" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add weird --name 'A "quote" \ path' --email weird@example.com --dir "$SANDBOX" >/dev/null 2>&1

	run sc status --json "$SANDBOX"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"name": "A \"quote\" \\ path"'* ]]
}

@test "status keeps human-readable output by default" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com

	run sc status "$SANDBOX/projects/work"
	[ "$status" -eq 0 ]
	[[ "$output" == *'profile'* ]]
	[[ "$output" != *'"schema_version"'* ]]
}

# shellcheck shell=bash
# git-style test library, sourced by tests/tNNNN-*.sh: t0NNN on the host
# (they set TEST_STATE), the rest inside a VM (tests/vm-run sets TEST_VM).
# Prints TAP on stdout; the plan comes last ("1..N"), as TAP allows, since
# a test may span reboots:
#
#	if test_stage 1; then
#		test_expect_success 'desc' 'commands'
#		test_reboot
#	fi
#	if test_stage 2; then
#		test_expect_success ...
#		test_done
#	fi
#
# Counters, the stage and anything a test keeps for later stages live in
# $TEST_STATE (persistent /var; the VM disk itself is thrown away per run).

: "${TEST_STATE:?run through tests/vm-run}"
mkdir -p "$TEST_STATE"

# state_get <name> <default>: a counter from $TEST_STATE, or the default
# on the first boot.
state_get() {
	if [ -f "$TEST_STATE/$1" ]; then
		cat "$TEST_STATE/$1"
	else
		echo "$2"
	fi
}

test_count="$(state_get count 0)"
test_failed="$(state_get failed 0)"
test_current_stage="$(state_get stage 1)"

test_save() {
	echo "$test_count" > "$TEST_STATE/count"
	echo "$test_failed" > "$TEST_STATE/failed"
	echo "$test_current_stage" > "$TEST_STATE/stage"
}

# True when this boot runs stage $1.
test_stage() {
	[ "$test_current_stage" = "$1" ]
}

# test_expect_success <description> <commands>: commands run in a subshell;
# their output is shown as TAP comments only when they fail.
test_expect_success() {
	local out status
	test_count=$((test_count + 1))
	out="$( (eval "$2") 2>&1 )"
	status=$?
	if [ "$status" -eq 0 ]; then
		echo "ok $test_count - $1"
	else
		test_failed=$((test_failed + 1))
		echo "not ok $test_count - $1"
		printf '%s\n' "$out" | sed 's/^/#\t/'
	fi
	test_save
}

# test_update <name> <update|commit> [args]: stage a version, its log into
# $TEST_STATE/<name>.log (shown on failure), the staged version into
# $TEST_STATE/<name>.
test_update() {
	local name="$1"
	shift
	"$IMAGE_ID" "$@" > "$TEST_STATE/$name.log" 2>&1 ||
		{ cat "$TEST_STATE/$name.log"; return 1; }
	sed -n "s/^Staged $IMAGE_ID \([0-9]*\);.*/\1/p" \
		"$TEST_STATE/$name.log" > "$TEST_STATE/$name"
	test -s "$TEST_STATE/$name"
}

# Run a command for its output only, as TAP comments (not a test).
test_info() {
	"$@" 2>&1 | sed 's/^/# /'
}

test_reboot() {
	test_current_stage=$((test_current_stage + 1))
	test_save
	echo "# rebooting into stage $test_current_stage"
	systemctl reboot
	exit 0
}

test_done() {
	echo "1..$test_count"
	if [ "$test_failed" -eq 0 ]; then
		echo "# passed all $test_count test(s)"
	else
		echo "# failed $test_failed among $test_count test(s)"
	fi
	echo "# test_done"
	if [ -n "${TEST_VM:-}" ]; then
		systemctl poweroff
	fi
	exit 0
}

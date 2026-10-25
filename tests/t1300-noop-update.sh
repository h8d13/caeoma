#!/bin/bash
# An update that changes nothing (pacman -Q), from the built image, then
# from an in-box one: the running image is never written, the next one
# differs from it only in os-release, the delta stays small. Timings of a
# cold (initrd built) and a warm update.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

image="/system/${IMAGE_ID}_${IMAGE_VERSION}.erofs"

# Paths that differ between images $1 and $2 (content, type, mode, links).
image_diff() {
	local a="$TEST_STATE/a" b="$TEST_STATE/b"
	mkdir -p "$a" "$b" &&
	mount -o ro "$1" "$a" &&
	mount -o ro "$2" "$b" &&
	{
		diff --recursive --brief --no-dereference "$a" "$b" || true
		diff <(cd "$a" && find . -printf '%y %m %U:%G %p %l\n' | sort) \
			<(cd "$b" && find . -printf '%y %m %U:%G %p %l\n' | sort) \
			|| true
	} | sed "s|$a|old|g; s|$b|new|g"
	umount "$a" "$b"
}

# Newest staged image other than the running one.
staged() {
	find /system -maxdepth 1 -name "${IMAGE_ID}_*.erofs" \
		! -name "${IMAGE_ID}_${IMAGE_VERSION}.erofs" | sort | tail -n 1
}

exclusive_bytes() {
	btrfs filesystem du --raw "$1" | awk 'NR == 2 { print $2 }'
}

timed_update() {
	local start
	start="$(date +%s.%N)"
	"$IMAGE_ID-update" --noconfirm -Q > "$TEST_STATE/$1.log" 2>&1 ||
		{ cat "$TEST_STATE/$1.log"; return 1; }
	awk -v s="$start" -v e="$(date +%s.%N)" 'BEGIN { printf "%.1f\n", e - s }' \
		> "$TEST_STATE/$1.seconds"
}

# Stage checks on the update just staged from the running image.
check_noop() {
	test_expect_success "$1: running image untouched by the update" '
		sha256sum --check --quiet "$TEST_STATE/running.sha256"
	'
	test_expect_success "$1: staged image differs only in os-release" '
		image_diff "$image" "$(staged)" > "$TEST_STATE/diff" &&
		test "$(cat "$TEST_STATE/diff")" = \
			"Files old/usr/lib/os-release and new/usr/lib/os-release differ" ||
			{ cat "$TEST_STATE/diff"; false; }
	'
	test_expect_success "$1: no-op delta adds under 1 MiB on disk" '
		test "$(exclusive_bytes "$(staged)")" -lt 1048576
	'
	test_info btrfs filesystem du /system/*.erofs
	test_expect_success "$1: images are read-only files" '
		! find /system -maxdepth 1 -name "*.erofs" -perm /222 | grep .
	'
}

if test_stage 1; then
	sha256sum "$image" > "$TEST_STATE/running.sha256"
	test_expect_success 'built image: no-op update (cold initrd cache)' '
		timed_update cold
	'
	test_expect_success 'built image: no-op update again (warm)' '
		timed_update warm &&
		grep "^Reusing cached initrd" "$TEST_STATE/warm.log"
	'
	test_info echo "cold $(cat "$TEST_STATE/cold.seconds")s," \
		"warm $(cat "$TEST_STATE/warm.seconds")s"
	check_noop 'built image'
	cp "$TEST_STATE/running.sha256" "$TEST_STATE/built.sha256"
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'built image still byte-identical after reboot' '
		sha256sum --check --quiet "$TEST_STATE/built.sha256"
	'
	sha256sum "$image" > "$TEST_STATE/running.sha256"
	test_expect_success 'in-box image: no-op update (warm)' '
		timed_update steady
	'
	test_info echo "steady $(cat "$TEST_STATE/steady.seconds")s"
	check_noop 'in-box image'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

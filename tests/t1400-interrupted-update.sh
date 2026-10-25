#!/bin/bash
# What an interrupted install leaves (an image whose UKI never landed, a
# UKI copy never renamed) is cleaned by the next update instead of counting
# as a kept version; a second update while one runs is refused, not let
# loose on the first one's work dir.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

image="/system/${IMAGE_ID}_${IMAGE_VERSION}.erofs"
esp=/boot/EFI/Linux
# Newer than the running version, as a crashed update would have staged.
orphan=$((IMAGE_VERSION + 1))

if test_stage 1; then
	sha256sum "$image" "$esp/${IMAGE_ID}_${IMAGE_VERSION}"*.efi \
		> "$TEST_STATE/running.sha256"
	cp --reflink=always "$image" "/system/${IMAGE_ID}_$orphan.erofs"
	echo partial > "$esp/${IMAGE_ID}_$orphan+3.efi.tmp"
	test_info ls -l /system "$esp"

	"$IMAGE_ID-update" --noconfirm -Q > "$TEST_STATE/first.log" 2>&1 &
	first=$!
	# Holding the lock once its work dir exists.
	for _ in $(seq 100); do
		[ -d "/system/.$IMAGE_ID-update/mnt" ] && break
		sleep 0.1
	done
	test_expect_success 'second update while one runs is refused' '
		! "$IMAGE_ID-update" --noconfirm -Q > "$TEST_STATE/second.log" 2>&1 &&
		grep "^Another $IMAGE_ID-update is running" "$TEST_STATE/second.log"
	'
	wait "$first"
	echo "$?" > "$TEST_STATE/first.status"
	test_expect_success 'first update unharmed by the second' '
		test "$(cat "$TEST_STATE/first.status")" = 0 ||
			{ cat "$TEST_STATE/first.log"; false; }
	'
	test_info grep -E "^(Pruning|Staged|Timings)" "$TEST_STATE/first.log"
	test_expect_success 'image without a UKI pruned' '
		test ! -e "/system/${IMAGE_ID}_$orphan.erofs"
	'
	test_expect_success 'unrenamed UKI copy removed' '
		! ls "$esp/"*.efi.tmp
	'
	test_expect_success 'running image and its UKI untouched' '
		sha256sum --check --quiet "$TEST_STATE/running.sha256"
	'
	test_expect_success 'every kept image has a UKI' '
		for f in /system/"${IMAGE_ID}"_*.erofs; do
			v="${f##*/${IMAGE_ID}_}"; v="${v%.erofs}"
			ls "$esp/${IMAGE_ID}_$v"*.efi || exit 1
		done
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v1"
	echo "$orphan" > "$TEST_STATE/orphan"
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the staged version' '
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/v1")" &&
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/orphan")"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

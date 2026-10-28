#!/bin/bash
# Deltas keep the data they replace: once the base outgrew the last full
# image of its line by /etc/<id>/squash-growth percent, the update builds
# a full one. Each image carries that reference size
# (/usr/lib/<id>/full-size), a full image none.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

mnt="$TEST_STATE/mnt"

image_of() {
	echo "/system/${IMAGE_ID}_$(cat "$TEST_STATE/$1").erofs"
}

# The reference size image $1 carries, empty if none.
reference_of() {
	mkdir -p "$mnt" && mount -o ro "$1" "$mnt" || return 1
	cat "$mnt/usr/lib/$IMAGE_ID/full-size" 2>&1 | grep '^[0-9]*$'
	umount "$mnt"
}

if test_stage 1; then
	test_expect_success 'any growth squashes' '
		mkdir -p "/etc/$IMAGE_ID" &&
		echo 0 > "/etc/$IMAGE_ID/squash-growth"
	'
	test_expect_success 'first update: a delta carrying the full size' '
		test_update first update --noconfirm -Q &&
		! grep "building a full image" "$TEST_STATE/first.log" &&
		test "$(reference_of "$(image_of first)")" = \
			"$(stat -c %s "/system/${IMAGE_ID}_$IMAGE_VERSION.erofs")"
	'
	test_expect_success 'second update: the delta grew it, full image' '
		test_update second update --noconfirm -Q &&
		grep "^Image grew from" "$TEST_STATE/second.log"
	'
	test_expect_success 'the full image carries no reference' '
		test -z "$(reference_of "$(image_of second)")"
	'
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the full image' '
		test "$IMAGE_VERSION" = "$(cat "$TEST_STATE/second")"
	'
	test_expect_success 'next update: a delta carrying its size' '
		test_update third update --noconfirm -Q &&
		! grep "building a full image" "$TEST_STATE/third.log" &&
		test "$(reference_of "$(image_of third)")" = \
			"$(stat -c %s "$(image_of second)")"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

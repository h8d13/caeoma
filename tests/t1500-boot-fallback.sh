#!/bin/bash
# Boot counting falls back past broken versions: stage three updates,
# corrupt the two newest images on purpose. Each of their tries fails in
# the initrd and reboots (counted boot, usr generator), sd-boot moves on,
# the newest good one boots and is blessed. The next update prunes the
# two spent versions, keeps the good ones.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

esp=/boot/EFI/Linux

# Stage an update from the running image; its version into $TEST_STATE/$1.
stage() {
	"$IMAGE_ID-update" --noconfirm -Q > "$TEST_STATE/$1.log" 2>&1 ||
		{ cat "$TEST_STATE/$1.log"; return 1; }
	sed -n "s/^Staged $IMAGE_ID \([0-9]*\);.*/\1/p" "$TEST_STATE/$1.log" \
		> "$TEST_STATE/$1"
	test -s "$TEST_STATE/$1"
}

v() {
	cat "$TEST_STATE/$1"
}

image_of() {
	echo "/system/${IMAGE_ID}_$(v "$1").erofs"
}

if test_stage 1; then
	echo "$IMAGE_VERSION" > "$TEST_STATE/v0"
	test_expect_success 'stage v1, v2, v3' '
		stage v1 && stage v2 && stage v3
	'
	# No superblock: the initrd cannot mount these.
	test_expect_success 'corrupt v3 and v2 on purpose' '
		for n in v3 v2; do
			chattr -i "$(image_of $n)" &&
			dd if=/dev/zero of="$(image_of $n)" bs=4096 count=1 \
				conv=notrunc status=none &&
			chattr +i "$(image_of $n)" || exit 1
		done
	'
	sha256sum "$(image_of v1)" > "$TEST_STATE/v1.sha256"
	test_info ls -l /system "$esp"
	test_reboot
fi

if test_stage 2; then
	test_info ls -l /system "$esp"
	test_expect_success 'booted v1, the newest good version' '
		test "$IMAGE_VERSION" = "$(v v1)"
	'
	test_expect_success 'v3 and v2 spent their boot tries' '
		ls "$esp/${IMAGE_ID}_$(v v3)+0-"*.efi &&
		ls "$esp/${IMAGE_ID}_$(v v2)+0-"*.efi
	'
	test_expect_success 'v1 blessed (counter dropped)' '
		test -e "$esp/${IMAGE_ID}_$(v v1).efi"
	'
	test_expect_success 'v1 image intact, v0 still kept' '
		sha256sum --check --quiet "$TEST_STATE/v1.sha256" &&
		test -e "$(image_of v0)"
	'
	test_expect_success 'next update prunes the spent versions' '
		stage v4 &&
		grep "^Pruning $IMAGE_ID $(v v3) (failed every boot try)" \
			"$TEST_STATE/v4.log" &&
		grep "^Pruning $IMAGE_ID $(v v2) (failed every boot try)" \
			"$TEST_STATE/v4.log" &&
		! ls "$esp/${IMAGE_ID}_$(v v3)"* "$esp/${IMAGE_ID}_$(v v2)"* \
			"$(image_of v3)" "$(image_of v2)"
	'
	test_expect_success 'good versions kept: v0, v1, v4' '
		test -e "$(image_of v0)" && test -e "$(image_of v1)" &&
		test -e "$(image_of v4)"
	'
	test_info ls -l /system "$esp"
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

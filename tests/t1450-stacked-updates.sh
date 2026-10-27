#!/bin/bash
# Updates staged before a reboot add up: each builds on the newest staged
# version that can still boot, not on the running one. discard deletes
# what is staged: the next update builds on the running version again.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

# Packages in the image of the version staged as $1.
packages_of() {
	local mnt="$TEST_STATE/mnt"
	mkdir -p "$mnt" &&
	mount -o ro "/system/${IMAGE_ID}_$(cat "$TEST_STATE/$1").erofs" "$mnt" &&
	ls "$mnt/usr/lib/sysimage/pacman/local"
	umount "$mnt"
}

if test_stage 1; then
	test_expect_success 'stage tree' 'test_update first --noconfirm -Syu tree'
	test_expect_success 'stage nano before rebooting' '
		test_update second --noconfirm -Syu nano &&
		grep "^Building on staged $IMAGE_ID $(cat "$TEST_STATE/first")" \
			"$TEST_STATE/second.log"
	'
	test_expect_success 'second image has both packages' '
		packages_of second > "$TEST_STATE/second.pkgs" &&
		grep "^tree-" "$TEST_STATE/second.pkgs" &&
		grep "^nano-" "$TEST_STATE/second.pkgs"
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v0"
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the second staged version' '
		test "$IMAGE_VERSION" = "$(cat "$TEST_STATE/second")"
	'
	test_expect_success 'both packages installed' 'pacman -Q tree nano'
	test_expect_success 'stage the removal of nano' '
		test_update third --noconfirm -R nano
	'
	test_expect_success 'discard deletes the staged removal' '
		"$IMAGE_ID-update" discard > "$TEST_STATE/discard.log" 2>&1 &&
		grep "^Discarding staged $IMAGE_ID $(cat "$TEST_STATE/third")" \
			"$TEST_STATE/discard.log" &&
		test ! -e "/system/${IMAGE_ID}_$(cat "$TEST_STATE/third").erofs" &&
		! ls "/boot/EFI/Linux/${IMAGE_ID}_$(cat "$TEST_STATE/third")"*
	'
	test_expect_success 'next update builds on the running version' '
		test_update fourth --noconfirm -Q &&
		! grep "^Building on staged" "$TEST_STATE/fourth.log" &&
		packages_of fourth | grep "^nano-"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

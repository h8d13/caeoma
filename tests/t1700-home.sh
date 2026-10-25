#!/bin/bash
# /home is the @home subvolume, beside @system on the same btrfs (one pool:
# /var and /home share the disk, both grow with the root partition). Files
# in it outlive an update.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

if test_stage 1; then
	test_info findmnt --output TARGET,SOURCE,FSTYPE,UUID /home
	test_expect_success '/home is the @home subvolume' '
		test "$(findmnt --noheadings --output FSTYPE /home)" = btrfs &&
		findmnt --noheadings --output OPTIONS /home | grep "subvol=/@home"
	'
	# Same filesystem UUID (btrfs gives each subvolume its own f_fsid).
	test_expect_success '/home shares the root filesystem' '
		test "$(findmnt --noheadings --output UUID /home)" = \
			"$(findmnt --noheadings --output UUID /)"
	'
	test_expect_success 'stage an update with a file in /home' '
		mkdir -p /home/test &&
		echo dotfile > /home/test/.profile &&
		"$IMAGE_ID-update" --noconfirm -Q > "$TEST_STATE/update.log" 2>&1 ||
			{ cat "$TEST_STATE/update.log"; false; }
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v0"
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the update' '
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/v0")"
	'
	test_expect_success 'file in /home kept' '
		test "$(cat /home/test/.profile)" = dotfile
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

#!/bin/bash
# /var is the @var subvolume (var.mount): state written to it outlives an
# update, the carry binds on top of it still apply, and journald lets go
# of it at shutdown so it unmounts cleanly.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

if test_stage 1; then
	test_info findmnt --output TARGET,SOURCE,FSTYPE,OPTIONS /var
	test_expect_success '/var is the @var subvolume' '
		test "$(findmnt --noheadings --output FSTYPE /var)" = btrfs &&
		findmnt --noheadings --output OPTIONS /var | grep "subvol=/@var"
	'
	test_expect_success '/var shares the root filesystem' '
		test "$(findmnt --noheadings --output UUID /var)" = \
			"$(findmnt --noheadings --output UUID /)"
	'
	test_expect_success 'pacman DB bound over /var' '
		findmnt --noheadings /var/lib/pacman/local && pacman -Q pacman
	'
	# Without it the stop of var.mount never stops journal-flush, whose
	# ExecStop relinquishes /var: journald keeps it busy at shutdown.
	test_expect_success 'stopping /var stops journal-flush first' '
		systemctl show --property=RequiredBy --value var.mount |
			grep --word-regexp systemd-journal-flush.service
	'
	test_expect_success 'stage an update with state in /var' '
		mkdir -p /var/lib/test &&
		echo state > /var/lib/test/data &&
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
	test_expect_success 'state in /var kept' '
		test "$(cat /var/lib/test/data)" = state
	'
	test_expect_success '@system holds no /var content' '
		test -z "$(ls -A /system/@system/var)"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

#!/bin/bash
# /etc is an overlay: the running image's factory /etc under @etc/upper.
# Local edits, deletions and new files outlive an update; untouched files
# and a package's new defaults come from the image, never copied up.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

# shellcheck disable=SC2034 # used in test_expect_success strings
upper=/system/@etc/upper

if test_stage 1; then
	test_info findmnt --output TARGET,FSTYPE,OPTIONS /etc
	test_expect_success '/etc is an overlay on factory /etc' '
		test "$(findmnt --noheadings --output FSTYPE /etc)" = overlay &&
		findmnt --noheadings --output OPTIONS /etc |
			grep "lowerdir=[^,]*/usr/share/factory/etc,"
	'
	test_expect_success 'vendor files are not links' '
		test -f /etc/issue && test ! -L /etc/issue
	'
	test_expect_success 'edit, delete and add in /etc' '
		echo local-edit >> /etc/issue &&
		rm /etc/locale.gen &&
		echo local-new > "/etc/$IMAGE_ID-test.conf"
	'
	test_expect_success 'stage an update with nano' '
		"$IMAGE_ID-update" --noconfirm -Syu nano \
			> "$TEST_STATE/update.log" 2>&1 ||
			{ cat "$TEST_STATE/update.log"; false; }
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v0"
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the update' '
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/v0")"
	'
	test_expect_success 'edit kept' '
		test "$(tail --lines=1 /etc/issue)" = local-edit
	'
	test_expect_success 'deletion kept' '
		! ls -la /etc/locale.gen &&
		ls -la /usr/share/factory/etc/locale.gen
	'
	test_expect_success 'new file kept' '
		test "$(cat "/etc/$IMAGE_ID-test.conf")" = local-new
	'
	test_expect_success 'package default from the new image' '
		test -f /etc/nanorc && test ! -e "$upper/nanorc"
	'
	test_expect_success 'untouched files never copied up' '
		test ! -e "$upper/hosts" && test ! -e "$upper/pacman.conf"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

#!/bin/bash
# On the first boot of a version, the initrd drops /etc upper entries the
# image ships alike (etc-dedup): a rewrite with the same bytes, a live
# pacman -S whose package the next image has. Real edits, deletions and
# anything below an opaque dir stay.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

# shellcheck disable=SC2034 # used in test_expect_success strings
upper=/system/@etc/upper factory=/usr/share/factory/etc

if test_stage 1; then
	test_expect_success 'same bytes rewritten: copied up' '
		cat "$factory/issue" > /etc/issue &&
		test -f "$upper/issue"
	'
	test_expect_success 'live pacman -S nano: nanorc copied up' '
		pacman -Sy --noconfirm nano > "$TEST_STATE/live.log" 2>&1 &&
		test -f "$upper/nanorc"
	'
	test_expect_success 'a real edit, a deletion, an opaque dir' '
		echo "# local" >> /etc/hosts &&
		rm /etc/locale.gen &&
		rm -r /etc/skel &&
		cp -a "$factory/skel" /etc/skel &&
		test "$(getfattr --only-values -n trusted.overlay.opaque \
			"$upper/skel")" = y
	'
	test_expect_success 'stage an update with nano' '
		test_update update --noconfirm -Syu nano
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v0"
	test_reboot
fi

if test_stage 2; then
	test_info journalctl -b -o cat --grep "^etc-dedup"
	test_expect_success 'booted the update' '
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/v0")"
	'
	test_expect_success 'etc-dedup named what it dropped' '
		journalctl -b -o cat --grep "^etc-dedup" |
			grep "^etc-dedup: /etc/issue identical to the image, dropped"
	'
	test_expect_success 'same-bytes copy dropped, image file shows' '
		test ! -e "$upper/issue" && cmp /etc/issue "$factory/issue"
	'
	test_expect_success 'live nanorc dropped, the image one shows' '
		test ! -e "$upper/nanorc" && test -f /etc/nanorc
	'
	test_expect_success 'real edit kept' '
		test "$(tail -n 1 /etc/hosts)" = "# local"
	'
	test_expect_success 'deletion kept' '
		test ! -e /etc/locale.gen && test -c "$upper/locale.gen"
	'
	test_expect_success 'opaque dir kept with its content' '
		test -n "$(ls -A "$upper/skel")"
	'
	test_expect_success 'stamp is this version' '
		test "$(cat /system/@etc/lower-version)" = "$IMAGE_VERSION"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

#!/bin/bash
# The update over three boots: add tree (delta), remove it (delta,
# whiteouts). Box-side pacman, /etc links and CA trust, delta size, COW,
# package DB integrity, cache cleanup.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

image="/system/${IMAGE_ID}_${IMAGE_VERSION}.erofs"

# Exclusive bytes of the running image: what this version added on disk.
exclusive_bytes() {
	btrfs filesystem du --raw "$image" | awk 'NR == 2 { print $2 }'
}

common() {
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_expect_success 'box pacman syncs repo indexes (writable lock)' '
		pacman -Sy
	'
	test_expect_success 'box pacman searches the repos' '
		pacman -Ss "^tree\$" | grep "^extra/tree "
	'
	test_expect_success '/etc/ssl is a directory link into factory' '
		test "$(readlink /etc/ssl)" = /usr/share/factory/etc/ssl
	'
	test_expect_success 'CA trust works through the linked /etc/ssl' '
		curl --head --silent --show-error --fail --output /dev/null \
			https://archlinux.org
	'
	test_expect_success 'running image is COW (reflinks keep working)' '
		! lsattr "$image" | grep "^[^ ]*C"
	'
}

if test_stage 1; then
	common
	test_expect_success 'tree is not installed' '! pacman -Q tree'
	test_expect_success 'update stages tree' '
		"$IMAGE_ID-update" --noconfirm -Syu tree &&
		pacman --query --quiet | wc -l > "$TEST_STATE/packages"
	'
	test_expect_success 'package cache emptied after staging' '
		test -z "$(ls -A /var/cache/pacman/pkg)"
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v1"
	test_reboot
fi

if test_stage 2; then
	common
	test_expect_success 'booted the staged version' '
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/v1")"
	'
	test_expect_success 'tree is installed' 'pacman -Q tree'
	test_expect_success 'package DB kept the base (+1 for tree)' '
		test "$(pacman --query --quiet | wc -l)" -eq \
			"$(($(cat "$TEST_STATE/packages") + 1))"
	'
	test_expect_success 'delta adds under 2 MiB on disk' '
		test "$(exclusive_bytes)" -lt 2097152
	'
	test_expect_success 'update removes tree' '
		"$IMAGE_ID-update" --noconfirm -R tree > "$TEST_STATE/update2.log"
	'
	test_expect_success 'unchanged initrd inputs: cached initrd reused' '
		grep "^Reusing cached initrd" "$TEST_STATE/update2.log" ||
			{ cat "$TEST_STATE/update2.log"; false; }
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v2"
	test_reboot
fi

if test_stage 3; then
	common
	# The reused initrd holds the old os-release: the later archive wins.
	test_expect_success 'booted the staged version (cached initrd)' '
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/v2")"
	'
	test_expect_success 'tree is gone (whiteouts applied)' '! pacman -Q tree'
	test_expect_success 'delta adds under 2 MiB on disk' '
		test "$(exclusive_bytes)" -lt 2097152
	'
	test_info btrfs filesystem du /system/*.erofs
	test_done
fi

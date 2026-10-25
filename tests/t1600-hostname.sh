#!/bin/bash
# A box without /etc/hostname is named after its image (the UKI's initrd
# sets it, see build-uki), not after the kernel's built-in "archlinux". A
# local name is per machine and wins from the next boot on.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

if test_stage 1; then
	test_info hostnamectl
	test_expect_success 'no /etc/hostname on a fresh box' '
		test ! -e /etc/hostname
	'
	test_expect_success 'named after the ImageId' '
		test "$(cat /proc/sys/kernel/hostname)" = "$IMAGE_ID"
	'
	test_expect_success 'set a local name' '
		hostnamectl hostname local-name &&
		test "$(cat /etc/hostname)" = local-name
	'
	test_reboot
fi

if test_stage 2; then
	test_info hostnamectl
	test_expect_success 'local name kept over the ImageId' '
		test "$(cat /proc/sys/kernel/hostname)" = local-name
	'
	test_done
fi

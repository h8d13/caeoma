#!/bin/bash
# The update builds from the box's config: a repo enabled in
# /etc/pacman.conf for pacman; for the UKI the /etc the box boots with:
# /etc/kernel/cmdline, /etc/mkinitcpio.conf.d drop-ins and the box-only
# files they name. Microcode reaches the initrd's early archive. A drop-in
# losing the hooks that mount the image is refused before staging.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

# The fallback's (generic) initrd: microcode of every vendor, whatever
# the CPU the test runs on.
# shellcheck disable=SC2034 # used in test_expect_success strings
marker="$IMAGE_ID.local-config=1" \
	initrd="/var/lib/$IMAGE_ID/initrd/generic/initrd"

images() {
	find /system -maxdepth 1 -name "${IMAGE_ID}_*.erofs" | sort
}

if test_stage 1; then
	test_expect_success 'repo, cmdline, drop-in naming a box-only file' '
		printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" \
			>> /etc/pacman.conf &&
		mkdir -p /etc/kernel /etc/mkinitcpio.conf.d &&
		echo "$marker" > /etc/kernel/cmdline &&
		echo box-only > /etc/test-initrd-marker &&
		echo "FILES+=(/etc/test-initrd-marker)" \
			> /etc/mkinitcpio.conf.d/50-test.conf &&
		echo "# local" >> /etc/mkinitcpio.conf &&
		pacman -Sy
	'
	test_expect_success 'update with a [multilib] package and microcode' '
		"$IMAGE_ID" update --noconfirm -Syu lib32-acl amd-ucode \
			> "$TEST_STATE/update.log" 2>&1 ||
			{ cat "$TEST_STATE/update.log"; false; }
	'
	test_expect_success 'edits to /etc/mkinitcpio.conf are named unused' '
		grep "^Edits to /etc/mkinitcpio.conf are not used" \
			"$TEST_STATE/update.log"
	'
	test_expect_success 'the box-only file is in the initrd' '
		lsinitcpio "$initrd" | grep --line-regexp etc/test-initrd-marker
	'
	test_expect_success 'microcode in the early archive' '
		bsdtar -tf "$initrd" |
			grep --line-regexp kernel/x86/microcode/AuthenticAMD.bin
	'
	test_expect_success 'a drop-in losing systemd is refused, nothing staged' '
		images > "$TEST_STATE/before" &&
		echo "HOOKS=(base udev)" > /etc/mkinitcpio.conf.d/90-bad.conf &&
		! "$IMAGE_ID" update --noconfirm -Q > "$TEST_STATE/bad.log" 2>&1 &&
		grep "^HOOKS must keep systemd and $IMAGE_ID" "$TEST_STATE/bad.log" &&
		images | diff "$TEST_STATE/before" - &&
		rm /etc/mkinitcpio.conf.d/90-bad.conf
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v0"
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the update' '
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/v0")"
	'
	test_expect_success 'packages installed' 'pacman -Q lib32-acl amd-ucode'
	test_expect_success '/etc/kernel/cmdline on the kernel command line' '
		grep --word-regexp --fixed-strings "$marker" /proc/cmdline
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

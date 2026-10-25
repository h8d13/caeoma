#!/bin/bash
# Image state rules (/usr/lib/caeoma/state): vendor carry/drop in a built
# image, a local drop rule applied by caeoma-update, and the refusals.

. /root/tests/test-lib.sh
. /usr/lib/os-release

# The running erofs, mounted as built (not the merged /usr).
mount_image() {
	mkdir -p /run/caeoma-image &&
	mount -o ro "/system/${IMAGE_ID}_${IMAGE_VERSION}.erofs" /run/caeoma-image
}

if test_stage 1; then
	test_expect_success 'carry: pacman DB ships in /usr/lib/sysimage' '
		test -d /usr/lib/sysimage/pacman/local &&
		test -f /usr/lib/sysimage/pacman/local/ALPM_DB_VERSION
	'
	test_expect_success 'carry: generator binds it on /var/lib/pacman/local' '
		findmnt --noheadings --output TARGET /var/lib/pacman/local &&
		test -f /var/lib/pacman/local/ALPM_DB_VERSION
	'
	test_expect_success 'drop /var/*: the image has an empty /var' '
		mount_image &&
		test -z "$(find /run/caeoma-image/var -mindepth 1 ! -path "*/var/tmp")" &&
		umount /run/caeoma-image
	'
	test_expect_success 'a malformed rule is rejected' '
		mkdir -p /etc/caeoma/state.d &&
		echo "keep /usr" > /etc/caeoma/state.d/90-bad.conf &&
		! /usr/lib/caeoma/state &&
		rm /etc/caeoma/state.d/90-bad.conf
	'
	test_expect_success 'local drop rule applied by caeoma-update' '
		test -n "$(ls -A /usr/share/man)" &&
		echo "drop /usr/share/man/*" > /etc/caeoma/state.d/50-test.conf &&
		pacman --query --quiet | wc -l > "$TEST_STATE/packages" &&
		caeoma-update --noconfirm -Syu
	'
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'local drop rule emptied /usr/share/man' '
		test -z "$(ls -A /usr/share/man)"
	'
	test_expect_success 'local rules stayed out of factory and the image' '
		! test -e /usr/share/factory/etc/caeoma
	'
	test_expect_success 'package DB carried through the update' '
		test "$(pacman --query --quiet | wc -l)" -eq \
			"$(cat "$TEST_STATE/packages")"
	'
	test_expect_success 'a drop of an essential path is refused' '
		echo "drop /usr/lib/*" > /etc/caeoma/state.d/60-essential.conf &&
		versions="$(ls /system)" &&
		! caeoma-update --noconfirm -Syu &&
		test "$(ls /system)" = "$versions"
	'
	rm -f /etc/caeoma/state.d/60-essential.conf
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

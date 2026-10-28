#!/bin/bash
# Image state rules (the state script): vendor carry/drop in a built
# image, a local drop rule applied by the update, and the refusals.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

image="/run/$IMAGE_ID-image"
local_rules="/etc/$IMAGE_ID/state.d"

# The running erofs, mounted as built (not the merged /usr).
mount_image() {
	mkdir -p "$image" &&
	mount -o ro "/system/${IMAGE_ID}_${IMAGE_VERSION}.erofs" "$image"
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
		test -z "$(find "$image/var" -mindepth 1 ! -path "*/var/tmp")" &&
		umount "$image"
	'
	test_expect_success 'a malformed rule is rejected' '
		mkdir -p "$local_rules" &&
		echo "keep /usr" > "$local_rules/90-bad.conf" &&
		! "/usr/lib/$IMAGE_ID/state" &&
		rm "$local_rules/90-bad.conf"
	'
	test_expect_success 'local drop rule applied by the update' '
		test -n "$(ls -A /usr/share/man)" &&
		echo "drop /usr/share/man/*" > "$local_rules/50-test.conf" &&
		pacman --query --quiet | wc -l > "$TEST_STATE/packages" &&
		"$IMAGE_ID" update --noconfirm -Syu
	'
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'local drop rule emptied /usr/share/man' '
		test -z "$(ls -A /usr/share/man)"
	'
	test_expect_success 'local rules stayed out of factory and the image' '
		! test -e "/usr/share/factory/etc/$IMAGE_ID"
	'
	test_expect_success 'package DB carried through the update' '
		test "$(pacman --query --quiet | wc -l)" -eq \
			"$(cat "$TEST_STATE/packages")"
	'
	test_expect_success 'a drop of an essential path is refused' '
		echo "drop /usr/lib/*" > "$local_rules/60-essential.conf" &&
		versions="$(ls /system)" &&
		! "$IMAGE_ID" update --noconfirm -Syu &&
		test "$(ls /system)" = "$versions"
	'
	rm -f "$local_rules/60-essential.conf"
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

#!/bin/bash
# Throwaway writable /usr (sysext Mutable=ephemeral): pacman -S on the box
# works live and is gone after reboot; /opt persists; caeoma-update still
# stages a permanent version.

. /root/t/test-lib.sh

if test_stage 1; then
	test_expect_success '/usr is merged with the ephemeral anchor' '
		systemd-sysext status | grep "^/usr .*caeoma-ephemeral"
	'
	test_expect_success '/opt is not managed by sysext' '
		systemd-sysext status | grep "^/opt *- "
	'
	test_expect_success 'package DB is bound from the merged /usr' '
		test "$(findmnt --noheadings --output FSTYPE /var/lib/pacman/local)" \
			= overlay
	'
	test_expect_success 'pacman -S installs live' '
		pacman --query --quiet | wc -l > "$TEST_STATE/packages" &&
		pacman -Sy &&
		pacman -S --noconfirm tree &&
		tree --version
	'
	test_expect_success '/opt takes a write' '
		echo persist > /opt/persist-test
	'
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'live install is gone after reboot' '
		! command -v tree && ! pacman -Q tree
	'
	test_expect_success 'package DB is back to the image' '
		test "$(pacman --query --quiet | wc -l)" -eq \
			"$(cat "$TEST_STATE/packages")"
	'
	test_expect_success '/opt kept its write' '
		test "$(cat /opt/persist-test)" = persist
	'
	test_expect_success 'caeoma-update still stages a version' '
		caeoma-update --noconfirm -Syu tree
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

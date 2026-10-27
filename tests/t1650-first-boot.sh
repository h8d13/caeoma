#!/bin/bash
# First boot never prompts (systemd.firstboot=headless): it applies the
# image's own credentials (/usr/lib/credstore), here booted with none from
# outside. They are root-only. A local change afterwards is the box's.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh

if test_stage 1; then
	test_info localectl
	test_info timedatectl
	test_expect_success 'first boot is headless' '
		grep --word-regexp systemd.firstboot=headless /proc/cmdline
	'
	test_expect_success 'locale, keymap, timezone from the image' '
		grep --line-regexp LANG=C.UTF-8 /etc/locale.conf &&
		grep --line-regexp KEYMAP=us /etc/vconsole.conf &&
		test "$(timedatectl show --property=Timezone --value)" = UTC
	'
	test_expect_success 'root has a password' '
		getent shadow root | cut -d: -f2 | grep "^\\$"
	'
	test_expect_success 'credentials are root-only' '
		test "$(stat -c %a /usr/lib/credstore)" = 700 &&
		! find /usr/lib/credstore -type f ! -perm 0600 | grep .
	'
	test_expect_success 'a local timezone' '
		timedatectl set-timezone Europe/Paris
	'
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'the local timezone stays' '
		test "$(timedatectl show --property=Timezone --value)" = Europe/Paris
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

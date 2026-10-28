#!/bin/bash
# Vendor unit enablement lives in factory /etc (the /etc lower), not in
# /usr: first boot copies nothing up, a local systemctl disable is a
# whiteout in the upper that outlives an update, enable brings it back.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

# shellcheck disable=SC2034 # used in test_expect_success strings
upper=/system/@etc/upper wants=systemd/system/sysinit.target.wants
# shellcheck disable=SC2034
unit=systemd-timesyncd.service

if test_stage 1; then
	test_expect_success 'vendor enablement visible in /etc' '
		test -L "/etc/$wants/$unit"
	'
	test_expect_success 'nothing baked into /usr' '
		test ! -e "/usr/lib/$wants/$unit"
	'
	test_expect_success 'first boot copied no enablement up' '
		test ! -e "$upper/systemd"
	'
	test_expect_success 'disable leaves a whiteout in the upper' '
		systemctl disable "$unit" &&
		test -c "$upper/$wants/$unit"
	'
	test_expect_success 'stage an update' '
		test_update update update --noconfirm -Q
	'
	echo "$IMAGE_VERSION" > "$TEST_STATE/v0"
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the update' '
		test "$IMAGE_VERSION" != "$(cat "$TEST_STATE/v0")"
	'
	test_expect_success 'disabled unit stayed disabled and stopped' '
		test "$(systemctl is-enabled "$unit")" = disabled &&
		! systemctl is-active --quiet "$unit"
	'
	test_expect_success 'other vendor units still enabled' '
		systemctl is-active --quiet systemd-networkd.service
	'
	test_expect_success 'enable brings it back' '
		systemctl enable --now "$unit" &&
		systemctl is-active --quiet "$unit"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

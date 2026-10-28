#!/bin/bash
# Writable /usr (sysext Mutable=yes): writes on the box (pacman -S, a dir
# rename) land in the running version's upper and persist across reboots;
# a new version starts with an empty upper, the old one keeps its own.
# /opt is not sysext's.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

# shellcheck disable=SC2034 # used in the test strings (eval)
upper="/var/lib/$IMAGE_ID/usr"

if test_stage 1; then
	echo "$IMAGE_VERSION" > "$TEST_STATE/v1"
	test_expect_success '/usr is merged with the anchor' '
		systemd-sysext status | grep "^/usr .*$IMAGE_ID-anchor"
	'
	test_expect_success '/opt is not managed by sysext' '
		systemd-sysext status | grep "^/opt *- "
	'
	test_expect_success 'writes go to the version upper' '
		test "$(readlink /var/lib/extensions.mutable/usr)" = \
			"$upper/$IMAGE_VERSION"
	'
	test_expect_success 'package DB is bound from the merged /usr' '
		test "$(findmnt --noheadings --output FSTYPE /var/lib/pacman/local)" \
			= overlay
	'
	test_expect_success 'pacman -S installs live, into the upper' '
		pacman -Sy &&
		pacman -S --noconfirm tree &&
		tree --version &&
		test -x "$upper/$IMAGE_VERSION/bin/tree"
	'
	test_expect_success 'a renamed dir is copied up whole' '
		mv /usr/share/licenses/zstd /usr/share/licenses/zstd-renamed &&
		ls "$upper/$IMAGE_VERSION/share/licenses/zstd-renamed/LICENSE" &&
		! getfattr --name=trusted.overlay.redirect \
			"$upper/$IMAGE_VERSION/share/licenses/zstd-renamed"
	'
	test_expect_success '/opt takes a write' '
		echo persist > /opt/persist-test
	'
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'live install kept across reboot' '
		tree --version && pacman -Q tree
	'
	test_expect_success 'renamed dir kept across reboot' '
		ls /usr/share/licenses/zstd-renamed/LICENSE &&
		! ls /usr/share/licenses/zstd
	'
	test_expect_success '/opt kept its write' '
		test "$(cat /opt/persist-test)" = persist
	'
	test_expect_success 'stage a version without package change' '
		test_update next update --noconfirm -Q
	'
	test_reboot
fi

if test_stage 3; then
	test_expect_success 'booted the new version' '
		test "$IMAGE_VERSION" = "$(cat "$TEST_STATE/next")"
	'
	test_expect_success 'the new version starts with an empty upper' '
		test "$(readlink /var/lib/extensions.mutable/usr)" = \
			"$upper/$IMAGE_VERSION" &&
		! command -v tree && ! pacman -Q tree &&
		ls /usr/share/licenses/zstd/LICENSE
	'
	test_expect_success 'the old version keeps its upper' '
		test -x "$upper/$(cat "$TEST_STATE/v1")/bin/tree"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

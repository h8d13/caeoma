#!/bin/bash
# The update refuses -S without -u: the repo indexes are shared with the
# box's pacman -Sy, a sync without the upgrade is a partial upgrade. Sync
# queries install nothing and pass.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh

images="$TEST_STATE/images"

list() {
	find /system -maxdepth 1 | sort
}

# The update with args $@ is refused before staging anything.
refused() {
	list > "$images" &&
	! "$IMAGE_ID" update --noconfirm "$@" > "$TEST_STATE/log" 2>&1 &&
	grep "partial upgrade" "$TEST_STATE/log" &&
	list | diff "$images" -
}

test_expect_success '-S refused' 'refused -S nano'
test_expect_success '-Sy refused' 'refused -Sy nano'
test_expect_success '--sync --refresh refused' 'refused --sync --refresh nano'
test_expect_success '-Ss passes' '
	pacman -Sy &&
	"$IMAGE_ID" update --noconfirm -Ss "^nano\$" > "$TEST_STATE/query.log" 2>&1 ||
		{ cat "$TEST_STATE/query.log"; false; }
'
test_expect_success 'no failed units' '
	test -z "$(systemctl --failed --no-legend)"
'
test_done

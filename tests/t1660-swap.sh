#!/bin/bash
# Swap: zram first (priority 100), then a swapfile in @swap made on first
# boot as large as the RAM (overflow, hibernation), NOCOW as btrfs needs.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh

# Priority, size (KiB) of active swap $1.
swap_of() {
	awk -v f="$1" '$1 == f { print $5, $3 }' /proc/swaps
}

test_info cat /proc/swaps
test_expect_success 'zram first, priority 100' '
	test "$(swap_of /dev/zram0 | cut -d" " -f1)" = 100
'
test_expect_success '/swap is the @swap subvolume' '
	findmnt --noheadings --output OPTIONS /swap | grep "subvol=/@swap"
'
test_expect_success 'the swapfile is on, below zram' '
	test "$(swap_of /swap/swapfile | cut -d" " -f1)" = 10
'
test_expect_success 'the swapfile is about the size of the RAM' '
	ram="$(awk "/^MemTotal:/ { print \$2 }" /proc/meminfo)" &&
	size="$(swap_of /swap/swapfile | cut -d" " -f2)" &&
	test "$size" -ge $((ram * 95 / 100)) &&
	test "$size" -le $((ram * 105 / 100))
'
test_expect_success 'the swapfile is NOCOW' '
	lsattr /swap/swapfile | cut -d" " -f1 | grep C
'
test_expect_success 'no failed units' '
	test -z "$(systemctl --failed --no-legend)"
'
test_done

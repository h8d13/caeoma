#!/bin/bash
# First boot fills the disk: the initrd grows the root partition before
# it is unlocked or mounted (grow-root), then the btrfs. A LUKS2 root is
# opened at its full size, systemd-growfs is not involved (it cannot resize
# an opened LUKS2 root and warns). Plain or encrypted root alike.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh

# Device of type $1 (part, disk) under the root's file system.
under_root() {
	lsblk --inverse --noheadings --list --output NAME,TYPE \
		"$(findmnt --noheadings --output SOURCE /system | sed 's/\[.*//')" |
		awk -v t="$1" '$2 == t { print "/dev/" $1; exit }'
}

bytes() {
	lsblk --bytes --nodeps --noheadings --output SIZE "$1"
}

test_info lsblk --output NAME,TYPE,FSTYPE,SIZE
test_expect_success 'root partition fills the disk (but the 2 GiB ESP)' '
	disk="$(bytes "$(under_root disk)")" part="$(bytes "$(under_root part)")" &&
	test $((part + 2 * 1024 ** 3 + 64 * 1024 ** 2)) -ge "$disk"
'
test_expect_success 'btrfs fills the root partition' '
	part="$(bytes "$(under_root part)")" &&
	fs="$(btrfs filesystem usage --raw /system |
		awk "/Device size:/ { print \$3 }")" &&
	test $((fs + 32 * 1024 ** 2)) -ge "$part"
'
test_expect_success 'no systemd-growfs on root, no crypt_resize warning' '
	! systemctl list-units --all --no-legend "systemd-growfs*" | grep . &&
	! journalctl -b -o cat --grep "crypt_resize|resize underlying device"
'
test_expect_success 'no failed units' '
	test -z "$(systemctl --failed --no-legend)"
'
test_done

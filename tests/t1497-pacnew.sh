#!/bin/bash
# The image's own mirrorlist edit is redone by every update, so it never
# leaves a .pacnew; any other .pacnew is named in the update's output. A
# box-local pacman hook (the update uses the box's pacman.conf, hooks
# included) stands in for a package upgrade leaving .pacnew files.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh

mnt="$TEST_STATE/mnt"

test_expect_success 'mirrorlist written from the image mirror' '
	test "$(cat /etc/pacman.d/mirrorlist)" = \
		"Server = $(cat "/usr/lib/$IMAGE_ID/mirror")/\$repo/os/\$arch"
'
test_expect_success 'a hook leaving .pacnew files in the tree' '
	mkdir -p /etc/pacman.d/hooks &&
	cat > /etc/pacman.d/hooks/test-pacnew.hook <<- HOOK
		[Trigger]
		Operation = Install
		Operation = Upgrade
		Type = Package
		Target = *

		[Action]
		Description = test: leave .pacnew files
		When = PostTransaction
		Exec = /bin/sh -c "echo new > /etc/pacman.d/mirrorlist.pacnew; echo new > /etc/test-only.pacnew"
	HOOK
'
test_expect_success 'update with a transaction' '
	test_update update update --noconfirm -Syu tree
'
test_expect_success 'the other .pacnew is named' '
	grep "^/etc/test-only.pacnew: merge it" "$TEST_STATE/update.log" &&
	! grep "mirrorlist.pacnew" "$TEST_STATE/update.log"
'
test_expect_success 'mount the staged image' '
	mkdir -p "$mnt" &&
	mount -o ro "/system/${IMAGE_ID}_$(cat "$TEST_STATE/update").erofs" "$mnt"
'
test_expect_success 'no mirrorlist.pacnew in the image, mirrorlist kept' '
	test ! -e "$mnt/usr/share/factory/etc/pacman.d/mirrorlist.pacnew" &&
	cmp "$mnt/usr/share/factory/etc/pacman.d/mirrorlist" \
		/usr/share/factory/etc/pacman.d/mirrorlist
'
test_expect_success 'the other .pacnew shipped as is' '
	test -f "$mnt/usr/share/factory/etc/test-only.pacnew"
'
umount "$mnt"
test_expect_success 'named once: not again by the next update' '
	test_update again update --noconfirm -Q &&
	! grep "test-only.pacnew" "$TEST_STATE/again.log"
'
test_expect_success 'no failed units' '
	test -z "$(systemctl --failed --no-legend)"
'
test_done

#!/bin/bash
# commit: the box's changes become a new version. /usr writes of any
# origin (pacman -S, a hand-made file), /etc edits and deletions go in;
# machine state stays the box's. After the reboot the uppers hold nothing
# the image ships. rollback then boots the version before, clean.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

# shellcheck disable=SC2034 # used in the test strings (eval)
image="/run/$IMAGE_ID-image"
# shellcheck disable=SC2034
etc_upper=/system/@etc/upper
# shellcheck disable=SC2034
usr_upper="/var/lib/$IMAGE_ID/usr"

if test_stage 1; then
	echo "$IMAGE_VERSION" > "$TEST_STATE/v1"
	test_expect_success 'changes on the box' '
		pacman -Sy &&
		pacman -S --noconfirm tree &&
		printf "#!/bin/sh\necho handmade\n" > /usr/bin/handmade &&
		chmod 755 /usr/bin/handmade &&
		echo committed > /etc/commit-test.conf &&
		test -e /etc/issue && rm /etc/issue &&
		echo secret > /etc/ssh/ssh_host_test_key
	'
	test_expect_success 'commit' 'test_update next commit'
	test_expect_success 'the image has the changes' '
		mkdir -p "$image" &&
		mount -o ro "/system/${IMAGE_ID}_$(cat "$TEST_STATE/next").erofs" \
			"$image" &&
		test -x "$image/usr/bin/tree" &&
		test -x "$image/usr/bin/handmade" &&
		test -d "$image"/usr/lib/sysimage/pacman/local/tree-* &&
		grep committed "$image/usr/share/factory/etc/commit-test.conf" &&
		! test -e "$image/usr/share/factory/etc/issue"
	'
	test_expect_success 'machine state stayed out of the image' '
		! test -e "$image/etc/ssh/ssh_host_test_key" &&
		! test -e "$image/usr/share/factory/etc/ssh/ssh_host_test_key" &&
		! grep "^root:" "$image/usr/share/factory/etc/shadow"
	'
	test_expect_success 'no overlay xattrs in the image' '
		test -z "$(getfattr --recursive --absolute-names \
			--match="^trusted\.overlay\." "$image/usr/bin" \
			"$image/usr/share/factory/etc")"
	'
	umount "$image"
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the committed version' '
		test "$IMAGE_VERSION" = "$(cat "$TEST_STATE/next")"
	'
	test_expect_success '/usr changes come from the image' '
		tree --version && pacman -Q tree &&
		test "$(handmade)" = handmade &&
		test -z "$(ls -A "$usr_upper/$IMAGE_VERSION")"
	'
	test_expect_success 'the committed upper is gone' '
		! test -e "$usr_upper/$(cat "$TEST_STATE/v1")" &&
		! test -e "$usr_upper/$(cat "$TEST_STATE/v1").committed"
	'
	test_expect_success '/etc edit comes from the image' '
		grep committed /etc/commit-test.conf &&
		! test -e "$etc_upper/commit-test.conf"
	'
	test_expect_success '/etc deletion comes from the image' '
		! test -e /etc/issue &&
		! test -e "$etc_upper/issue"
	'
	test_expect_success 'machine state still the box'"'"'s' '
		test "$(cat /etc/ssh/ssh_host_test_key)" = secret &&
		test -e "$etc_upper/ssh/ssh_host_test_key"
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_expect_success 'rollback' '
		"$IMAGE_ID" rollback &&
		ls /boot/EFI/Linux/"${IMAGE_ID}_${IMAGE_VERSION}"+0-3.efi \
			/boot/EFI/Linux/"${IMAGE_ID}_${IMAGE_VERSION}"-fallback+0-3.efi
	'
	test_reboot
fi

if test_stage 3; then
	test_expect_success 'booted the version before the commit' '
		test "$IMAGE_VERSION" = "$(cat "$TEST_STATE/v1")"
	'
	test_expect_success 'its /usr is clean' '
		! command -v tree && ! pacman -Q tree && ! command -v handmade &&
		test -z "$(ls -A "$usr_upper/$IMAGE_VERSION")"
	'
	test_expect_success 'its /etc is back' '
		! test -e /etc/commit-test.conf && test -e /etc/issue
	'
	test_expect_success 'machine state still the box'"'"'s' '
		test "$(cat /etc/ssh/ssh_host_test_key)" = secret
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

#!/bin/bash
# The update installs two UKIs per version: one for this machine
# (autodetect: its modules, its CPU's microcode), the default, and a
# fallback for any (<id>_<ver>-fallback), sorted just before it. Once the
# first spent its tries (a hardware change), the same version boots
# through the fallback, not an older one. Both go with their version.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh
. /usr/lib/os-release

# shellcheck disable=SC2034 # used in test_expect_success strings
esp=/boot/EFI/Linux cache="/var/lib/$IMAGE_ID/initrd"

v() {
	cat "$TEST_STATE/$1"
}

# Entry id bootctl marks default.
default_entry() {
	bootctl list --no-pager | awk '
		/title:/ { d = /\(default\)/ }
		/ id:/ && d { print $2; exit }'
}

if test_stage 1; then
	test_expect_success 'update installs both UKIs' '
		test_update staged update --noconfirm -Q &&
		test -f "$esp/${IMAGE_ID}_$(v staged)+3.efi" &&
		test -f "$esp/${IMAGE_ID}_$(v staged)-fallback+3.efi"
	'
	test_expect_success 'the host-only initrd is the smaller one' '
		test "$(stat -c %s "$cache/autodetect/initrd")" -lt \
			"$(stat -c %s "$cache/generic/initrd")"
	'
	test_info bootctl list --no-pager
	# bootctl ids drop the boot counter.
	test_expect_success 'bootctl takes the fallback entry name' '
		bootctl list --no-pager > "$TEST_STATE/list" 2>&1 &&
		! grep "Invalid loader entry name" "$TEST_STATE/list" &&
		grep "id: ${IMAGE_ID}_$(v staged)-fallback.efi$" "$TEST_STATE/list"
	'
	test_expect_success 'the host-only UKI is the default' '
		test "$(default_entry)" = "${IMAGE_ID}_$(v staged).efi"
	'
	test_expect_success 'its tries spent, as on new hardware' '
		mv "$esp/${IMAGE_ID}_$(v staged)+3.efi" \
			"$esp/${IMAGE_ID}_$(v staged)+0-3.efi"
	'
	test_reboot
fi

if test_stage 2; then
	test_expect_success 'booted the same version' '
		test "$IMAGE_VERSION" = "$(v staged)"
	'
	test_expect_success 'through the fallback, now blessed' '
		test -f "$esp/${IMAGE_ID}_$(v staged)-fallback.efi" &&
		test -f "$esp/${IMAGE_ID}_$(v staged)+0-3.efi"
	'
	test_expect_success 'discard removes both UKIs of a version' '
		test_update next update --noconfirm -Q &&
		"$IMAGE_ID" discard > "$TEST_STATE/discard.log" 2>&1 &&
		! ls "$esp/${IMAGE_ID}_$(v next)"*
	'
	test_expect_success 'no failed units' '
		test -z "$(systemctl --failed --no-legend)"
	'
	test_done
fi

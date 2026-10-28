#!/bin/bash
# What the update relies on from mkfs.erofs --incremental: an overlay
# upper appended to a reflinked copy of the lower image equals the merged
# view. metacopy=off, redirect_dir=off, --ovlfs-strip=1 (whiteouts become deletions), opaque
# dirs expanded to whiteouts first (mkfs.erofs ignores the xattr). Images
# are 48bit, as the update builds its full images: without it the root
# inode nid is 16 bits and a changed root dir can make --incremental fail,
# which the update answers with a full image (the fallback test).
# Re-run after erofs-utils upgrades.

# shellcheck source=test-lib.sh
. /root/tests/test-lib.sh

w=/var/tmp/erofs-incremental
rm -rf "$w"
mkdir -p "$w"
cd "$w" || exit 1

# Paths, type, mode, size (not for dirs: overlayfs and erofs report
# directory sizes differently) and content hashes.
manifest() {
	(cd "$1" && find . -mindepth 1 ! -type d -printf '%p %y %m %s\n' | sort)
	(cd "$1" && find . -mindepth 1 -type d -printf '%p %y %m\n' | sort)
	(cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
}

# Same as the update's expand_opaque, on <upper> over <lower>.
expand_opaque() {
	local upper="$1" lower="$2" dir rel entry
	getfattr --absolute-names --recursive --physical --no-dereference --dump \
		--match='^trusted\.overlay\.opaque$' "$upper" \
		| sed -n 's/^# file: //p' \
		| while IFS= read -r dir; do
			rel="${dir#"$upper"}"
			shopt -s dotglob nullglob
			for entry in "$lower$rel"/*; do
				entry="$dir/${entry##*/}"
				if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
					mknod "$entry" c 0 0
				fi
			done
			setfattr --remove=trusted.overlay.opaque "$dir"
		done
}

# round <lower image> <ops function> <output image>: leaves the merged
# view's manifest in <out>.ref and the built image's in <out>.got.
round() {
	local lower="$1" ops="$2" out="$3"
	mkdir -p "$out".{lower,upper,work,mnt,check}
	mount -o ro "$lower" "$out.lower" &&
	mount -t overlay overlay \
		-o "lowerdir=$w/$out.lower,upperdir=$w/$out.upper,workdir=$w/$out.work" \
		-o metacopy=off,redirect_dir=off \
		"$out.mnt" &&
	(cd "$out.mnt" && "$ops") &&
	manifest "$out.mnt" > "$out.ref" &&
	umount "$out.mnt" &&
	expand_opaque "$w/$out.upper" "$w/$out.lower" &&
	cp --reflink=always "$lower" "$out" &&
	mkfs.erofs --quiet -zzstd --incremental=data --ovlfs-strip=1 \
		"$out" "$out.upper" &&
	umount "$out.lower" &&
	mount -o ro "$out" "$out.check" &&
	manifest "$out.check" > "$out.got" &&
	umount "$out.check"
}

# set_shared_bytes <file> <set...>: bytes of <file> shared with the others
# in <set> (btrfs filesystem du columns: total, exclusive, set shared,
# filename).
set_shared_bytes() {
	local file="$1"
	shift
	btrfs filesystem du --raw "$@" | awk -v f="$file" '$4 == f { print $3 }'
}

# add, modify, delete file and dir, replace dir (opaque), chmod only,
# rename file and dir, new nested dir, new symlink
ops1() {
	echo new > added.txt
	echo changed > modify.txt
	rm delete.txt
	rm -r deldir
	rm -r opaquedir && mkdir opaquedir && echo new > opaquedir/new1
	chmod 600 chmod.txt
	mv big.bin moved.bin
	mv movedir renamed-dir
	mkdir -p newdir/deep && echo x > newdir/deep/x
	ln -s keep.txt link-to-keep
}

# on top of round 1: delete what it added, replace a dir it created
ops2() {
	rm added.txt
	echo changed-again > modify.txt
	rm -r newdir && mkdir newdir && echo y > newdir/y
	echo again > opaquedir/new2
	rm link-to-keep
	head -c 1048576 /dev/urandom > blob2.bin
}

# grow the root directory well past its inline size
ops_grow_root() {
	local i
	for i in $(seq 1 300); do
		echo "$i" > "root-entry-$i"
	done
}

test_expect_success 'base image' '
	mkdir -p base/deldir base/opaquedir base/sub &&
	echo keep > base/keep.txt &&
	echo original > base/modify.txt &&
	echo gone > base/delete.txt &&
	mkdir -p base/movedir &&
	echo m > base/movedir/m &&
	echo a > base/deldir/a &&
	echo b > base/deldir/b &&
	echo old > base/opaquedir/old1 &&
	echo old2 > base/opaquedir/.hidden &&
	echo mode > base/chmod.txt &&
	head -c 4194304 /dev/urandom > base/big.bin &&
	head -c 4194304 /dev/urandom > base/sub/untouched.bin &&
	mkfs.erofs --quiet -zzstd -E48bit base.erofs base
'

test_expect_success 'round 1 builds' 'round base.erofs ops1 v1.erofs'
test_expect_success 'round 1 image equals the merged view' '
	diff v1.erofs.ref v1.erofs.got
'
test_expect_success 'round 2 (incremental on incremental) builds' '
	round v1.erofs ops2 v2.erofs
'
test_expect_success 'round 2 image equals the merged view' '
	diff v2.erofs.ref v2.erofs.got
'
test_expect_success 'appended rounds share the base extents' '
	test "$(set_shared_bytes v2.erofs base.erofs v1.erofs v2.erofs)" \
		-ge "$(stat --format=%s base.erofs)"
'
test_info btrfs filesystem du base.erofs v1.erofs v2.erofs

# The update's fallback when --incremental fails: the upper (whiteouts
# expanded) as top lower layer over the old image, built as a full image.
test_expect_success 'fallback full image equals the merged view' '
	mkdir -p fallback.mnt fallback.check &&
	mount -o ro v1.erofs v2.erofs.lower &&
	mount -t overlay overlay \
		-o "lowerdir=$w/v2.erofs.upper:$w/v2.erofs.lower" fallback.mnt &&
	mkfs.erofs --quiet -zzstd -E48bit fallback.erofs fallback.mnt &&
	umount fallback.mnt &&
	umount v2.erofs.lower &&
	mount -o ro fallback.erofs fallback.check &&
	manifest fallback.check > fallback.got &&
	umount fallback.check &&
	diff v2.erofs.ref fallback.got
'
# Without 48bit the root inode nid is 16 bits: an appended root past nid
# 65535 must fit the old root slot, which a changed root dir may not.
test_expect_success 'with 48bit, a grown root dir builds incrementally' '
	round base.erofs ops_grow_root grow48.erofs &&
	diff grow48.erofs.ref grow48.erofs.got
'

test_done

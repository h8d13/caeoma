#!/bin/bash
# Host-side: render substitutes __NAME__ in paths, contents and symlink
# targets and rejects bad ids; install-glue writes only changes and drops
# what a later glue no longer has; the repo's own glue rendered for another
# ImageId= keeps no trace of the default one.

repo="$(cd "$(dirname "$0")/.." && pwd)"
TEST_STATE="$(mktemp --directory)"
trap 'rm --recursive --force "$TEST_STATE"' EXIT
. "$repo/tests/test-lib.sh"
cd "$TEST_STATE"
export IMAGE_ID=foo

mkdir -p src/tree/usr/lib/__NAME__ src/scripts
cp "$repo/scripts/render" "$repo/scripts/install-glue" src/scripts/
printf '#!/bin/sh\necho __NAME__ __NAME__\n' > src/tree/usr/lib/__NAME__/run
chmod 0755 src/tree/usr/lib/__NAME__/run
echo keep > src/tree/usr/lib/__NAME__/keep
ln -s ../lib/__NAME__/run src/tree/usr/lib/__NAME__-link

test_expect_success 'render substitutes path, content, mode, link' '
	src/scripts/render src/tree out &&
	test "$(cat out/usr/lib/foo/run)" = "#!/bin/sh
echo foo foo" &&
	test -x out/usr/lib/foo/run &&
	test "$(readlink out/usr/lib/foo-link)" = ../lib/foo/run
'
test_expect_success 'render rejects ids that break names' '
	for id in Foo foo_bar foo.bar -foo ""; do
		! IMAGE_ID="$id" src/scripts/render src/tree bad || exit 1
	done
'
test_expect_success 'install-glue installs tree, scripts and its list' '
	src/scripts/install-glue src root &&
	test -x root/usr/lib/foo/run &&
	test -x root/usr/lib/foo/install-glue &&
	grep --line-regexp usr/lib/foo/keep root/usr/lib/foo/glue.list &&
	! grep glue.list root/usr/lib/foo/glue.list
'
test_expect_success 'install-glue leaves identical files alone' '
	stat --format=%i:%Y root/usr/lib/foo/keep > before &&
	sleep 1 &&
	src/scripts/install-glue src root &&
	stat --format=%i:%Y root/usr/lib/foo/keep > after &&
	cmp before after
'
test_expect_success 'install-glue updates changes, drops removals' '
	echo changed > src/tree/usr/lib/__NAME__/run &&
	rm src/tree/usr/lib/__NAME__/keep &&
	echo local > root/usr/lib/foo/local &&
	src/scripts/install-glue src root &&
	test "$(cat root/usr/lib/foo/run)" = changed &&
	test ! -e root/usr/lib/foo/keep &&
	! grep keep root/usr/lib/foo/glue.list &&
	test -e root/usr/lib/foo/local
'
test_expect_success 'repo glue for another id has no default id left' '
	default="$(sed -n "s/^ImageId=//p" "$repo/mkosi.conf")" &&
	"$repo/scripts/install-glue" "$repo" repo-root &&
	test -x repo-root/usr/bin/foo-update &&
	test -x repo-root/usr/lib/foo/update &&
	! grep --recursive --ignore-case --files-with-matches \
		-e __NAME__ -e "$default" repo-root &&
	! find repo-root -iname "*__NAME__*" -o -iname "*$default*" | grep .
'
test_done

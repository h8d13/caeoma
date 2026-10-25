# shellcheck shell=bash
# Sourced by tests/run and tests/vm-run: the test image is built and booted
# apart from the stock one. Own ImageId (nothing may assume the default),
# own output directory, explicit version (mkosi.version is the stock
# build's). Run from the repo root.

test_out=mkosi.output/tests
test_mkosi=(--image-id=testbox --output-directory="$test_out")
if [ -f "$test_out/version" ]; then
	test_mkosi+=(--image-version="$(cat "$test_out/version")")
fi

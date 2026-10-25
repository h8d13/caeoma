# HACKING

## Do not hardcode anything

Everything should be derived from capabilities:

`ImageId=foo` builds the whole tree with templated `__NAME__`
pre-stamps (`scripts/render`: paths, contents, symlink targets).
Scripts read `$IMAGE_ID` instead; units and other static names live
in `tree/` with `__NAME__`. `tree/` lands on `/`.

`scripts/` in `/usr/lib/__NAME__`.

A new name is a **fresh install**.

## Inside

Inner mechanisms like `/etc/__NAME__/state.d` follow the same rule: any
hard-coded rule should allow to be extended, modified or removed. The
vendor rules in `/usr/lib/__NAME__/state.d` are only defaults: a local
file of the same name replaces one.

## Immutable images

An installed image in `/system` is never written again (`+i`, 0444).
Every change is a new image: stage an update, do not edit one.

Anything running in the tree on update (postinst, finalize, glue) must be
idempotent and write only what changed: identical bytes rewritten are
still a copy-up, so they land in the delta. A no-op update differs only
in `os-release` (`t1300`).

## No backwards-compat

A new image should be able to sync `scripts/` when they move:
`scripts/install-glue` keeps a list of what it installed
(`/usr/lib/__NAME__/glue.list`) and removes what a later glue no longer
has. Rename or move freely, no shims left behind.

## Shell-check

`pre-commit install`. Inline ignores, unless repeated several times then
top-level ignore once.

## Minimalism

Keeps `master` branch in a clean concise spot. Where any configuration can
be made on a branch or worktree. Tries to take least decisions possible, unless
essential to working "base" system.

### Example config

`mkosi.local.conf` is per machine (gitignored), `mkosi.conf` is the
branch's.

Example content of: `mkosi.local.conf`

```ini
[Output]
ImageId=spore
```

Then add any during/post build steps in appropriate locations.

Then build: `mkosi -B -f build`, test in vm `mkosi vm`.

## Tests

Hermetic: own image (`testbox`, `mkosi.output/tests/`), stock build
untouched, no test code in `scripts/`, `tree/` or `mkosi.*`. `t0NNN` run
on the host, the rest in a VM.

```console
tests/run                                 # build test image, all tests
tests/run --no-build                      # last test image
tests/vm-run tests/t1300-noop-update.sh   # one VM test
```

Slow update: start from its closing `Timings:` line. A rebuilt initrd
prints the manifest diff that caused it.

Tools: `utils/erofs-diff` (two images), `utils/uki-inspect` (what a UKI
boots). References: `docs/mkosi` (the version in use), `docs/particleos`.

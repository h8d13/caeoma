# HACKING

## Do not hardcode anything

Everything should be derived from capabilities:

`ImageId=foo` builds the whole tree with templated `__NAME__`
pre-stamps (`scripts/render`: paths, contents, symlink targets).
Scripts read `$IMAGE_ID` instead; units and other static names live
in `tree/` with `__NAME__`. `tree/` lands on `/`, `scripts/` in
`/usr/lib/__NAME__`. A new name is a fresh install.

`tests/t0100-glue.sh` renders the repo for another id and fails on any
leftover of the default one.

## Inside

Similarly inner mechanisms like `/etc/__NAME__/state.d` should behave
similarly: any hard-coded rule should allow to be extended, modified
or removed. The vendor rules in `/usr/lib/__NAME__/state.d` are only
defaults: a local file of the same name replaces one.

## No backwards-compat

A new image should be able to sync `scripts/` when they move:
`scripts/install-glue` keeps a list of what it installed
(`/usr/lib/__NAME__/glue.list`) and removes what a later glue no longer
has. Rename or move freely, no shims left behind.

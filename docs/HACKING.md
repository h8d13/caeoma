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

The update builds the next image from the box's own config: its
`/etc/pacman.conf` (repos, mirrors) for pacman, and for the UKI the `/etc`
the box will boot with (the image's, under the box's changes):
`/etc/kernel/cmdline` (appended to the kernel command line),
`/etc/mkinitcpio.conf.d/*.conf` (appended to the image's initrd config;
`/etc/mkinitcpio.conf` itself is not used), and any file they name.
`/etc/__NAME__/squash-growth`: percent the image may grow through deltas
before a full one is built (default 50). Rebuild the UKI alone, no package
change: `__NAME__-update -Q`.

First boot never prompts (`systemd.firstboot=headless`): it applies the
image's credentials, which mkosi writes to `/usr/lib/credstore/` from
`Locale=`, `Keymap=`, `Timezone=` and `RootPassword=` (`mkosi.conf`: root's
password is root, as install ISOs do; `passwd` on the box, or override in
`mkosi.local.conf`).


## No backwards-compat

A new image should be able to sync `scripts/` when they move:
`scripts/install-glue` keeps a list of what it installed
(`/usr/lib/__NAME__/glue.list`)

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

Some tests take a bit of time (several boots).

Tools: `utils/erofs-diff` (two images), `utils/uki-inspect` (what a UKI
boots), `utils/vm-serial` (drive a VM over its serial console, one command
at a time: `start --tests`, `run <cmd>`, `reboot`, `stop`).

References: `docs/mkosi` (the version in use), `docs/particleos`,
`docs/kde-linux` with `docs/etc-factory` (same stack; /etc by copy +
hash tracking), `docs/transactional-update` (in-box btrfs snapshot
updates; dropped its /etc overlay in 5.0.0, see NEWS).

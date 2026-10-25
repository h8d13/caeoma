# Waste in images, deltas and on the box

Reference: ParticleOS (github.com/systemd/particleos, clone at 4aa5d13).
It builds every version as a full image on a build host and installs it
into an A/B `/usr` partition; nothing is built on the box. Most rows
below exist only because Caeoma derives the next image in-box as a delta.

## 1. Inside every image and delta

Only `usr/` of each erofs is mounted, but the image is the whole tree
(pacman needs it as its root during `caeoma-update`). Anything outside
`/usr`, and any cache inside it, is dead weight, appended to every delta
whenever it changes.

### pacman sync DBs: `/usr/lib/pacman/sync/*.db`

- Waste: repo indexes, ~9 MB rewritten by every `-Sy`; most of the
  10.75 MB `tree` delta.
- ParticleOS: ships only `local/`. `mkosi.conf.d/arch/mkosi.postinst`
  moves `var/lib/pacman/local` to `/usr/lib/pacman`; `sync/` never
  reaches the image. Its `pacman.conf` is only `DBPath = /usr/lib/pacman`
  (no repos): pacman on the box is query-only.
- Change for Caeoma: same split, but keep the box able to sync.
  finalize replaces `/usr/lib/pacman/sync` with a symlink to
  `/var/lib/pacman/sync`. The image holds `local/` only; `pacman -Sy`
  on the box writes to `/var`, so `-Ss`/`-Si` work. `caeoma-update`
  syncs into the tree's `/var` (not in the delta: see the `/var` row).

### Factory `/etc`: `/usr/share/factory/etc`

- Waste: finalize does `rm -rf` + `cp`, so overlayfs copies up all ~800
  files on every update, unchanged ones included.
- ParticleOS: not an issue, a full image is written either way.
  Its `mkosi.finalize` copies `/etc` once with
  `cp --archive --update=none`.
- Change for Caeoma: sync instead of rebuild. Copy a file only when
  its content differs (`cmp`), delete factory files whose `/etc`
  source is gone. Unchanged files are then never touched, so never
  copied up.

### `/etc` granularity (generated `caeoma-etc.conf`)

- Waste: one `L` line per factory file, ~730 of ~800 for CA output
  (`/etc/ssl/certs`, `/etc/ca-certificates/extracted`).
- ParticleOS: a hand-written `usr/lib/tmpfiles.d/etc.conf` overriding
  systemd's, mostly directory links: `L /etc/ssl`,
  `L? /etc/ca-certificates`, `L /etc/security`, `L /etc/xdg`,
  `L /etc/profile.d`, ... Its Arch postinst deletes Arch's
  `tmpfiles.d/arch.conf`, `audit.conf` and `openssh.conf` (their `C`
  copies would pin files as copies instead of links).
- Change for Caeoma: keep the generator for single files, but emit
  one directory `L` for trees that are pure vendor/generated content
  (`ssl`, `ca-certificates`, `security`, `xdg`). Cost: a local file in
  such a directory means replacing the directory link with a real
  directory. Decide on deleting Arch's `C` lines (profile, shells,
  hosts, ...) separately: they make those files local copies that
  never update.

### Generated files rewritten with identical content

- Waste: `caeoma-etc.conf`, `00-caeoma-baked.preset`, sd-boot in the
  factory ESP: rewritten each update, so copied up even when equal.
- ParticleOS: not an issue (full images).
- Change for Caeoma: write to a temp file, replace only if it
  differs. `bootctl install` → `bootctl update` (only copies a newer
  sd-boot).

### The image's own `/var`: `cache/`, `log/` (`pacman.log`), `tmp/`, `lib/systemd/`

- Waste: never mounted (`/var` comes from `@system`), yet in the image
  and in deltas when pacman writes there.
- ParticleOS: avoided at the root: `mkosi.repart/12-usr.conf` is
  `CopyFiles=/usr:/`, so only `/usr` goes into the erofs; the build
  tree's `/var` is dropped and its `/etc` survives only as factory.
- Change for Caeoma: a `/usr`-only image would need the in-box update
  to rebuild a full root (`/etc` from factory) as the overlay lower;
  overlayfs does not see mounts nested in a lower layer, so that is
  not a clean drop-in. Instead finalize empties the tree's `/var`
  (keeping only what packages need as directories) before mkfs.

### Initramfs from pacman's mkinitcpio hook: `/boot/initramfs-*.img`

- Waste: built on every kernel update and deleted by finalize; ~25 s,
  since `build-uki` builds its own initrd anyway.
- ParticleOS: not an issue: no kernel installs on the box; the initrd
  is built by mkosi on the build host.
- Change for Caeoma: mask the hook in the tree:
  `/etc/pacman.d/hooks/90-mkinitcpio-install.hook → /dev/null`.

### UKI rebuilt when the kernel did not change

- Waste: mkinitcpio runs on every update (~25 s) only because the
  initrd carries os-release, which names the erofs to mount.
- ParticleOS: not an issue: one full build per version on the host.
- Change for Caeoma: reuse the previous initrd and append a small
  cpio holding the new `/usr/lib/os-release` (later initrds override
  earlier files); run mkinitcpio only when the kernel version or the
  glue changed.

## 2. Growing on the box

### Package cache: `/var/cache/pacman/pkg`

- Waste: `caeoma-update` binds it in so downloads are reused, but
  pacman never deletes anything. After a successful update the
  packages are inside the image: pure duplication.
- ParticleOS: not an issue: no package installs on the box; caching
  is on the build host (`CacheDirectory=mkosi.cache`,
  `Incremental=yes`).
- Change for Caeoma: empty it after a successful stage. Keeping only
  the last version's packages (`paccache -rk1`) needs pacman-contrib.

### Leftovers of a run: `/system/.caeoma-update`

- Already handled: `cleanup()` removes it on exit, failed runs
  included.

## What does not apply

ParticleOS has no in-box builds, so every delta-specific row (factory
rewrite, identical rewrites, pkg cache, initrd reuse) is Caeoma's own
cost for building on the box. The two rows worth copying as-is: no
sync DBs in the image, directory-level `/etc` links.

## Status

Implemented, not yet built or measured:

| Row | Where | Matches ParticleOS |
|---|---|---|
| sync DBs | finalize (symlink), update (bind), tmpfiles `caeoma-pacman.conf` | yes: only `local/` in the image |
| factory `/etc` sync | finalize (`cmp`, stale removal, machine-state skip) | same end state as its one-shot copy |
| directory links | finalize (`ssl ca-certificates security xdg`) | yes: its `L /etc/ssl`, `L? /etc/ca-certificates`, `L /etc/security`, `L /etc/xdg` |
| identical rewrites | finalize (`replace_if_changed`), postinst (`bootctl update`), update (`copy_changed` glue, no `touch`) | n/a (full images) |
| image `/var` | finalize (empties, refuses if anything is mounted below) | yes in effect: it ships `/usr` only |
| mkinitcpio hook | `mkosi.extra/etc/pacman.d/hooks/90-mkinitcpio-install.hook → /dev/null` | n/a |
| initrd reuse | build-uki (key file, `.initrd` of the running UKI + os-release cpio), update (`--squash` rebuilds) | n/a |
| pkg cache | update (emptied after a successful stage) | n/a |

Not done: Arch's own `C` lines (`arch.conf`, `audit.conf`, `openssh.conf`,
deleted by ParticleOS), left as a separate decision.

## Verification

Use one Arch archive snapshot for every run so the package set, and
so the expected delta, stay fixed.

1. Baseline on the current scripts: `-Syu`, add `tree`, remove `tree`;
   record `btrfs filesystem du` exclusive bytes per version and the
   time of each update.
2. Apply the changes above; repeat the same three steps on the same
   snapshot.
3. `--squash` at the end; compare total size and whether a delta on
   top of a squashed image still shares.
4. Check the common approach against measured numbers: the rows
   ParticleOS avoids by design should drop to near zero; the
   delta-only rows should shrink to the actual package changes.

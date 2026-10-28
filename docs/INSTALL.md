# Walk-through

A typical install on `caeoma` is slightly different but mainly still follows:
[Install Wiki](https://wiki.archlinux.org/title/Installation_guide)

But here are the steps regardless.

Secure Boot must be off: the UKIs are unsigned.

## After succesfully building

You should have added (your) essentials in `mkosi.local.conf` like `*-ucode`, `linux-firmware`, `iwd` ...

See [HACKING](./HACKING.md) and [example conf](../mkosi.local.conf.example)

You will find the image in `mkosi.output`, timestamped: `<ImageId>_<version>.raw`.

`dd` it to the whole disk (not a partition), it grows to fill it on first boot:
```console
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
sudo dd if=mkosi.output/caeoma_<version>.raw of=/dev/sdX bs=4M conv=fsync oflag=direct status=progress
```

Encrypted root (optional): a passphrase in `mkosi.passphrase` (0600, no newline) before building, asked at boot.
Every disk flashed from that image shares it: change it with `cryptsetup luksChangeKey /dev/<disk>2`.
It fills the disk on the first boot, like a plain root.

## Config precedence

`mkosi.local.conf` (gitignored) over `mkosi.conf`:

- One value (`RootPassword=`, `Locale=`, `Keymap=`, `Timezone=`, `Mirror=`...):
  `mkosi.local.conf` wins. Command line flags win over both.
- Lists (`Packages=`, `KernelCommandLine=`...): both add up.

So `root:root`, `C.UTF-8`, `us`, `UTC` unless `mkosi.local.conf` says otherwise.

## What is **different from a regular install?**

1. `/usr` is the image. Plain `pacman` (or anything writing to `/usr`) still
   works, on an overlay kept per version: a new version starts without it.
2. To keep packages: `__NAME__ update [pacman args]` (`caeoma update`), default `-Syu`,
   then reboot :) It stages a new image; each update builds on the newest staged one,
   `__NAME__ discard` starts over. `-S` without `-u` is refused (partial upgrade).
3. Happy with what you tried? `__NAME__ commit` makes it a new version:
   your `/usr` writes and `/etc` changes, minus machine state (accounts, keys,
   wifi secrets: `machine` rules in `/usr/lib/__NAME__/state.d`).
   `__NAME__ rollback` boots the version before at the next reboot.
4. `/etc`, `/var` and `/home` outlive updates. `/etc` shows the image's
   defaults under your changes: edit, delete, `systemctl disable` as usual.
   Committed changes follow their version; `/var` and `/home` never do.
5. The update builds from your config: `/etc/pacman.conf` (repos), and for the
   kernel/initrd `/etc/kernel/cmdline` and `/etc/mkinitcpio.conf.d/*.conf`.
6. Each version boots a UKI made for this machine, with a generic fallback used
   on its own if that one fails (e.g. new hardware). Older versions stay in the
   boot menu.

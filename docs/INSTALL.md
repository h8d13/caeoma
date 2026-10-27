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

## Config precedence

`mkosi.local.conf` (yours, gitignored) over `mkosi.conf`:

- One value (`RootPassword=`, `Locale=`, `Keymap=`, `Timezone=`, `Mirror=`...):
  `mkosi.local.conf` wins. Command line flags win over both.
- Lists (`Packages=`, `KernelCommandLine=`...): both add up.

So `root:root`, `C.UTF-8`, `us`, `UTC` unless `mkosi.local.conf` says otherwise.

## What is **different from a regular install?**

1. `/usr` is the image, read-only. A plain `pacman -S` still works, on a throwaway
   `/usr` gone at the next boot (to try things).
2. To keep packages: `__NAME__-update [pacman args]` (`caeoma-update`), default `-Syu`,
   then reboot :) It stages a new image; each update builds on the newest staged one,
   `__NAME__-update discard` starts over. `-S` without `-u` is refused (partial upgrade).
3. `/etc`, `/var` and `/home` are yours and outlive updates. `/etc` shows the image's
   defaults under your changes: edit, delete, `systemctl disable` as usual.
4. The update builds from your config: `/etc/pacman.conf` (repos), and for the
   kernel/initrd `/etc/kernel/cmdline` and `/etc/mkinitcpio.conf.d/*.conf`.
   `__NAME__-update -Q` rebuilds them with no package change.
5. Each version boots a UKI made for this machine, with a generic fallback used
   on its own if that one fails (e.g. new hardware). Older versions stay in the
   boot menu.

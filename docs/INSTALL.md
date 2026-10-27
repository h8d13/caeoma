# Walk-through

A typical install on `caeoma` is slightly different but mainly still follows: 
[Install Wiki](https://wiki.archlinux.org/title/Installation_guide)

But here are the steps regardless.

## After succesfully building 

You should have added (your) essentials in `mkosi.local.conf` like `*-ucode`, `linux-firmware`, `iwd` ... 
See [HACKING](./HACKING.md) and [example conf](../mkosi.local.conf.example)

You will find the `.raw` image in `mkosi.output` timestamped.

You can `dd` it to a storage device (which grows on first boot automatically).

Once booted up: What is **different from a regular install?**

1. `pacman` calls are read-only by default, they vanish on the next boot.
2. unless you use `__NAME__-update [pacman args]` default to `-Syu` and reboot after :)

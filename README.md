# CAEOMA

> "An aecium in some rust fungi that has no surrounding membrane"

## Layout

`scripts/` - Anything that lives "in-the-box" for self-update
`utils/` - Anything that lives outside for tests or inspection

## References

This repo holds simplified versions of references:

- https://invent.kde.org/kde-linux/kde-linux
- https://github.com/systemd/particleos

And mainly uses:

- https://github.com/systemd/mkosi

---

This project aims to explore how delta `erofs` layers can work.
Which isn't currently supported by [`sysupdate`](https://www.freedesktop.org/software/systemd/man/latest/systemd-sysupdate.html)

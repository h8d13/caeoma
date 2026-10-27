# Design

ID is `ImageId=` (`mkosi.conf`): every name below derives from it.

## Build, disk and boot

```mermaid
flowchart TD
	subgraph BUILD["mkosi build (host)"]
		P["mkosi.postinst.chroot<br/>install-glue: tree/ + scripts/<br/>rendered for ImageId=<br/>mirrorlist, cmdline"]
		PI["scripts/postinst<br/>os-release (IMAGE_VERSION)<br/>sd-boot to factory ESP<br/>build-uki: mkinitcpio + ukify"]
		F["scripts/finalize<br/>vendor config into /usr<br/>apply presets, sync factory /etc<br/>empty /boot<br/>state rules: carry into /usr/lib/sysimage, drop"]
		R["mkosi.repart<br/>esp.raw + whole tree as erofs"]
		PO["mkosi.postoutput + install.repart<br/>assemble disk.raw"]
		P --> PI --> F --> R --> PO
	end

	subgraph DISK["Installed disk"]
		ESP["ESP vfat (2 GiB)<br/>sd-boot<br/>ID_VER+3.efi (host-only, default)<br/>ID_VER-fallback+3.efi (any machine)"]
		subgraph BTRFS["root btrfs"]
			TOP["top level = /system<br/>ID_VER.erofs ..."]
			SYS["@system = / (rw)<br/>skeleton, mountpoints"]
			HOME["@home = /home (rw)"]
			VAR["@var = /var (rw)"]
			ETCU["@etc = /etc overlay upper (rw)"]
		end
	end

	PO --> ESP
	PO --> TOP
	PO --> SYS
	PO --> HOME
	PO --> VAR
	PO --> ETCU

	subgraph BOOT["Boot"]
		SB["sd-boot picks UKI (boot counting +3):<br/>newest good; a spent host-only UKI<br/>falls back to its version's fallback"]
		GEN["initrd: ID-usr-generator<br/>reads os-release IMAGE_ID/VERSION"]
		M1["mount top level at /sysroot/system"]
		M2["mount VER.erofs subdir usr/<br/>at /sysusr/usr, bind to /sysroot/usr"]
		ROOT["@system as / (gpt-auto, rootflags)"]
		DD["ID-etc-dedup (first boot of VER)<br/>drop upper entries the image<br/>ships alike (old or new lower)"]
		M3["overlay at /sysroot/etc<br/>lower = factory/etc of VER<br/>upper = @etc/upper"]
		SB --> GEN --> M1 --> M2 --> DD --> M3
		GEN --> ROOT
	end

	ESP --> SB
	TOP --> M1
	SYS --> ROOT
	ETCU --> M3
	VAR --> RUN

	subgraph RUN["Running system"]
		ETC["/etc: image defaults, local<br/>edits/deletes copied up and kept"]
		VM["var.mount: @var at /var<br/>(unit file: journald released at shutdown)"]
		PAC["ID-state-generator (carry rules)<br/>/usr/lib/sysimage/pacman/local bound on /var/lib/pacman/local"]
		SX["systemd-sysext Mutable=ephemeral<br/>anchor ext in /run<br/>writable /usr, lost at reboot"]
		SX --> PAC
	end

	M3 --> RUN
	ROOT --> RUN
```

## Update (ID-update)

```mermaid
flowchart TD
	START["ID-update [--squash] [pacman args]<br/>-S without -u refused (partial upgrade)<br/>(ID-update discard: delete staged versions)"] --> BASE["base = newest staged version that can boot,<br/>else the running one"]
	BASE --> V["version = UTC now<br/>must be newer than base"]
	V --> OV["overlay at /system/.ID-update<br/>lower = base VER.erofs (ro)<br/>upper = empty, metacopy=off"]
	OV --> G{"glue in /var/lib/ID?"}
	G -- yes --> GC["install-glue: render tree/ + scripts/<br/>write changes, drop removals"]
	G -- no --> MB
	GC --> MB["bind host /proc /sys /dev /run<br/>keyring, resolv.conf, sync DBs, pkg cache<br/>carry paths bound from tree /usr/lib/sysimage<br/>the box's /etc/ID (ro)"]
	MB --> PM["pacman --root tree -Syu ...<br/>(the box's pacman.conf)"]
	PM --> CH["chroot: postinst, /etc = the box's (ro snapshot of<br/>@etc upper on the tree's): os-release, UKIs<br/>(host-only + fallback; kernel/cmdline,<br/>mkinitcpio.conf.d, microcode)<br/>chroot: finalize (re-freeze, idempotent, mirrorlist,<br/>names new .pacnew) with the box's state.d rules"]
	CH --> SQ{"--squash, or base grew past<br/>the last full image by squash-growth%?"}
	SQ -- yes --> FULL["mkfs.erofs full image<br/>from merged view"]
	SQ -- no --> EO["expand_opaque<br/>opaque dirs to whiteouts"]
	EO --> RL["cp --reflink=always current to next"]
	RL --> INC["mkfs.erofs --incremental=data<br/>--ovlfs-strip=1 append upper"]
	FULL --> INST
	INC --> INST["install_next<br/>rename erofs into /system<br/>UKIs to ESP: VER-fallback+3.efi, then VER+3.efi"]
	INST --> PR["prune: keep newest 3 + running"]
	PR --> CL["empty pkg cache, cleanup mounts"]
	CL --> RB["reboot: sd-boot picks new UKI<br/>bless-boot drops +N on success"]
```

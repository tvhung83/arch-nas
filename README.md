# arch-nas

Small core + one self-contained file per service.

    install.sh     live ISO only: config wizard → wipe disk → btrfs → pacstrap → setup.sh in chroot
    configure.sh   interactive wizard, writes config.local   (./configure.sh web  = just DNS/HTTPS questions)
    setup.sh       ./setup.sh [module ...]  runs modules (default: $MODULES) on any Arch box
    lib.sh         helpers (pkg, put, apply, …) + global defaults
    config.env     PUBLIC defaults (no secrets)      config.local  your answers (git-ignored, mode 600)
    modules/       system users ssh network shell storage firewall samba nfs caddy ddns
                   database rustapps snapshots verify   (+ boot: install-only)
    tools/         release.sh (dev machine only; not shipped in the archive)

## Install (published copy)

    curl -fsSL is.gd/<alias> | tar xz && cd arch-nas && bash install.sh

The wizard asks about every setting (Enter keeps the default, `-` clears). Answers are saved to `config.local`,
which is copied to /root/arch-nas on the new system so later `./setup.sh` runs reuse it.
Skip the wizard with `./install.sh --defaults`; reuse a config.local you scp'd over and it will just ask to confirm.

## DNS tokens

AfraidDNS hostnames default to a placeholder (`host=CHANGE_ME`): the updater timer is enabled but skips them, and
Caddy serves plain HTTP for them. When you have real tokens:  `./configure.sh web && ./setup.sh ddns caddy`

## External drives

NTFS drives stay NTFS: storage only mounts them (rw, owned by ADMIN_USER) at /srv/nas/<label>; samba/nfs share what
storage registered. New drive later: `sudo ./setup.sh storage samba nfs` · unplug safely: `sudo nas-eject`

## Publishing (dev machine)

    chmod +x *.sh modules/*.sh tools/*.sh      # so git records the exec bits
    git init && git add -A && git commit -m init
    gh repo create arch-nas --public --source . --push
    ./tools/release.sh --alias <name>        # builds the archive from committed files and uploads release "stable"
    ./tools/release.sh                       # later updates: same URL, same short link

Module rules: sources ../lib.sh, installs its own packages, is idempotent, reads config, keeps extra knobs as
`: "${VAR:=default}"`, works in a chroot or on a running system. New service = modules/<name>.sh + add it to MODULES.

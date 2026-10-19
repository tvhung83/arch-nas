# arch-nas

Headless Arch Linux NAS installer: a small core plus one self-contained module per service.

    install.sh     live ISO only: config wizard → wipe disk → btrfs → pacstrap → setup.sh in chroot
    configure.sh   interactive wizard, writes config.local   (./configure.sh web = only the DNS/HTTPS questions)
    setup.sh       ./setup.sh [module ...]  runs modules (default: $MODULES) on any Arch box
    lib.sh         helpers (pkg, put, apply, …) + global defaults
    config.env     PUBLIC defaults (no secrets)      config.local  your answers (git-ignored, mode 600)
    modules/       system users ssh network shell storage firewall samba nfs caddy ddns
                   database rustapps snapshots verify   (+ boot: install-only)
    tools/         release.sh (dev machine only; not shipped in the archive)

## 1. Install (published copy)

    curl -fsSL tinyurl.com/<alias> | tar xz && cd arch-nas && bash install.sh

The wizard asks about every setting (Enter keeps the default, `-` clears). Answers go to `config.local`, which is
copied to /root/arch-nas on the new system so later `./setup.sh` runs reuse it. Skip the wizard with
`./install.sh --defaults`; if a config.local is already there it just asks to confirm.

---

# 2. After install.sh — what's next

Every `./setup.sh` / `./configure.sh` command below runs **as root from the scripts folder on the NAS**:

    ssh robert@nas.local          # robert = your ADMIN_USER
    sudo -i
    cd arch-nas && chmod +x *.sh modules/*.sh

### 2.0 What you have right now

| State | What |
|---|---|
| Running | sshd · NetworkManager · avahi (`nas.local`) · nftables · smb · nfsv4-server · postgresql (if DB_ENGINE=postgresql) |
| Running while AFRAID_DOMAINS is non-empty | caddy + afraid-ddns.timer. Default is a **placeholder** (`yourhost.mooo.com=CHANGE_ME`): Caddy serves plain HTTP, the updater skips the placeholder |
| Timers | fstrim · reflector (mirrors) · btrfs-scrub (monthly) · systemd-timesyncd |
| Not done yet | real DNS tokens · router port-forwards · certificates · SSH keys (unless given in the wizard) · external drives (unless plugged in during install) |

Work through 2.1 → 2.7 in order.

### 2.1 First boot

1. Remove the USB stick and boot from the SSD. If the PC returns to the Ventoy menu or finds no OS, open the one-time
   boot menu (F7/F11/F12/Esc depending on the board) and pick "Linux Boot Manager". systemd-boot is unsigned, so keep
   **Secure Boot off**. Optional: BIOS "restore on AC power loss" → On, so the NAS returns after a power cut.
2. Find it: `ssh robert@nas.local`, or read the router's DHCP client list. Otherwise plug in a monitor + keyboard,
   log in as robert and run `ip -br a`.
3. **Reserve its IP** in the router (DHCP reservation by MAC; `ip -br link` shows it). Port-forwarding needs this.
4. Log in with the password you chose during install.

### 2.2 Verify and update

    ./setup.sh verify        # services, mounts, routes, failed units, last DDNS runs
    pacman -Syu              # a read-only btrfs snapshot is taken first (last 8 kept); reboot after a kernel update

### 2.3 SSH: add your public key, then allow keys only

Do the steps in this order and keep your first session open until step 4 works.

1. On the Mac (skip if you already have a key): `ssh-keygen -t ed25519 -C "mac-mini"`
2. Install the key while password login still works:

       ssh-copy-id robert@nas.local
       # or: cat ~/.ssh/id_ed25519.pub | ssh robert@nas.local 'cat >> ~/.ssh/authorized_keys'

3. Test it **in a new terminal**, no password prompt allowed:

       ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no robert@nas.local

4. Lock it down. On the NAS:

       ./configure.sh access      # "SSH password login" → no   (the other questions: Enter keeps them)
       ./setup.sh ssh

   `no` refuses to apply if no key exists, so you cannot lock yourself out by accident. The default `auto` already
   turns passwords off once any key is present. The module writes `PasswordAuthentication no`,
   `AuthenticationMethods publickey` and `PermitRootLogin no`, and merges keys (it never deletes any).
5. Verify: `sshd -T | grep -Ei '^(passwordauthentication|authenticationmethods|permitrootlogin)'`
   and from the Mac `ssh -o PubkeyAuthentication=no robert@nas.local` must say `Permission denied (publickey)`.

More keys later: `ssh-copy-id` again, or set SSH_KEYS_URL (e.g. `https://github.com/<user>.keys`) and `./setup.sh ssh`.
Locked out anyway? The console (monitor + keyboard) still accepts robert's password; see Troubleshooting.

### 2.4 Firewall (nftables)

Policy: **drop everything inbound** except
- the LAN (`LAN_CIDR`, default all private IPv4 ranges + IPv6 link-local/ULA): SSH, SMB, NFS, mDNS, everything
- the internet: TCP 80, TCP 443, UDP 443 (HTTP/3). SSH, SMB and NFS are never reachable from outside.

Inspect: `nft list ruleset`. Tighten or change:

    ./configure.sh access          # LAN_CIDR → e.g. 192.168.1.0/24
    ./setup.sh firewall nfs        # nfs too: its exports use LAN_CIDR
    # extra public ports: add  WAN_TCP="80, 443, 8443"  to config.local, then ./setup.sh firewall

Test from outside (phone hotspot or a VPS): `nmap -Pn -p 22,445,2049,80,443 <your-public-ip>` → only 80/443 open.
Need remote shell access? Use a VPN (e.g. WireGuard) instead of forwarding port 22.

IPv6: the NAS is `link-local` only by default (`IPV6_MODE`), so nothing public is exposed over IPv6 and LAN clients
connect over fe80:: or IPv4 and are never blocked. With `IPV6_MODE=auto` the NAS gets a global address and you must set
`LAN_CIDR6` to your LAN's prefix, or clients using global IPv6 will be dropped.

### 2.5 External drives (NTFS boxes)

The drives stay plain NTFS: the scripts only mount them (read-write, owned by robert) at `/srv/nas/<label>` and never
format, partition, repair or write anything on them.

1. Plug the boxes in, wait ~10 s, check: `lsblk -f` (FSTYPE `ntfs`).
2. `./setup.sh storage samba nfs` — mounts each drive, adds `/etc/fstab` entries (`nofail`, so boot never hangs),
   creates one SMB share and one NFS export per drive.
3. Check: `findmnt -t ntfs3` and `ls /srv/nas/<label>`. Rename mounts with `MOUNT_NAMES="<uuid>=media"` in config.local
   (`blkid` shows UUIDs), then re-run step 2.
4. Connect: macOS Finder ⌘K `smb://nas.local/<label>` · Windows `\\nas.local\<label>` (or the IP) ·
   Linux `sudo mount -t nfs4 nas.local:/<label> /mnt/nas`. SMB login: robert + the Samba password
   (change: `sudo smbpasswd -a robert`). NFS clients are squashed to robert (LAN-trusted).
5. Unplugging: `sudo nas-eject` first (stops smb/nfs, unmounts, syncs), otherwise the volume is left "dirty" and
   Windows offers chkdsk. After re-plugging: `sudo mount -a && sudo systemctl restart nfsv4-server smb`.

A drive that will not mount read-write is almost always flagged dirty (Windows fast-startup/hibernate or unsafe
removal): `dmesg | grep -i ntfs`, then shut Windows down fully / run chkdsk there. `ntfsfix` would clear the flag from
Linux but modifies the volume, so the scripts never run it. While unmounted, each mount point is an immutable empty
directory, so clients cannot fill the SSD.

### 2.6 AfraidDNS

1. At freedns.afraid.org: Subdomains → add one per hostname (type **A**, pick a domain such as mooo.com, destination =
   your current public IP, `curl -4 ifconfig.me`).
2. Dynamic DNS page → each hostname has a "Direct URL" like `https://sync.afraid.org/u/<TOKEN>/`. The token is the
   part after `/u/` (as far as I know an `update.php?<TOKEN>` URL carries the same token). Each hostname has its own.
3. On the NAS (**ddns before caddy**, DNS must point at you before certificates are requested):

       ./configure.sh web            # [t] update the tokens of the listed hostnames, or [r] replace the list
       ./setup.sh ddns caddy

4. Verify:

       systemctl start afraid-ddns.service
       journalctl -u afraid-ddns -n 5 --no-pager          # one status line per hostname
       getent ahostsv4 nas.mooo.com | head -1; curl -4 -s ifconfig.me     # same IP (DNS caches can lag a few minutes)

The updater runs every 5 minutes, IPv4 only, with the tokens in /etc/afraid-ddns.conf (mode 600, never logged).
Hostnames still set to `CHANGE_ME` are skipped. The IP it registers is the one afraid.org sees, so behind CGNAT it
would be your ISP's address and Let's Encrypt cannot work.

### 2.7 Router + Let's Encrypt with Caddy

Prerequisites: (a) a public IPv4 — the router's WAN address must equal `curl -4 ifconfig.me` and not be in
100.64.0.0/10 (that is CGNAT); (b) the ISP does not block inbound 80/443 (some residential lines do; test from mobile
data); (c) the DHCP reservation from 2.1; (d) the DNS record from 2.6.

1. Router port-forwards to the NAS's LAN IP: **TCP 80, TCP 443**, optionally UDP 443 (HTTP/3).
2. **First run on Let's Encrypt STAGING** (untrusted test certs, so mistakes cannot hit the real rate limits):

       ./configure.sh web            # Let's Encrypt contact email (optional) → ACME_STAGING = 1
       ./setup.sh caddy
       journalctl -u caddy -f        # wait for "certificate obtained successfully"

3. Check from outside the LAN (or from inside, bypassing hairpin NAT):

       curl -kI https://nas.mooo.com/healthz                                        # 200, add -k while on staging
       curl -kI --resolve nas.mooo.com:443:<NAS-LAN-IP> https://nas.mooo.com/healthz
       echo | openssl s_client -connect nas.mooo.com:443 -servername nas.mooo.com 2>/dev/null | openssl x509 -noout -issuer -dates

4. Go live: `./configure.sh web` → ACME_STAGING = 0, then `./setup.sh caddy`. The issuer should no longer say STAGING.

Caddy then renews certificates by itself (stored in /var/lib/caddy), redirects HTTP→HTTPS and speaks HTTP/2 + HTTP/3 —
nothing to cron. Several hostnames share one site block. Route traffic to your apps with a drop-in per app:

    # /etc/caddy/conf.d/myapp.caddy
    handle_path /myapp/* { reverse_proxy 127.0.0.1:8081 }
    # split by hostname instead:
    #   @api host api.mooo.com
    #   handle @api { reverse_proxy 127.0.0.1:8081 }

    sudo -u caddy caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy

### 2.8 Apps: PostgreSQL and Rust

    sudo -u postgres createuser -P app && sudo -u postgres createdb -O app app     # listens on localhost only
    # DATABASE_URL=postgres://app:<password>@127.0.0.1/app   → put it in /etc/apps/<name>.env

Rust apps run as a hardened systemd template: binary `/opt/apps/<name>/<name>`, environment `/etc/apps/<name>.env`.
Build on the Mac, not on the N150:

    cargo zigbuild --release --target x86_64-unknown-linux-musl          # or any musl cross toolchain
    scp target/x86_64-unknown-linux-musl/release/<name> robert@nas.local:/tmp/
    ssh -t robert@nas.local 'sudo install -D -m755 /tmp/<name> /opt/apps/<name>/<name> && sudo systemctl enable --now app@<name>'
    # logs: journalctl -u app@<name> -f      restart after a new build: sudo systemctl restart app@<name>

### 2.9 Day-2 cheat sheet

| I want to… | Do |
|---|---|
| Update the OS | `pacman -Syu` (snapshot first), reboot after kernel updates |
| Undo a bad update | `ls /.snapshots`, `nas-rollback pre-<timestamp>`, reboot |
| Change any setting | `./configure.sh [system install access nas web db advanced]`, then `./setup.sh <module>` for what changed |
| Add a drive | plug in → `./setup.sh storage samba nfs` |
| Update the scripts | see below |
| Set / change DNS tokens | `./configure.sh web && ./setup.sh ddns caddy` |
| Wi-Fi later | `./configure.sh access` (SSID/password) → `./setup.sh network` (wired still wins) |
| Back up your settings | keep a copy of `/root/arch-nas/config.local` (it holds tokens and the Wi-Fi password) |

Update the scripts on the NAS (config.local is not in the archive, so it is kept):

    sudo -i; cd /root
    curl -fsSL tinyurl.com/<alias> | tar xz --strip-components=1 -C arch-nas      # or scp the .tar.gz over and tar xz -f it
    cd arch-nas && chmod +x *.sh modules/*.sh && ./setup.sh <modules you want re-applied>

### 2.10 Troubleshooting

| Symptom | Fix |
|---|---|
| `nas.local` not found | router DHCP list, or monitor + keyboard and `ip -br a`; `systemctl status avahi-daemon` |
| Won't boot / back at the Ventoy menu | one-time boot menu → "Linux Boot Manager"; Secure Boot off |
| `Permission denied (publickey)` | key not installed: log in on the console, add it to `~/.ssh/authorized_keys` (dir 700, file 600) |
| Locked out of SSH | console login with robert's password, `sudoedit /etc/ssh/sshd_config.d/10-nas.conf` → `PasswordAuthentication yes`, delete the AuthenticationMethods line, `sudo systemctl restart sshd` |
| SSH or SMB hangs from the LAN | your subnet is not in `LAN_CIDR`, or the client uses global IPv6 (see 2.4) |
| Share empty / drive missing | `findmnt -t ntfs3`, `lsblk -f`, `dmesg \| grep -i ntfs` (dirty flag, see 2.5) |
| SMB login fails | the Samba password is separate: `sudo smbpasswd -a robert` |
| Certificate not issued | `journalctl -u caddy`; DNS not pointing at your IP yet, CGNAT, ports 80/443 not forwarded or blocked by the ISP; use staging while testing; failed attempts are rate-limited |
| "placeholder token" warnings | expected until you run `./configure.sh web` |

---

## 3. Publishing (dev machine)

    chmod +x *.sh modules/*.sh tools/*.sh      # so git records the exec bits
    git init && git add -A && git commit -m init
    gh repo create arch-nas --public --source . --push
    export TINYURL_TOKEN=…                     # free TinyURL account → Settings → API (or --via isgd, or the web form)
    ./tools/release.sh --alias <name>          # builds the archive, uploads release "stable", creates + verifies the short link
    ./tools/release.sh                         # later updates: same URL, same short link

Module rules: sources ../lib.sh, installs its own packages, is idempotent, reads config, keeps extra knobs as
`: "${VAR:=default}"`, works in a chroot or on a running system. New service = modules/<name>.sh + add it to MODULES.

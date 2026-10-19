#!/usr/bin/env bash
# btrfs root only: read-only snapshot before every pacman transaction (keeps SNAP_KEEP), monthly scrub,
# and nas-rollback <snapshot> to boot back into one. Put this module LAST so earlier installs aren't snapshotted.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
[[ $(stat -f -c %T /) == btrfs ]] || { warn "root is not btrfs — skipping snapshots"; exit 0; }
: "${SNAP_KEEP:=8}"
pkg btrfs-progs
MODE=755 put /usr/local/bin/btrfs-pre-snapshot <<EOF
#!/usr/bin/env bash
mountpoint -q /.snapshots || exit 0
btrfs subvolume snapshot -r / "/.snapshots/pre-\$(date +%Y%m%d-%H%M%S)" >/dev/null
ls -1d /.snapshots/pre-* | head -n -$SNAP_KEEP | xargs -r -n1 btrfs subvolume delete >/dev/null
EOF
put /etc/pacman.d/hooks/00-btrfs-snapshot.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Snapshot root before pacman transaction
When = PreTransaction
Exec = /usr/local/bin/btrfs-pre-snapshot
EOF
MODE=755 put /usr/local/bin/nas-rollback <<'EOF'
#!/usr/bin/env bash
# usage: nas-rollback <snapshot-name>   (list them: ls /.snapshots)
set -euo pipefail
snap=${1:?usage: nas-rollback <snapshot-name>}
[[ -d /.snapshots/$snap ]] || { echo "no such snapshot:"; ls /.snapshots; exit 1; }
dev=$(findmnt -no SOURCE / | sed 's/\[.*//')
mnt=$(mktemp -d); mount -o subvolid=5 "$dev" "$mnt"
mv "$mnt/@" "$mnt/@.broken-$(date +%s)"
btrfs subvolume snapshot "$mnt/@snapshots/$snap" "$mnt/@"
umount "$mnt"; echo "Rolled back to $snap. Reboot now."
EOF
enable btrfs-scrub@-.timer || warn "could not enable btrfs scrub timer"

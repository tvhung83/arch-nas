#!/usr/bin/env bash
# NFSv4-only: pseudo-root NAS_DIR, one export per mounted drive (clients mount <host>:/<name>).
# NTFS has no POSIX owners, so by default every client is squashed to ADMIN_USER:ADMIN_USER (the owner of the NTFS mounts) (LAN-trusted; tighten NFS_OPTS if needed).
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${NFS_OPTS:=rw,sync,no_subtree_check,all_squash,anonuid=$(id -u "$ADMIN_USER"),anongid=$(id -g "$ADMIN_USER")}"
pkg nfs-utils
put /etc/nfs.conf.d/10-v4only.conf <<EOF
[nfsd]
vers2=n
vers3=n
vers4=y
vers4.1=y
vers4.2=y
udp=n
EOF
install -d "$NAS_DIR"
mapfile -t mounts < <(awk -v d="$NAS_DIR/" 'index($2,d)==1{print $2}' /etc/fstab)
{
  line="$NAS_DIR"; for n in ${LAN_CIDR//,/ }; do line+=" $n(ro,fsid=0,no_subtree_check)"; done; echo "$line"
  for mp in "${mounts[@]}"; do
    fsid=$(( $(printf '%s' "${mp##*/}" | cksum | cut -d' ' -f1) % 1000000000 + 1 ))   # stable per name; NTFS has no UUID nfs-utils likes
    line="$mp"; for n in ${LAN_CIDR//,/ }; do line+=" $n($NFS_OPTS,fsid=$fsid)"; done; echo "$line"
  done
} | put /etc/exports
apply nfsv4-server

#!/usr/bin/env bash
# DB_ENGINE=postgresql (lean tuning) | sqlite (library only) | none.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${DB_ENGINE:=postgresql}" "${PG_SHARED_BUFFERS:=512MB}" "${PG_CACHE_SIZE:=3GB}"
case $DB_ENGINE in
  sqlite) pkg sqlite; exit 0 ;;
  none)   exit 0 ;;
  postgresql) ;;
  *) die "DB_ENGINE must be postgresql|sqlite|none" ;;
esac
pkg postgresql
pgdir=/var/lib/postgres; pgdata=$pgdir/data
install -d -o postgres -g postgres -m 700 "$pgdir"
if [[ ! -f $pgdata/PG_VERSION ]]; then
  # btrfs: files created under an empty dir with +C skip copy-on-write (PG has its own checksums)
  if [[ $(stat -f -c %T "$pgdir") == btrfs ]]; then chattr +C "$pgdir"; fi
  runuser -u postgres -- bash -c "cd $pgdir && initdb --locale=C.UTF-8 -E UTF8 --data-checksums -D $pgdata"
fi
grep -q 'arch-nas tuning' "$pgdata/postgresql.conf" || cat >> "$pgdata/postgresql.conf" <<EOF

# --- arch-nas tuning ---
listen_addresses = 'localhost'
max_connections = 50
shared_buffers = $PG_SHARED_BUFFERS
effective_cache_size = $PG_CACHE_SIZE
work_mem = 16MB
maintenance_work_mem = 128MB
wal_compression = on
checkpoint_timeout = 15min
max_wal_size = 2GB
random_page_cost = 1.1
EOF
apply postgresql

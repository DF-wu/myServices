# Shared Valkey persistence

The `chatstack-unified-redis` service shares one persistent dataset across several
applications and logical databases. The recipe enables `appendonly yes`,
`appendfsync everysec`, and `save 3600 1`, preserving the existing image, `/data`
bind mount, and other AOF defaults. RDB snapshots become eligible after 3600
seconds with at least one change; this is not an exact hourly schedule. AOF
rewrites still produce storage traffic. No traffic reduction has been measured.

With healthy storage, `everysec` normally risks about one second of recent
writes. That is not a universal loss bound: NFS stalls and storage durability
semantics can extend the window.

## Migration gate: before merge or redeploy

Follow the official [Valkey persistence guide][persistence]. **Do not merely
change the startup flags and restart an RDB-only instance.** Enable AOF on the
running dataset first. The stack polls `master` automatically, so keep the PR
draft and unmerged until the initial conversion and recovery checks below pass.
Git review/push does not authorize these production actions; a separately
authorized operator must coordinate the migration and subsequent rollout.

1. Record the running version, `CONFIG GET appendonly appendfsync save dir
   dbfilename appenddirname appendfilename auto-aof-rewrite-percentage`,
   `INFO persistence`, and `INFO keyspace`. Record key counts and representative
   application records across **all** populated databases. Use the existing
   authenticated access method; keep credentials and private inventory out of
   Git and command history.
2. Verify the existing `/data` mount is healthy and writable by the service UID,
   with enough free storage for the RDB, complete AOF, rewrite temporary files,
   and backups, plus memory headroom for fork/copy-on-write. Do not substitute a
   new volume if the existing NFS mount or permissions fail.
3. Back up the latest successfully completed `dump.rdb` to a timestamped location
   outside the live data directory and outside the storage failure domain.
   Check `rdb_last_bgsave_status:ok`, record its age, verify the copy's checksum,
   and test restoration in isolation. RDB files can be copied while Valkey runs
   because completed snapshots are atomically replaced. Retain the pre-migration
   backup until post-rollout recovery is validated and the agreed retention
   period expires; never overwrite the only good backup.
4. On the **running existing instance**, execute the following operator commands
   using the existing access method (not executed by this recipe change):

   ```sh
   docker exec chatstack-unified-redis valkey-cli CONFIG SET appendfsync everysec
   docker exec chatstack-unified-redis valkey-cli CONFIG SET appendonly yes
   docker exec chatstack-unified-redis valkey-cli INFO persistence
   ```

   Enabling AOF starts the initial background rewrite of the in-memory dataset;
   it may wait for an active RDB save. Before **any restart or recreation**, wait
   for `aof_enabled:1`, `aof_rewrite_in_progress:0`,
   `aof_rewrite_scheduled:0`, `aof_last_bgrewrite_status:ok`, and
   `aof_last_write_status:ok`. Confirm logs show successful initial rewrite
   completion and subsequent application writes reach the incremental AOF.
   A successful `CONFIG SET` reply alone is insufficient. Stop the rollout on
   rewrite/write errors, unhealthy storage, or a rewrite that never completes.
5. Resolve the AOF location from the recorded `dir`, `appenddirname`, and
   `appendfilename`. Verify its manifest and **every referenced base and
   incremental file** exist and are readable; the base may use RDB format. Back
   up the complete AOF directory, including its manifest, without racing a
   rewrite: record `auto-aof-rewrite-percentage`, temporarily set it to `0`,
   prevent manual rewrites, and wait for both rewrite flags to be `0` before
   copying. Restore the recorded percentage afterward, including on failure.
   Check the copied set with `valkey-check-aof` without `--fix` and restore it
   into an isolated same-version instance; verify all databases and sample
   records. Do not treat one `.aof` file as the complete backup.
6. Only after these gates pass, merge and persist the flags through the normal
   Git-backed Portainer flow. The command line in Compose is authoritative;
   this service has no managed `valkey.conf` to update with `CONFIG REWRITE`.
   Runtime `CONFIG SET` changes alone do not survive recreation. Coordinate
   this interval to avoid restarts with the old recipe. Keep the same data
   mount and permissions throughout; do not edit Portainer's Git checkout.

## After rollout

Verify health, startup logs showing AOF loading, and `CONFIG GET appendonly
appendfsync save` returning `yes`, `everysec`, and `3600 1`. Recheck the persistence
status fields above, `rdb_last_bgsave_status`, manifest/files, all database key
counts, and application reads/writes (allow for normal traffic and expirations).
Monitor NFS capacity/latency, AOF write errors, delayed fsyncs, rewrite duration,
and RDB snapshot duration. Maintain verified off-storage backups; the live RDB
and AOF on the same mount are not independent backups.

## Recovery and rollback

If conversion fails, keep the running dataset available and investigate; do not
restart into an incomplete AOF. If restart is unavoidable, preserve all data
files first and use a verified isolated recovery copy and an explicitly approved
recovery point. Never repair the only copy: `valkey-check-aof --fix` may discard
data after corruption.

Reverting the recipe alone disables AOF and may load a stale `dump.rdb`, losing
writes already present in AOF. Prefer retaining AOF while resolving rollout
issues. If returning to RDB-only is required, quiesce **all** writers, complete a
fresh `BGSAVE` successfully with no save in progress, back up and test that RDB,
and keep writers stopped until the approved RDB-only recipe and restart are
complete. Preserve the complete AOF backup for recovery. Restoring an older
backup requires explicit acceptance of its data-loss window across every
consumer; never delete the AOF set merely to force an RDB fallback.

[persistence]: https://valkey.io/topics/persistence/

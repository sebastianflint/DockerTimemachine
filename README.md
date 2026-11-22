# Time Machine in Docker

A small Samba container that macOS sees as a network Time Machine disk.
It uses Samba's `fruit` module for Apple compatibility and Avahi (Bonjour) so the
Mac finds it automatically.

## Quick start

1. Put `Dockerfile`, `entrypoint.sh` and `docker-compose.yml` in one folder.
2. Edit `docker-compose.yml`: at least set `TM_PASSWORD`, and set `PUID`/`PGID`
   to the owner of your backup folder (`id -u` / `id -g` on the host).
3. Start it:

   ```sh
   docker compose up -d --build
   docker compose logs -f
   ```

4. On the Mac: **System Settings → General → Time Machine → Add Backup Disk**.
   The share (`timemachine` by default) should appear. Sign in as
   `timemachine` with your password.

   If it doesn't show up: Finder → **Go → Connect to Server** →
   `smb://<server-ip>/TimeMachine`, then choose it in Time Machine.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `TM_USER` | `timemachine` | SMB login name |
| `TM_PASSWORD` / `TM_PASSWORD_FILE` | — (required) | Password, or path to a file/Docker secret holding it |
| `TM_SHARE_NAME` | `TimeMachine` | Share name |
| `TM_SIZE_LIMIT` | `1T` | Size macOS is allowed to use (`500G`, `2T`, … or `0` for none) |
| `TM_HOSTNAME` | `timemachine` | Name shown in Finder / Time Machine |
| `PUID` / `PGID` | `1000` | Owner of the files on the host |
| `ENABLE_AVAHI` | `1` | Run Bonjour inside the container |

## Notes

- **Filesystem:** the host folder must support extended attributes
  (ext4, XFS, Btrfs and ZFS all do). FAT/exFAT and most network mounts won't work.
- **Networking:** `network_mode: host` is needed for Bonjour discovery. It works on
  Linux hosts (NAS, Raspberry Pi, home server), not in Docker Desktop on a Mac.
  Without host networking, publish port `445:445` and connect manually.
- **Host already runs Avahi** (common on Synology, Ubuntu desktop, etc.):
  set `ENABLE_AVAHI=0`, mount the host's `/etc/avahi/services` to `/export`,
  and the container drops its `timemachine.service` file there for the host's Avahi.
- **Port 445 in use:** if the host already runs Samba, stop it or use a different machine;
  macOS expects SMB on 445.
- **Several Macs:** each Mac creates its own `.sparsebundle` in the same share; the
  size limit is per Mac.

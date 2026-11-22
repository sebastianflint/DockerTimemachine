#!/bin/sh
set -eu

# ---- Password (plain env var or Docker secret file) -------------------------
if [ -n "${TM_PASSWORD_FILE:-}" ] && [ -f "$TM_PASSWORD_FILE" ]; then
  TM_PASSWORD="$(cat "$TM_PASSWORD_FILE")"
fi
if [ -z "${TM_PASSWORD:-}" ]; then
  echo "ERROR: set TM_PASSWORD (or TM_PASSWORD_FILE)." >&2
  exit 1
fi

# ---- User / group matching the owner of the host folder ---------------------
if ! getent group "$PGID" >/dev/null 2>&1; then
  addgroup -g "$PGID" tmgroup
fi
GROUP_NAME="$(getent group "$PGID" | cut -d: -f1)"

if ! id "$TM_USER" >/dev/null 2>&1; then
  adduser -D -H -s /sbin/nologin -u "$PUID" -G "$GROUP_NAME" "$TM_USER"
fi

printf '%s\n%s\n' "$TM_PASSWORD" "$TM_PASSWORD" | smbpasswd -s -a "$TM_USER" >/dev/null
smbpasswd -e "$TM_USER" >/dev/null

mkdir -p /backups
chown "$PUID:$PGID" /backups
chmod 0770 /backups

# ---- Samba config ------------------------------------------------------------
cat > /etc/samba/smb.conf <<EOF
[global]
  server role = standalone server
  workgroup = WORKGROUP
  netbios name = ${TM_HOSTNAME}
  server string = Time Machine
  security = user
  map to guest = never
  server min protocol = SMB2_10
  disable netbios = yes
  smb ports = 445
  multicast dns register = no
  load printers = no
  printing = bsd
  printcap name = /dev/null
  disable spoolss = yes
  log level = 1

  # macOS / Time Machine compatibility
  vfs objects = catia fruit streams_xattr
  fruit:metadata = stream
  fruit:model = MacSamba
  fruit:posix_rename = yes
  fruit:veto_appledouble = no
  fruit:nfs_aces = no
  fruit:wipe_intentionally_left_blank_rfork = yes
  fruit:delete_empty_adfiles = yes

[${TM_SHARE_NAME}]
  path = /backups
  valid users = ${TM_USER}
  read only = no
  browseable = yes
  force user = ${TM_USER}
  create mask = 0660
  directory mask = 0770
  fruit:time machine = yes
EOF

if [ -n "${TM_SIZE_LIMIT:-}" ] && [ "$TM_SIZE_LIMIT" != "0" ]; then
  echo "  fruit:time machine max size = ${TM_SIZE_LIMIT}" >> /etc/samba/smb.conf
fi

testparm -s /etc/samba/smb.conf >/dev/null 2>&1 || { testparm -s /etc/samba/smb.conf; exit 1; }

# ---- Bonjour advertisement (so the Mac finds it automatically) ---------------
write_service_file() {
  cat > "$1" <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">${TM_HOSTNAME}</name>
  <service><type>_smb._tcp</type><port>445</port></service>
  <service><type>_device-info._tcp</type><port>9</port><txt-record>model=TimeCapsule8,119</txt-record></service>
  <service><type>_adisk._tcp</type><port>9</port>
    <txt-record>sys=waMa=0,adVF=0x100</txt-record>
    <txt-record>dk0=adVN=${TM_SHARE_NAME},adVF=0x82</txt-record>
  </service>
</service-group>
EOF
}

mkdir -p /etc/avahi/services
write_service_file /etc/avahi/services/timemachine.service
# Also drop a copy where it can be picked up by an Avahi running on the host
if [ -d /export ]; then
  write_service_file /export/timemachine.service
fi

if [ "${ENABLE_AVAHI}" = "1" ]; then
  sed -i \
    -e "s/^#\?host-name=.*/host-name=${TM_HOSTNAME}/" \
    -e "s/^#\?enable-dbus=.*/enable-dbus=no/" \
    /etc/avahi/avahi-daemon.conf
  rm -f /run/avahi-daemon/pid
  avahi-daemon --daemonize --no-drop-root --no-chroot || echo "WARN: avahi-daemon failed to start; Mac auto-discovery disabled." >&2
fi

echo "Time Machine share '${TM_SHARE_NAME}' ready for user '${TM_USER}' (limit: ${TM_SIZE_LIMIT:-none})."
exec smbd --foreground --debug-stdout --no-process-group

#!/usr/bin/env bash
#
# Read-only netplan / NetworkManager diagnostic. Run with sudo so the
# root-only files under /etc/netplan are readable. Secrets (psk, password,
# key material) are masked before printing.
set -uo pipefail

section() { printf '\n## %s\n' "$1"; }

mask() {
  sed -E 's/((password|psk|passphrase|key|secret)[^:]*:[[:space:]]*).*/\1***MASKED***/I'
}

section "netplan-dir"
ls -la /etc/netplan/ 2>&1

section "netplan-files"
for f in /etc/netplan/*.yaml; do
  [ -e "$f" ] || continue
  printf -- '--- %s (%s bytes)\n' "$f" "$(stat -c %s "$f" 2>/dev/null)"
  head -c 4096 "$f" | mask | cat -A
  printf '\n'
done

section "netplan-generate"
netplan generate 2>&1
printf 'exit=%s\n' "$?"

section "nmcli-connections"
nmcli -f NAME,UUID,TYPE,DEVICE connection show 2>&1

section "nm-netplan-backend"
grep -rIs 'netplan' /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d/ 2>&1 || echo "no netplan reference in NM config"

section "lib-modules"
for d in /lib/modules/*/; do
  name="$(basename "$d")"
  printf '%s modules.dep=%s build=%s\n' "$name" \
    "$([ -e "$d/modules.dep" ] && echo yes || echo no)" \
    "$([ -d "$d/build" ] && echo yes || echo no)"
done

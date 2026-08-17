#!/bin/sh
set -eu

TABLE_NAME="wg_clash_gateway"
MARK="0x1"
ROUTE_TABLE="100"

cleanup() {
  nft delete table inet "${TABLE_NAME}" 2>/dev/null || true
  ip rule del fwmark "${MARK}" lookup "${ROUTE_TABLE}" priority 100 2>/dev/null || true
  ip route flush table "${ROUTE_TABLE}" 2>/dev/null || true
}

trap 'cleanup; exit 0' INT TERM EXIT

until ip link show wg0 >/dev/null 2>&1; do
  sleep 1
done

cleanup

ip route add local 0.0.0.0/0 dev lo table "${ROUTE_TABLE}"
ip rule add fwmark "${MARK}" lookup "${ROUTE_TABLE}" priority 100

# Only decrypted client traffic arriving on wg0 is intercepted. Local destinations
# remain reachable, while every non-TCP/UDP packet is dropped instead of leaking
# through wg-easy's normal masquerade path.
nft -f - <<'EOF'
table inet wg_clash_gateway {
  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;
    iifname "wg0" fib daddr type local return
    iifname "wg0" meta l4proto { tcp, udp } meta mark set 0x1 tproxy to :7893 accept
    iifname "wg0" counter drop
  }

  chain forward_guard {
    type filter hook forward priority -1; policy accept;
    iifname "wg0" counter drop
  }
}
EOF

while :; do
  sleep 3600 &
  wait $!
done

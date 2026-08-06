#!/bin/sh
set -eu

response_file=$(mktemp /tmp/gost-health.XXXXXX)
trap 'rm -f "$response_file"' EXIT HUP INT TERM

# Complete a no-auth greeting and CONNECT to Gluetun's loopback health server.
# The first four response bytes must be greeting 05 00 and CONNECT success 05 00.
{
  printf '\005\001\000\005\001\000\001\177\000\000\001\047\017'
  printf 'GET / HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'
} | nc -w 2 127.0.0.1 1080 >"$response_file"

response_prefix=$(dd if="$response_file" bs=1 count=4 2>/dev/null |
  od -An -tx1 | tr -d ' \n')
[ "$response_prefix" = 05000500 ]
[ -d /sys/class/net/tun0 ]

#!/usr/bin/env python3
"""Verify SearXNG egress; --exercise-kill-switch briefly stops only its VPN."""
import argparse
import json
import subprocess
from pathlib import Path


PROBE = r'''
import concurrent.futures, ipaddress, json, secrets, socket, struct, sys, time
import urllib.parse, urllib.request
payload = json.load(sys.stdin)
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def control(method, body=None, path='/v1/vpn/status'):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request('http://127.0.0.1:8000' + path, data=data,
        method=method, headers={'X-API-Key': payload['key'], 'Content-Type': 'application/json'})
    with opener.open(request, timeout=10) as response:
        return json.load(response)

def trace():
    with opener.open('https://www.cloudflare.com/cdn-cgi/trace', timeout=12) as response:
        return dict(line.split('=', 1) for line in response.read().decode().splitlines() if '=' in line)

def dns(address):
    labels = ('sxng-' + secrets.token_hex(6) + '.example.com').split('.')
    question = b''.join(bytes([len(label)]) + label.encode() for label in labels) + b'\0'
    packet = struct.pack('!6H', 12345, 0x0100, 1, 0, 0, 0) + question + struct.pack('!2H', 1, 1)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as connection:
        connection.settimeout(4)
        connection.sendto(packet, (address, 53))
        result, _ = connection.recvfrom(4096)
        assert result[:2] == packet[:2], 'Unexpected DNS response'
        return result[3] & 0x0f

def tcp():
    with socket.create_connection(('1.1.1.1', 443), timeout=4):
        pass

baseline = trace()
assert ipaddress.ip_address(baseline['ip']).is_global
assert baseline.get('loc') == payload['country'], baseline.get('loc')
dns('127.0.0.1')
print(json.dumps({'check':'VPN baseline', 'country':baseline['loc'], 'https':True,
                  'resolver':'127.0.0.1', 'dns':True}), flush=True)
if not payload['exercise']:
    sys.exit(0)

def must_block(name, action):
    try:
        action()
    except (OSError, urllib.error.URLError):
        return {'check':name, 'blocked':True}
    raise AssertionError(name + ' succeeded while VPN was stopped')

try:
    control('PUT', {'status':'stopped'})
    for _ in range(40):
        if control('GET').get('status') == 'stopped':
            break
        time.sleep(0.25)
    else:
        raise AssertionError('VPN did not enter stopped state')
    tasks = [('new public TCP connection', tcp),
             ('direct public DNS', lambda: dns('1.1.1.1')),
             ('external HTTPS request', trace)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(lambda task: must_block(*task), tasks):
            print(json.dumps(result), flush=True)
    # A local resolver can return SERVFAIL or cached negative data while offline.
    # Receiving that local reply does not mean any DNS packet escaped the VPN.
    try:
        rcode = dns('127.0.0.1')
        print(json.dumps({'check':'offline local DNS reply', 'rcode':rcode,
                          'public_dns_already_verified_blocked':True}), flush=True)
    except OSError:
        print(json.dumps({'check':'offline local DNS reply', 'blocked':True}), flush=True)
    try:
        with socket.socket(socket.AF_INET6, socket.SOCK_STREAM) as connection:
            connection.settimeout(3)
            connection.connect(('2606:4700:4700::1111', 443))
    except OSError:
        print(json.dumps({'check':'IPv6 public connection', 'blocked':True}), flush=True)
    else:
        raise AssertionError('IPv6 connection succeeded')
    params = urllib.parse.urlencode({'q':'SearXNG WireGuard ' + secrets.token_hex(4),
                                     'format':'json', 'engines':'brave,duckduckgo'})
    with opener.open('http://127.0.0.1:8080/search?' + params, timeout=25) as response:
        result = json.load(response)
    assert not result.get('results'), 'Search returned remote results with VPN stopped'
    assert result.get('unresponsive_engines'), 'Missing upstream failure evidence'
    print(json.dumps({'check':'remote search while VPN stopped', 'results':0,
                      'upstream_errors':len(result['unresponsive_engines'])}), flush=True)
finally:
    control('PUT', {'status':'running'})
    recovered = False
    for _ in range(12):
        try:
            current = trace()
            if current.get('loc') == payload['country']:
                recovered = True
                break
        except OSError:
            pass
        time.sleep(1)
    assert recovered, 'VPN recovery not confirmed; inspect searxng-vpn immediately'
    print(json.dumps({'check':'VPN restored', 'country':current['loc'], 'https':True}), flush=True)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exercise-kill-switch", action="store_true")
    parser.add_argument("--country", default="JP")
    parser.add_argument("--appdata", type=Path, default=Path("/mnt/appdata/ChatStack/searxng"))
    args = parser.parse_args()
    payload = {"key": (args.appdata / "control-api.key").read_text().strip(),
               "exercise": args.exercise_kill_switch, "country": args.country}
    # A secret is supplied over stdin, never in process arguments or output.
    result = subprocess.run(["rtk", "proxy", "docker", "exec", "-i", "searxng",
        "/usr/local/searxng/.venv/bin/python", "-c", PROBE],
        input=json.dumps(payload), text=True)
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()

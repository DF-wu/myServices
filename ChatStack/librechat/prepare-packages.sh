#!/bin/bash
# Runs in the pinned official baked-runner image, only during Portainer deployment.
# Read its ext4 image as data; do not mount it, boot a VM, or execute guest code.
set -euo pipefail
revision=2fa9f0d43e8e38b7d6240bc76e2483c6a47c64c7
marker=/runtime/.recipe-revision
if [ -f "$marker" ]; then
    [ "$(cat "$marker")" = "$revision" ] || { echo 'Runtime volume revision mismatch' >&2; exit 1; }
    for runtime in python/3.14.4 node/24.22.1 bun/1.4.4 bash/5.2.0; do
        test -f "/runtime/$runtime/.package-installed"
    done
    echo 'Pinned offline language packages already prepared.'
    exit 0
fi
test -s /sandbox-rootfs.img
# Fedora's launcher image does not include debugfs. Install the reader in this
# disposable provisioner, never in the sandbox or on the Docker host.
dnf -y --setopt=install_weak_deps=False install e2fsprogs
stage=/runtime/.extract
rm -rf "$stage"
mkdir -p "$stage"
debugfs -R "rdump /pkgs $stage" /sandbox-rootfs.img
for runtime in python/3.14.4 node/24.22.1 bun/1.4.4 bash/5.2.0; do
    test -f "$stage/pkgs/$runtime/.package-installed"
done
cp -a "$stage/pkgs/." /runtime/
rm -rf "$stage"
chmod -R a+rX /runtime
printf '%s\n' "$revision" > "$marker"
echo 'Official Python, Node.js, Bun/TypeScript and Bash offline packages prepared.'

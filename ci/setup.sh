#!/usr/bin/env bash
set -euo pipefail
version=0.14.1
case "$(uname -m)" in x86_64) arch=x86_64 ;; aarch64) arch=aarch64 ;; *) exit 1 ;; esac
mkdir -p "$HOME/.local/opt"
curl -fsSL "https://ziglang.org/download/$version/zig-$arch-linux-$version.tar.xz" -o /tmp/licensebox-zig.tar.xz
tar -xJf /tmp/licensebox-zig.tar.xz -C "$HOME/.local/opt"
echo "$HOME/.local/opt/zig-$arch-linux-$version" >> "$GITHUB_PATH"

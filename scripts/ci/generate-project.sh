#!/usr/bin/env bash
# Installs XcodeGen (if missing) and generates Familoq.xcodeproj from project.yml.
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen via Homebrew…"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install xcodegen
fi

xcodegen --version
xcodegen generate --spec project.yml

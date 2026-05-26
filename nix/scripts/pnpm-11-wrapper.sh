#!/bin/sh
set -eu

case "$0" in
  */pnpm | pnpm)
    if [ "${1:-}" = "config" ] && [ "${2:-}" = "set" ] && [ "${3:-}" = "manage-package-manager-versions" ]; then
      exit 0
    fi
    ;;
esac

export PNPM_CONFIG_PM_ON_FAIL="${PNPM_CONFIG_PM_ON_FAIL:-ignore}"

exec @node@ @entrypoint@ "$@"

#!/usr/bin/env bash
set -Eeuo pipefail

# Applies the Twitter name and the icon pack to an already built IPA.

is_tty=0
if [[ -t 1 ]]; then is_tty=1; fi
bold='' green='' reset=''
if [[ "$is_tty" -eq 1 ]]; then
  if command -v tput >/dev/null 2>&1; then
    bold="$(tput bold || true)"
    green="$(tput setaf 2 || true)"
    reset="$(tput sgr0 || true)"
  else
    bold='\033[1m'; green='\033[32m'; reset='\033[0m'
  fi
fi

say() { if [[ -n "${bold}${green}${reset}" ]]; then printf "%b%s%b\n" "${bold}${green}" "$1" "${reset}"; else printf "%s\n" "$1"; fi; }
err() { printf "Error: %s\n" "$1" >&2; }
die() { err "$1"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [-t | --twitter-branding] [--resource-pack ZIP] IPA

Branding (at least one required):
  -t, --twitter-branding  Sets the app's display name to Twitter
  --resource-pack ZIP     Apply an icon pack ZIP

Options:
  -h, --help              Show this help
EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"; }

require_cmd python3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TWITTER_BRANDING=0
RESOURCE_PACK=""
IPA=""

set_ipa() {
  if [[ -n "$IPA" ]]; then die "Multiple IPA paths provided."; fi
  IPA="$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--twitter-branding)
      TWITTER_BRANDING=1; shift
      ;;
    --resource-pack)
      [[ $# -ge 2 ]] || die "--resource-pack requires a path argument."
      RESOURCE_PACK="$2"; shift 2
      ;;
    -h|--help)
      usage; exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      set_ipa "$1"; shift
      ;;
  esac
done

if [[ -z "$IPA" || ( "$TWITTER_BRANDING" -eq 0 && -z "$RESOURCE_PACK" ) ]]; then
  usage
  exit 2
fi

if [[ ! -f "$IPA" ]]; then
  die "IPA not found: $IPA"
fi

if [[ -n "$RESOURCE_PACK" && ! -f "$RESOURCE_PACK" ]]; then
  die "--resource-pack file not found: $RESOURCE_PACK"
fi

say "Rebranding $(basename "$IPA")."
TWITTER_BRANDING="$TWITTER_BRANDING" RESOURCE_PACK="$RESOURCE_PACK" \
  python3 "$SCRIPT_DIR/branding/ipa_branding.py" "$IPA"
say "$(basename "$IPA") rebranded."

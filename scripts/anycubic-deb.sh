#!/usr/bin/env bash
# Find, download and inspect the Anycubic Slicer Next .deb in Anycubic's APT
# repository. Used by the release workflow and by the HOWTOs.
#
#   scripts/anycubic-deb.sh latest              describe the current deb as KEY=value lines
#   scripts/anycubic-deb.sh download <file>     download the current deb to <file>, checking its SHA256
#   scripts/anycubic-deb.sh app-version <deb>   print the real app version inside a deb
#
# The deb's own Version field is a different scheme from the app version
# (deb 2.0.06 holds app 2.0.0.5), and the filename is not predictable from
# either, so both have to be read rather than guessed.
set -euo pipefail

REPO_URL=https://cdn-universe-slicer.anycubic.com/prod
PACKAGES_URL=$REPO_URL/dists/noble/main/binary-amd64/Packages

die() { echo "anycubic-deb: $*" >&2; exit 1; }

# Prints DEB_URL, DEB_SHA256, DEB_SIZE and DEB_VERSION.
#
# Exactly one anycubicslicernext entry is expected: with several there is no
# telling which one Anycubic means, and picking one could publish a downgrade.
# Every field is checked against a strict pattern, because the repository is
# unsigned and these values end up in shell commands and workflow outputs.
#
# Exits 75 (EX_TEMPFAIL) when Anycubic's server is down or timing out, so the
# hourly check can tell a passing outage from a repository that moved (any
# other HTTP error) or a Packages file it no longer understands.
latest() {
  local code rc=0
  # Global, not local: the EXIT trap runs after this function has returned.
  packages=$(mktemp)
  trap 'rm -f "$packages"' EXIT
  code=$(curl -fsS --retry 3 --retry-all-errors -o "$packages" -w '%{http_code}' "$PACKAGES_URL") || rc=$?
  if (( rc != 0 )); then
    case $code in
      000 | 408 | 429 | 5??)
        echo "anycubic-deb: $PACKAGES_URL is unreachable (HTTP $code, curl exit $rc)" >&2
        exit 75 ;;
      *)
        die "fetching $PACKAGES_URL failed with HTTP $code" ;;
    esac
  fi

  tr -d '\r' < "$packages" | awk -v repo="$REPO_URL" '
    function flush() {
      if (pkg == "anycubicslicernext") {
        n++
        f = file; s = sha; sz = size; v = ver
      }
      pkg = file = sha = size = ver = ""
    }
    /^Package: /  { pkg = $2 }
    /^Version: /  { ver = $2 }
    /^Filename: / { file = $2 }
    /^SHA256: /   { sha = $2 }
    /^Size: /     { size = $2 }
    /^$/          { flush() }
    END {
      flush()
      if (n != 1) {
        printf "expected 1 anycubicslicernext entry in Packages, found %d\n", n > "/dev/stderr"
        exit 1
      }
      if (f !~ /^[A-Za-z0-9][A-Za-z0-9._+\/-]*\.deb$/ || f ~ /\.\./ ||
          s !~ /^[0-9a-f]+$/ || length(s) != 64 ||
          sz !~ /^[0-9]+$/ || v !~ /^[A-Za-z0-9.+~-]+$/) {
        print "unexpected Packages entry: Filename=" f " SHA256=" s " Size=" sz " Version=" v > "/dev/stderr"
        exit 1
      }
      printf "DEB_URL=%s/%s\nDEB_SHA256=%s\nDEB_SIZE=%s\nDEB_VERSION=%s\n", repo, f, s, sz, v
    }'
}

download() {
  local dest=$1 info key value url='' sha=''
  info=$(latest) || exit 1
  while IFS='=' read -r key value; do
    case $key in
      DEB_URL) url=$value ;;
      DEB_SHA256) sha=$value ;;
    esac
  done <<< "$info"

  echo "Downloading $url" >&2
  curl -fL --retry 3 --retry-all-errors -o "$dest.part" "$url" || die "download failed"
  echo "$sha  $dest.part" | sha256sum -c --quiet - || die "SHA256 mismatch for $url"
  mv "$dest.part" "$dest"
  printf '%s\n' "$info"
}

app_version() {
  local deb version
  deb=$(realpath "$1")
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  # The member may be stored as ./usr/... or usr/...; both land in $work/usr.
  (cd "$work" && ar x "$deb" &&
     tar xf data.tar.* --wildcards --no-anchored 'usr/share/AnycubicSlicerNext/resources/build-version.txt') ||
    die "no resources/build-version.txt in $1"
  version=$(tr -d '[:space:]' < "$work/usr/share/AnycubicSlicerNext/resources/build-version.txt")
  [[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "unexpected app version '$version' in $1"
  echo "$version"
}

case ${1:-} in
  latest)      latest ;;
  download)    [[ $# -eq 2 ]] || die "usage: $0 download <file>"; download "$2" ;;
  app-version) [[ $# -eq 2 ]] || die "usage: $0 app-version <deb>"; app_version "$2" ;;
  *)           die "usage: $0 latest | download <file> | app-version <deb>" ;;
esac

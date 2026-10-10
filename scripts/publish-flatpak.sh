#!/usr/bin/env bash
# Add a freshly built Flatpak to the published repository, and write next to
# it everything a client needs to add that repository as a remote. Used by
# the release workflow; kept out of it so it can be run and tested locally.
#
#   scripts/publish-flatpak.sh <built-repo> <site-dir> <bundle-file>
#
# <built-repo>   the OSTree repo flatpak-builder exported to (--repo=...)
# <site-dir>     the previously published site, updated in place; empty or
#                missing on the very first run
# <bundle-file>  where to write the single-file bundle for the GitHub release
#
# Environment:
#   SITE_URL     where <site-dir> is served from, without a trailing slash
#   GPG_KEY_ID   key to sign the commits and the summary with
#   GNUPGHOME    keyring that holds it
#
# Afterwards <site-dir> contains:
#   repo/                                      the OSTree repository
#   anycubic-slicer-next.flatpakrepo           for `flatpak remote-add --from`
#   com.anycubic.AnycubicSlicer.flatpakref     for `flatpak install --from`
#   icon.svg, .nojekyll
set -euo pipefail

APP_ID=com.anycubic.AnycubicSlicer
BRANCH=stable
REMOTE_NAME=anycubic-slicer-next
TITLE="Anycubic Slicer Next"
HOMEPAGE=https://github.com/develonrails/anycubic-slicer-next
FLATHUB=https://dl.flathub.org/repo/flathub.flatpakrepo

# Commits kept behind the current one. GitHub Pages stops at 1 GB per site and
# one version of the app is ~150 MB in the repo plus as much again in static
# deltas, so this cannot keep the long history a small app could. One parent
# is enough for an update delta, and it keeps the previous commit's objects
# around while Pages' CDN may still serve the old summary (cached for up to
# ten minutes).
KEEP_PARENTS=1

# Pages publishes from git, which refuses files over 100 MB, and the site as a
# whole may not exceed 1 GB.
MAX_FILE=95M
MAX_SITE_MB=950

[[ $# -eq 3 ]] || { echo "usage: $0 <built-repo> <site-dir> <bundle-file>" >&2; exit 1; }
: "${SITE_URL:?}" "${GPG_KEY_ID:?}" "${GNUPGHOME:?}"

built=$1
site=$2
bundle=$3
repo=$site/repo
sign=(--gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GNUPGHOME")

mkdir -p "$site"
if [[ ! -f $repo/config ]]; then
  echo "No published repository yet, starting one."
  ostree init --repo="$repo" --mode=archive
fi

# git does not store empty directories, and an OSTree repository keeps several.
# They exist after ostree init, but not once the repository has come back
# through a clone of gh-pages, and build-update-repo then stops with
# "opendir(refs/remotes): No such file or directory".
mkdir -p "$repo"/refs/{heads,mirrors,remotes} "$repo"/{state,extensions,tmp/cache}

# Only the app and, if flatpak-builder made one, its translations. Not the
# appstream branches, which build-update-repo generates here, and nothing else
# a build that ran someone else's binary might have left in its repository.
app_ref=app/$APP_ID/x86_64/$BRANCH
locale_ref=runtime/$APP_ID.Locale/x86_64/$BRANCH
ostree --repo="$built" rev-parse "$app_ref" >/dev/null ||
  { echo "$built has no $app_ref" >&2; exit 1; }
refs=("$app_ref")
if ostree --repo="$built" rev-parse "$locale_ref" >/dev/null 2>&1; then
  refs+=("$locale_ref")
fi

# Clients refuse an update whose commit is older than the one they have
# ("Update is older than current version"), and build-commit-from keeps the
# build's own timestamp. Re-running an old workflow run after a newer one has
# published would otherwise leave every client stuck.
commit_time() { date -d "$(ostree --repo="$1" show "$2" | sed -n 's/^Date: *//p')" +%s; }
if ostree --repo="$repo" rev-parse "$app_ref" >/dev/null 2>&1 &&
   (( $(commit_time "$built" "$app_ref") < $(commit_time "$repo" "$app_ref") )); then
  echo "This build is older than the one already published; not publishing it." >&2
  exit 1
fi

# build-commit-from rather than a pull: it commits the build on top of what is
# published, with the previous release as its parent. A pull would move the ref
# to a commit with nothing behind it, and an installed client would have no
# path from where it is to where that is. --untrusted copies and checksums every
# object instead of trusting the build's repository.
flatpak build-commit-from --src-repo="$built" --untrusted "${sign[@]}" --no-update-summary \
  "$repo" "${refs[@]}"

flatpak build-update-repo "$repo" "${sign[@]}" \
  --title="$TITLE" --default-branch="$BRANCH" \
  --generate-static-deltas \
  --prune --prune-depth="$KEEP_PARENTS"

# The public key is inlined in both files, so adding the remote and trusting it
# are one step rather than two.
gpg --homedir "$GNUPGHOME" --export "$GPG_KEY_ID" > "$site/public.gpg"
key=$(base64 -w0 < "$site/public.gpg")

cat > "$site/$REMOTE_NAME.flatpakrepo" <<EOF
[Flatpak Repo]
Title=$TITLE
Url=$SITE_URL/repo/
Homepage=$HOMEPAGE
Comment=Unofficial Flatpak of Anycubic Slicer Next
Description=Anycubic Slicer Next, repackaged from Anycubic's .deb and updated whenever Anycubic publishes a new version.
Icon=$SITE_URL/icon.svg
DefaultBranch=$BRANCH
GPGKey=$key
EOF

# RuntimeRepo lets a one-step install also fetch the GNOME runtime from Flathub
# on systems that have not added Flathub yet.
cat > "$site/$APP_ID.flatpakref" <<EOF
[Flatpak Ref]
Name=$APP_ID
Branch=$BRANCH
Title=$TITLE
Url=$SITE_URL/repo/
SuggestRemoteName=$REMOTE_NAME
Homepage=$HOMEPAGE
Icon=$SITE_URL/icon.svg
RuntimeRepo=$FLATHUB
IsRuntime=false
GPGKey=$key
EOF

ostree --repo="$repo" cat "$app_ref" "/export/share/icons/hicolor/scalable/apps/$APP_ID.svg" > "$site/icon.svg"

# Without this, Pages puts the whole repository through Jekyll, which is slow
# and drops the files it decides look like templates.
touch "$site/.nojekyll"

# The bundle carries the repository's URL and key: installing it sets up a
# remote, so people who prefer a single download still get updates.
flatpak build-bundle "$repo" "$bundle" "$APP_ID" "$BRANCH" \
  --repo-url="$SITE_URL/repo/" --runtime-repo="$FLATHUB" --gpg-keys="$site/public.gpg"

# Fail here rather than on a push that git or Pages would reject.
too_big=$(find "$site" -path "$site/.git" -prune -o -type f -size +"$MAX_FILE" -print)
[[ -z $too_big ]] || { echo "Files too large for git: $too_big" >&2; exit 1; }
links=$(find "$site" -path "$site/.git" -prune -o -type l -print)
[[ -z $links ]] || { echo "Pages cannot publish symlinks: $links" >&2; exit 1; }
size_mb=$(du -sm --exclude=.git "$site" | cut -f1)
echo "Published site: ${size_mb} MB"
(( size_mb <= MAX_SITE_MB )) || { echo "Site exceeds ${MAX_SITE_MB} MB; GitHub Pages stops at 1 GB" >&2; exit 1; }

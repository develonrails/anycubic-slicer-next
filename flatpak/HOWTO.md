# How to Build AnycubicSlicer Flatpak

This guide explains how to create a Flatpak package of AnycubicSlicer from the Ubuntu 24.04 .deb package, and how releases are published.

Releases are built and published automatically by `.github/workflows/release.yml` whenever Anycubic publishes a new .deb (see [Publishing](#publishing)). Building by hand is only needed to test a change.

## System Requirements (For Running)

The Flatpak uses the GNOME 51 runtime which provides all necessary libraries (WebKit2GTK, GTK3, GStreamer, glibc, etc.) inside the sandbox. It requires:
- Flatpak installed on the system
- GNOME Platform 51 runtime (installed automatically from Flathub)
- A Linux kernel 5.10+ (for Flatpak sandboxing)
- Working GPU drivers (handled via Flatpak GL extensions)

The host's glibc version does **not** matter — the runtime bundles its own. This means it works on older distros like Linux Mint 21 (Ubuntu 22.04, glibc 2.35) and Debian 12.

## Prerequisites (For Building)

- Linux system with Flatpak installed
- `flatpak-builder` 1.4+ (or the `org.flatpak.Builder` Flatpak)
- GNOME 51 runtime and SDK
- `curl` and `sha256sum` (to download the .deb)
- Internet connection

## Installation of Build Tools

```bash
# Install Flatpak and flatpak-builder
# On Fedora:
sudo dnf install flatpak flatpak-builder

# On Ubuntu/Debian:
sudo apt install flatpak flatpak-builder

# Add Flathub repository
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install GNOME 51 runtime and SDK
flatpak install flathub org.gnome.Platform//51 org.gnome.Sdk//51
```

## Files Overview

- `com.anycubic.AnycubicSlicer.yml` - Flatpak manifest (build recipe)
- `com.anycubic.AnycubicSlicer.metainfo.xml` - AppStream metadata: what software centers show
- `anycubicslicernext.deb` - Source .deb package (downloaded, not in git)
- `../build/`, `../repo/` - Build directory and local Flatpak repository, created in the repository root by the commands below
- `../scripts/anycubic-deb.sh` - Finds and downloads the current .deb from Anycubic's APT repository
- `../scripts/publish-flatpak.sh` - Adds a build to the published repository (used by the release workflow)
- `../scripts/smoke-test.sh` - Starts the app on a virtual display to check it comes up

## Checking for New Versions

Anycubic publishes .deb packages to their APT repository. The deb package version does **NOT** match the actual app version (e.g. deb version `2.0.06` contains app version `2.0.0.5`).

```bash
scripts/anycubic-deb.sh latest                                    # what Anycubic publishes now
scripts/anycubic-deb.sh app-version flatpak/anycubicslicernext.deb  # the real app version inside a deb
```

See [appimage/HOWTO.md](../appimage/HOWTO.md#checking-for-new-versions) for details.

## Build Process

All commands run from the repository root, with the GNOME 51 SDK from [Installation of Build Tools](#installation-of-build-tools) installed.

### Step 1: Download the .deb

```bash
scripts/anycubic-deb.sh download flatpak/anycubicslicernext.deb
```

The .deb **must** be named `anycubicslicernext.deb` and sit next to the manifest — that is the
name the manifest refers to. The name is deliberately version-free, so the manifest does not
need editing when a new release comes out.

### Step 2: Build the Flatpak

```bash
# Build (creates build/ and repo/ directories)
flatpak-builder --repo=repo --force-clean build flatpak/com.anycubic.AnycubicSlicer.yml
```

### Step 3: Test the Flatpak

```bash
# Quick test without installing
flatpak-builder --run build flatpak/com.anycubic.AnycubicSlicer.yml anycubic-slicer-wrapper
```

You should see `add font of ... returns 1` for each bundled font. To test it installed, make a bundle and install that (uninstall a published version first: both are the same app on the same branch):

```bash
flatpak build-bundle repo AnycubicSlicer-test.flatpak com.anycubic.AnycubicSlicer stable \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user AnycubicSlicer-test.flatpak
flatpak run com.anycubic.AnycubicSlicer
```

## Publishing

`.github/workflows/release.yml` publishes every release. It runs every hour, on every push to `main` that touches the packaging, and by hand (`gh workflow run release.yml`, optionally with `-f force=true`).

1. **check** reads Anycubic's `Packages` file and compares the deb's SHA256, and a hash of the packaging files, with `latest.env` on the `gh-pages` branch. It only goes on when either changed or the run was forced. Because it compares against what was published rather than looking at what triggered the run, a push that was cancelled in the queue or came during an outage at Anycubic is still published by the next hourly run.
2. **flatpak** builds the manifest in the `ghcr.io/flathub-infra/flatpak-github-actions:gnome-51` container, installs the result and starts it on a virtual display (`scripts/smoke-test.sh`).
3. **appimage** builds and smoke-tests the AppImage on Ubuntu 24.04 (see [appimage/HOWTO.md](../appimage/HOWTO.md)).
4. **publish** commits the Flatpak on top of the published OSTree repository, signs it, and force-pushes the result to `gh-pages` as a single orphan commit (`scripts/publish-flatpak.sh`). Then it creates the GitHub release for the app version, or replaces its files when the version already has one.

Nothing is published unless both builds and both smoke tests pass.

The `gh-pages` branch, served at https://develonrails.github.io/anycubic-slicer-next, holds:

- `repo/` - the signed OSTree repository with branch `stable`
- `anycubic-slicer-next.flatpakrepo` - for `flatpak remote-add --from`
- `com.anycubic.AnycubicSlicer.flatpakref` - for a one-step `flatpak install --from`
- `latest.env` - which deb was published last; the hourly check compares against it
- `icon.svg`, `public.gpg`, `.nojekyll`

The release bundle (`AnycubicSlicer-<version>.flatpak`) is built from the published repository with `--repo-url` and the public key, so installing it sets up a remote for updates as well.

**Size:** GitHub Pages stops at 1 GB per site, and one version of the app is ~150 MB in the repository plus static deltas. `publish-flatpak.sh` therefore keeps only the current commit and its parent (`--prune-depth=1`). That is ~180 MB after the first publish or a packaging-only rebuild, and ~290 MB once a version change has been published, which is the usual state because the previous version stays until the next publish. The script refuses to publish over 950 MB or with any file git would reject (100 MB).

**Bandwidth:** Pages also has a soft limit of 100 GB of traffic a month. A client updating to a new version pulls roughly 75-90 MB, a fresh install from the remote roughly 150 MB (bundle downloads come from GitHub Releases and do not count). That leaves room for several hundred active installs per release. GitHub does not show Pages traffic, so watch the release download counts as a proxy; if GitHub gets in touch or usage clearly grows, move `repo/` (or a CDN in front of it) to a host without that limit.

### One-time setup

1. **Create the signing key** and store it as a repository secret:

   ```bash
   export GNUPGHOME=$(mktemp -d) && chmod 700 "$GNUPGHOME"

   gpg --batch --gen-key <<KEY
   %no-protection
   Key-Type: eddsa
   Key-Curve: Ed25519
   Key-Usage: sign
   Name-Real: anycubic-slicer-next repository signing
   Name-Email: anycubic-slicer-next@develonrails.github.io
   Expire-Date: 0
   %commit
   KEY

   gpg --export-secret-keys --armor | base64 -w0 |
       gh secret set FLATPAK_GPG_PRIVATE_KEY --repo develonrails/anycubic-slicer-next
   ```

   Nothing publishes without it — the publish job stops if it is unset.

2. **Run the workflow once** (`gh workflow run release.yml -f force=true`). It creates the `gh-pages` branch.

3. **Turn on GitHub Pages** for that branch: Settings → Pages → Deploy from a branch → `gh-pages`, `/ (root)`. Or:

   ```bash
   gh api -X POST repos/develonrails/anycubic-slicer-next/pages \
     -f 'source[branch]=gh-pages' -f 'source[path]=/'
   ```

### Maintenance

- **Rolling the key** re-signs everything on the next run, but a client that already trusts the old key will refuse the new signatures. Users would have to remove and re-add the remote, and bundle installs would have to reinstall. Avoid it.
- **When a build fails,** the hourly check skips that combination of deb and packaging from then on instead of failing (and emailing) every hour. A new deb or a push that changes the packaging tries again automatically; otherwise run `gh workflow run release.yml -f force=true` once the cause is fixed.
- **The hourly schedule pauses** after 60 days without activity in the repository; GitHub disables scheduled workflows in public repositories then. It emails a warning first. Turn it back on under Actions, or with `gh workflow enable release.yml`. Do not automate this: GitHub considers keepalive workarounds a violation of its terms.
- **Right after a release** GitHub Pages may serve the old repository summary for up to ten minutes (its CDN caches files that long). `flatpak update` sees the new version a little later, and in rare cases fails with a signature error during that window; trying again later fixes it.

## Understanding the Manifest

### Runtime Selection

We use **GNOME Platform 51** because:
- It includes WebKit2GTK 4.1 and libsoup 3 (required by AnycubicSlicer's UI)
- It includes GTK-3 and all necessary libraries
- Its pango (1.58) does not have the font crash of pango before 1.57.1 (issue #4)
- It is supported for about a year, until the GNOME release after next; 48 is end-of-life since March 2026
- The freedesktop runtime does NOT include WebKit

Check whether a runtime is end-of-life with `flatpak remote-info --system flathub org.gnome.Platform//51` (use `--user` if your Flathub remote is per-user). To move to a newer runtime, change `runtime-version` here **and** the `gnome-51` container tag in `.github/workflows/release.yml`, and check that `/usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0` still exists in the new runtime.

### Branch

The manifest builds branch `stable` for every version. The Flatpak remote only updates an installed app within its own branch, so a branch per version (as the bundles up to 1.3.9.4 had) would leave everyone on the version they first installed.

### Permissions (finish-args)

| Permission | Purpose |
|---|---|
| `--share=ipc` | X11 shared memory (required for display) |
| `--socket=x11` | X11 display access (the binary forces `GDK_BACKEND=x11`, so it runs through XWayland on Wayland) |
| `--socket=pulseaudio` | Audio for notifications |
| `--share=network` | Printer connectivity and cloud features |
| `--device=all` | GPU (3D rendering), camera (printer monitoring) |
| `--filesystem=home` | Loading/saving 3D models |
| `--filesystem=xdg-run/gvfs` | GNOME Virtual File System support |
| `--filesystem=/run/media` | USB drives, SD cards |
| `--filesystem=/media` | Removable media |

### Wrapper Script

The wrapper script is modeled after OrcaSlicer's entrypoint:

```bash
#!/usr/bin/env sh
# Only disable DMABUF for NVIDIA (fixes white screen on NVIDIA GPUs)
grep -q org.freedesktop.Platform.GL.nvidia /.flatpak-info && export WEBKIT_DISABLE_DMABUF_RENDERER=1
# UTF-8 locale to prevent segfaults
export LC_ALL=C.UTF-8
# Find bundled application libraries
export LD_LIBRARY_PATH="/app/lib:$LD_LIBRARY_PATH"
cd /app || exit 1
exec /app/bin/AnycubicSlicerNext "$@"
```

**Key design decisions:**
- DMABUF is only disabled for NVIDIA (unconditionally disabling it can cause issues on other GPUs)
- `LC_ALL=C.UTF-8` instead of `LC_ALL=C` (preserves UTF-8 support)
- `cd /app` is needed for resource path resolution (fonts, profiles, etc.)
- No contradictory compositing mode flags (the old build had both FORCE and DISABLE which caused issues)

### Fonts

The app loads its bundled fonts itself with `wxFont::AddPrivateFont()`. With pango before 1.57.1 (e.g. 1.56.4 in GNOME 48) that alone crashes in `libpangoft2` whenever NanumGothic is needed (issue #4). The manifest therefore also copies the fonts to `/app/share/fonts`, where the runtime's fontconfig finds them. GNOME 51's pango has the fix as well; the copy stays as a safety net.

### MetaInfo

`com.anycubic.AnycubicSlicer.metainfo.xml` is what GNOME Software, KDE Discover and `flatpak search` show. Its release entry is filled in at build time from the deb's `build-version.txt` and `build-timestamp.txt`, so it never needs editing for a new version. Software centers need an icon of 64, 128, 256 px or scalable; the deb's 192 px icon alone fails `appstreamcli compose`, which is why the SVG is installed too.

### No debug info

`no-debuginfo: true`: the binary is prebuilt and stripped, so there is nothing to split off. Without it flatpak-builder would still publish an empty `.Debug` extension, which GNOME Software trips over when installing a bundle.

## Version History

| App Version | Deb Version | Runtime | Date |
|---|---|---|---|
| 2.0.0.5 | 2.0.06 | GNOME 51 | 2026-09-13 |
| 1.3.9.4 | (unknown) | GNOME 49 (first upload: 48, replaced 2026-04-22) | 2026-03-19 |
| 1.3.9.3 | 1.3.96 | GNOME 48 | 2026-01-31 |
| 1.3.7.3 | 1.3.7171 | (unknown) | 2025-09-28 |

## Updating to a New Version

Nothing: the release workflow notices a new .deb within the hour and publishes it. Nothing in the manifest is tied to a version — the branch is constant, the deb filename is unversioned, and the MetaInfo release is stamped at build time.

To try a new .deb by hand first, follow the [Build Process](#build-process).

## Troubleshooting

### White/blank screen
- This is typically a WebKit DMABUF rendering issue
- The wrapper script conditionally disables DMABUF for NVIDIA GPUs
- If you still see a white screen on non-NVIDIA GPUs, try adding `WEBKIT_DISABLE_DMABUF_RENDERER=1` to the wrapper unconditionally
- Ensure you're using GNOME Platform 51 or newer

### Fonts not loading (returns 0)
- Ensure resources are copied to `/app/resources`
- The wrapper script must `cd /app` before executing the binary

### Segfault in libpangoft2 (e.g. on "remote print")
- `segfault at 38 ... in libpangoft2-1.0.so.0.5600.4`: pango before 1.57.1 crashing on the app's privately loaded fonts (issue #4)
- Fixed by the fonts in `/app/share/fonts` and by GNOME 49+ runtimes; seen with the 1.3.9.3 bundle on GNOME 48

### Cannot import/save files
- Check that `--filesystem=home` is in the finish-args
- For USB drives, ensure `--filesystem=/run/media` and `--filesystem=/media` are set

### "Remote listing not available" on install
- Always build the bundle with `--runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo`

### Signature error from `flatpak update` right after a release
- GitHub Pages caches the repository summary for up to ten minutes; try again later (see [Maintenance](#maintenance))

## Clean Build

```bash
rm -rf build repo .flatpak-builder
flatpak-builder --repo=repo --force-clean build flatpak/com.anycubic.AnycubicSlicer.yml
```

## GitHub Repository

Releases are published to: https://github.com/develonrails/anycubic-slicer-next

Release format:
- **Tag/Title**: The app version (e.g. `2.0.0.5`)
- **Assets**: `AnycubicSlicer-<VERSION>-x86_64.AppImage` (+ `.zsync`) and `AnycubicSlicer-<VERSION>.flatpak`

The Flatpak repository is published to https://develonrails.github.io/anycubic-slicer-next.

## Credits

- Flatpak wrapper script modeled after OrcaSlicer's entrypoint
- Uses GNOME 51 runtime for WebKit2GTK support
- NVIDIA DMABUF workaround from OrcaSlicer project
- Publishing modeled after [carbonate](https://github.com/develonrails/carbonate)

# How to Build AnycubicSlicer Flatpak

This guide explains how to create a Flatpak package of AnycubicSlicer from the Ubuntu 24.04 .deb package.

## System Requirements (For Running)

The Flatpak uses the GNOME 48 runtime which provides all necessary libraries (WebKit2GTK, GTK3, GStreamer, glibc, etc.) inside the sandbox. It requires:
- Flatpak installed on the system
- GNOME Platform 48 runtime (installed automatically from Flathub)
- A Linux kernel 5.10+ (for Flatpak sandboxing)
- Working GPU drivers (handled via Flatpak GL extensions)

The host's glibc version does **not** matter — the runtime bundles its own. This means it works on older distros like Linux Mint 21 (Ubuntu 22.04, glibc 2.35) and Debian 12.

## Prerequisites (For Building)

- Linux system with Flatpak installed
- `flatpak-builder` tool
- GNOME 48 runtime and SDK
- The AnycubicSlicer .deb package
- `gh` CLI (for creating GitHub releases)
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

# Install GNOME 48 runtime and SDK
flatpak install flathub org.gnome.Platform//48 org.gnome.Sdk//48
```

## Files Overview

- `com.anycubic.AnycubicSlicer.yml` - Flatpak manifest (build recipe)
- `anycubicslicernext.deb` - Source .deb package
- `build/` - Build directory (created during build)
- `repo/` - Local Flatpak repository (created during build)
- `AnycubicSlicer-<VERSION>.flatpak` - Final Flatpak bundle (output)

## Checking for New Versions

Anycubic publishes .deb packages to their APT repository. The deb package version does **NOT** match the actual app version (e.g. deb version `1.3.96` contains app version `1.3.9.3`).

### Step 1: Check the APT Packages file

```bash
curl -s https://cdn-universe-slicer.anycubic.com/prod/dists/noble/main/binary-amd64/Packages
```

This will show fields like:
```
Package: anycubicslicernext
Version: 1.3.96
Filename: dists/noble/main/binary-amd64/develop_AnycubicSlicerNext-1.3.96_20260131_153250-Ubuntu_24_04_3_LTS.deb
```

**Important notes:**
- The `Filename` field contains the actual download path — it is NOT predictable from the version number alone
- The filename may have a `develop_` prefix — this does NOT necessarily mean it's unstable
- The `Version` field (e.g. `1.3.96`) does NOT match the actual app version (e.g. `1.3.9.3`)

### Step 2: Download the .deb

```bash
DEB_FILENAME=$(curl -s https://cdn-universe-slicer.anycubic.com/prod/dists/noble/main/binary-amd64/Packages | grep "^Filename:" | awk '{print $2}')
curl -L -o anycubicslicernext.deb "https://cdn-universe-slicer.anycubic.com/prod/${DEB_FILENAME}"
```

### Step 3: Check the actual app version

```bash
mkdir -p /tmp/version-check && cd /tmp/version-check
ar x /path/to/anycubicslicernext.deb
tar xzf data.tar.gz
strings usr/bin/AnycubicSlicerNext | grep "AnycubicSlicerNext/"
```

This will output something like `AnycubicSlicerNext/1.3.9.3` — that is the real app version.

## Build Process

### Step 1: Set up workspace

```bash
APP_VERSION="1.3.9.3"
mkdir -p "Anycubic-Flatpak ${APP_VERSION}"
cd "Anycubic-Flatpak ${APP_VERSION}"
```

### Step 2: Place the .deb and manifest

Ensure these files are in the folder:
- `anycubicslicernext.deb` — the downloaded .deb package
- `com.anycubic.AnycubicSlicer.yml` — the Flatpak manifest

### Step 3: Build the Flatpak

```bash
# Build (creates build/ and repo/ directories)
flatpak-builder --repo=repo --force-clean build com.anycubic.AnycubicSlicer.yml
```

### Step 4: Create a distributable bundle

```bash
flatpak build-bundle repo "AnycubicSlicer-${APP_VERSION}.flatpak" \
  com.anycubic.AnycubicSlicer "${APP_VERSION}" \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
```

The `--runtime-repo` flag tells the bundle where to download the GNOME runtime if users don't have it installed.

### Step 5: Test the Flatpak

```bash
# Quick test without installing
flatpak-builder --run build com.anycubic.AnycubicSlicer.yml anycubic-slicer-wrapper

# Or install locally for full testing
flatpak install --user "AnycubicSlicer-${APP_VERSION}.flatpak"
flatpak run com.anycubic.AnycubicSlicer

# Uninstall when done testing
flatpak uninstall --user com.anycubic.AnycubicSlicer
```

### Step 6: Create GitHub Release (after testing)

```bash
# Add the flatpak to an existing release
gh release upload "${APP_VERSION}" \
  --repo develonrails/anycubic-slicer-next \
  "AnycubicSlicer-${APP_VERSION}.flatpak"

# Or create a new release with both AppImage and Flatpak
gh release create "${APP_VERSION}" \
  --repo develonrails/anycubic-slicer-next \
  --title "${APP_VERSION}" \
  --notes "Anycubic Slicer Next as AppImage and Flatpak." \
  "AnycubicSlicer-${APP_VERSION}-x86_64.AppImage" \
  "AnycubicSlicer-${APP_VERSION}.flatpak"
```

## Understanding the Manifest

### Runtime Selection

We use **GNOME Platform 48** because:
- It includes WebKit2GTK (required by AnycubicSlicer's UI)
- It includes GTK-3 and all necessary libraries
- Version 48 has WebKit rendering fixes that resolve white screen issues
- The freedesktop runtime does NOT include WebKit

### Permissions (finish-args)

| Permission | Purpose |
|---|---|
| `--share=ipc` | X11 shared memory (required for display) |
| `--socket=x11` | X11 display access |
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
cd /app
exec /app/bin/AnycubicSlicerNext "$@"
```

**Key design decisions:**
- DMABUF is only disabled for NVIDIA (unconditionally disabling it can cause issues on other GPUs)
- `LC_ALL=C.UTF-8` instead of `LC_ALL=C` (preserves UTF-8 support)
- `cd /app` is needed for resource path resolution (fonts, profiles, etc.)
- No contradictory compositing mode flags (the old build had both FORCE and DISABLE which caused issues)

## Version History

| App Version | Deb Version | Deb Filename | Date |
|---|---|---|---|
| 1.3.9.3 | 1.3.96 | `develop_AnycubicSlicerNext-1.3.96_20260131_153250-Ubuntu_24_04_3_LTS.deb` | 2026-01-31 |
| 1.3.7.3 | 1.3.7171 | `AnycubicSlicerNext-1.3.7171_20250928_162543-Ubuntu_24_04_2_LTS.deb` | 2025-09-28 |

## Updating to a New Version

When a new version is released:

1. **Download the new .deb** (see "Checking for New Versions" above)
2. **Check the real app version** with `strings` on the binary
3. **Update the manifest** — change these fields:
   - `branch:` — set to the new app version
   - `sources: path:` — if you renamed the deb file
4. **Clean and rebuild**:
   ```bash
   rm -rf build repo .flatpak-builder
   flatpak-builder --repo=repo --force-clean build com.anycubic.AnycubicSlicer.yml
   flatpak build-bundle repo "AnycubicSlicer-${NEW_VERSION}.flatpak" \
     com.anycubic.AnycubicSlicer "${NEW_VERSION}" \
     --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
   ```
5. **Test thoroughly**, then upload to GitHub

**What stays the same**: Manifest structure, wrapper script, permissions, runtime
**What changes**: `branch` field, deb file, output filename

## Troubleshooting

### White/blank screen
- This is typically a WebKit DMABUF rendering issue
- The wrapper script conditionally disables DMABUF for NVIDIA GPUs
- If you still see a white screen on non-NVIDIA GPUs, try adding `WEBKIT_DISABLE_DMABUF_RENDERER=1` to the wrapper unconditionally
- Ensure you're using GNOME Platform 48+ (older versions have WebKit bugs)

### Fonts not loading (returns 0)
- Ensure resources are copied to `/app/resources`
- The wrapper script must `cd /app` before executing the binary

### Cannot import/save files
- Check that `--filesystem=home` is in the finish-args
- For USB drives, ensure `--filesystem=/run/media` and `--filesystem=/media` are set

### "Remote listing not available" on install
- Always build the bundle with `--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo`

## Clean Build

```bash
rm -rf build repo .flatpak-builder
flatpak-builder --repo=repo --force-clean build com.anycubic.AnycubicSlicer.yml
flatpak build-bundle repo "AnycubicSlicer-${APP_VERSION}.flatpak" \
  com.anycubic.AnycubicSlicer "${APP_VERSION}" \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
```

## GitHub Repository

Releases are published to: https://github.com/develonrails/anycubic-slicer-next

Release format:
- **Tag/Title**: The app version (e.g. `1.3.9.3`)
- **Assets**: `AnycubicSlicer-<VERSION>-x86_64.AppImage` and `AnycubicSlicer-<VERSION>.flatpak`

## Credits

- Flatpak wrapper script modeled after OrcaSlicer's entrypoint
- Uses GNOME 48 runtime for WebKit2GTK support
- NVIDIA DMABUF workaround from OrcaSlicer project

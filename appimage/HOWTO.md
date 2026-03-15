# AnycubicSlicer AppImage

This folder contains the source files and instructions for building the AnycubicSlicer AppImage from the Ubuntu 24.04 .deb package.

## System Requirements (For Running)

The AppImage requires a modern Linux distribution with glibc 2.38+ and GLib 2.76+:
- Ubuntu 23.10+, Fedora 39+, Debian 13 (Trixie)+, Arch, etc.
- For older distros (e.g. Debian 12), use the Flatpak instead

**System dependencies required:**
- WebKit2GTK 4.1
- GTK-3
- GStreamer
- GLib 2.76+
- glibc 2.38+
- OpenGL/EGL drivers

## Prerequisites (For Building)

- Linux system (any distribution)
- `ar` command (usually in binutils package)
- `tar` command
- `curl` command
- `appimagetool` (downloaded in build process)
- `gh` CLI (for creating GitHub releases)
- Internet connection

## Files Overview

- `ubuntu-24-deb-file/` - Contains the original .deb package
- `extracted/` - Extracted contents of the .deb package
- `AnycubicSlicer.AppDir/` - AppImage directory structure
- `AnycubicSlicer-<VERSION>-x86_64.AppImage` - Final AppImage (output)

## Checking for New Versions

Anycubic publishes .deb packages to their APT repository. The deb package version does **NOT** match the actual app version (e.g. deb version `1.3.96` contains app version `1.3.9.3`). Follow these steps to check for updates:

### Step 1: Check the APT Packages file

The Packages file contains the current deb metadata including the actual filename:

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

### Step 2: Download the .deb using the Filename from the Packages file

```bash
# The download URL is the repo base URL + the Filename from the Packages file
curl -L -o anycubicslicernext.deb \
  "https://cdn-universe-slicer.anycubic.com/prod/<FILENAME_FROM_PACKAGES_FILE>"
```

### Step 3: Check the actual app version

The deb metadata version doesn't match the real app version. To find the actual version, extract the deb and check the binary:

```bash
mkdir -p /tmp/version-check && cd /tmp/version-check
ar x /path/to/anycubicslicernext.deb
tar xzf data.tar.gz
strings usr/bin/AnycubicSlicerNext | grep "AnycubicSlicerNext/"
```

This will output something like:
```
AnycubicSlicerNext/1.3.9.3
```

That is the real app version to use for the AppImage filename and GitHub release.

## Build Process

### Step 1: Set up workspace

```bash
# Use the real app version (from the binary, NOT the deb version)
APP_VERSION="1.3.9.3"

mkdir -p "Anycubic-Appimage ${APP_VERSION}/ubuntu-24-deb-file"
cd "Anycubic-Appimage ${APP_VERSION}"
```

### Step 2: Download the .deb Package

```bash
# First, get the filename from the Packages file
DEB_FILENAME=$(curl -s https://cdn-universe-slicer.anycubic.com/prod/dists/noble/main/binary-amd64/Packages | grep "^Filename:" | awk '{print $2}')
echo "Downloading: $DEB_FILENAME"

# Download
curl -L -o ubuntu-24-deb-file/anycubicslicernext.deb \
  "https://cdn-universe-slicer.anycubic.com/prod/${DEB_FILENAME}"
```

### Step 3: Extract the .deb Package

```bash
mkdir -p extracted
cd extracted
ar x ../ubuntu-24-deb-file/anycubicslicernext.deb
tar xzf data.tar.gz
cd ..
```

### Step 4: Create AppDir Structure

```bash
mkdir -p AnycubicSlicer.AppDir

# Copy all files from usr/ to AppDir
cp -r extracted/usr/* AnycubicSlicer.AppDir/

# Copy desktop file and icon to AppDir root
cp AnycubicSlicer.AppDir/share/applications/AnycubicSlicer.desktop AnycubicSlicer.AppDir/
cp AnycubicSlicer.AppDir/share/AnycubicSlicerNext/resources/images/AnycubicSlicer.png AnycubicSlicer.AppDir/

# Copy resources to AppDir root (important for the app to find them)
cp -r AnycubicSlicer.AppDir/share/AnycubicSlicerNext/resources AnycubicSlicer.AppDir/
```

### Step 5: Modify Desktop File

```bash
sed -i 's|Icon=.*|Icon=AnycubicSlicer|' AnycubicSlicer.AppDir/AnycubicSlicer.desktop
```

### Step 6: Create AppRun Script

```bash
cat > AnycubicSlicer.AppDir/AppRun <<'EOF'
#!/bin/bash
DIR=$(readlink -f "$0" | xargs dirname)

export LD_LIBRARY_PATH="$DIR/lib:$DIR/bin:$LD_LIBRARY_PATH"

# FIXME: Slicer segfault workarounds (from OrcaSlicer)
# 1) Slicer will segfault on systems where locale info is not as expected (i.e. Holo-ISO arch-based distro)
export LC_ALL=C

if [ "$XDG_SESSION_TYPE" = "wayland" ] && [ "$ZINK_DISABLE_OVERRIDE" != "1" ]; then
    if command -v glxinfo >/dev/null 2>&1; then
        RENDERER=$(glxinfo | grep "OpenGL renderer string:" | sed 's/.*: //')
        if echo "$RENDERER" | grep -qi "NVIDIA"; then
            if command -v nvidia-smi >/dev/null 2>&1; then
                DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
                DRIVER_MAJOR=$(echo "$DRIVER_VERSION" | cut -d. -f1)
                [ "$DRIVER_MAJOR" -gt 555 ] && ZINK_FORCE_OVERRIDE=1
            fi
            if [ "$ZINK_FORCE_OVERRIDE" = "1" ]; then
                export __GLX_VENDOR_LIBRARY_NAME=mesa
                export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
                export MESA_LOADER_DRIVER_OVERRIDE=zink
                export GALLIUM_DRIVER=zink
                export WEBKIT_DISABLE_DMABUF_RENDERER=1
            fi
        fi
    fi
fi

# Set resource path for the application to find its resources
export ANYCUBIC_RESOURCES_PATH="$DIR/resources"

# WebKit rendering fixes
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_FORCE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1

exec "$DIR/bin/AnycubicSlicerNext" "$@"
EOF

chmod +x AnycubicSlicer.AppDir/AppRun
```

### Step 7: Download appimagetool

```bash
curl -L -o appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x appimagetool
```

### Step 8: Build the AppImage

```bash
ARCH=x86_64 ./appimagetool AnycubicSlicer.AppDir "AnycubicSlicer-${APP_VERSION}-x86_64.AppImage"
```

### Step 9: Test the AppImage

```bash
chmod +x "AnycubicSlicer-${APP_VERSION}-x86_64.AppImage"

# Run it from the command line to view logs
./"AnycubicSlicer-${APP_VERSION}-x86_64.AppImage"
```

You should see output like:
```
[2026-01-07 17:20:33.141739] [0x00007fc45bad9b00] [trace]   Initializing StaticPrintConfigs
add font of HarmonyOS_Sans_SC_Bold returns 1
add font of HarmonyOS_Sans_SC_Regular returns 1
add font of NanumGothic-Regular returns 1
add font of NanumGothic-Bold returns 1
```

If fonts return 1, everything is working correctly!

### Step 10: Create GitHub Release

```bash
gh release create "${APP_VERSION}" \
  --repo develonrails/anycubic-slicer-next \
  --title "${APP_VERSION}" \
  --notes "Anycubic Slicer Next as AppImage." \
  "AnycubicSlicer-${APP_VERSION}-x86_64.AppImage"
```

## Version History

| App Version | Deb Version | Deb Filename | Date |
|---|---|---|---|
| 1.3.9.3 | 1.3.96 | `develop_AnycubicSlicerNext-1.3.96_20260131_153250-Ubuntu_24_04_3_LTS.deb` | 2026-01-31 |
| 1.3.9.1 | 1.3.91 | (unknown) | 2026-01 |
| 1.3.7.3 | 1.3.7171 | `AnycubicSlicerNext-1.3.7171_20250928_162543-Ubuntu_24_04_2_LTS.deb` | 2025-09-28 |

## Important Notes

### Deb Version vs App Version

Anycubic's deb packaging uses a **different version number** than the actual application. The deb `Version` field is a flattened/abbreviated form:
- Deb `1.3.7171` = App `1.3.7.3` (roughly)
- Deb `1.3.96` = App `1.3.9.3`

Always check the binary with `strings` to get the real version for naming the AppImage and GitHub release.

### Directory Structure

The AppDir must have this structure for the app to work:

```
AnycubicSlicer.AppDir/
├── AppRun                    # Launch script
├── AnycubicSlicer.desktop    # Desktop integration file
├── AnycubicSlicer.png        # Icon
├── bin/
│   └── AnycubicSlicerNext    # Main binary
├── lib/                      # Application libraries
│   ├── libcloud_mqtt.so
│   ├── libcloud_sdk_cpp.so
│   └── ...
├── resources/                # Resources at root level (critical!)
│   ├── fonts/
│   ├── calib/
│   ├── profiles/
│   └── ...
└── share/
    └── AnycubicSlicerNext/
        └── resources/        # Resources also here for compatibility
```

### Key Features in AppRun

1. **LC_ALL=C**: Prevents segfaults on systems with non-standard locales
2. **NVIDIA/Wayland workarounds**: Fixes crashes on newer NVIDIA drivers (>555) with Wayland
3. **WebKit rendering fixes**: Environment variables to fix graphics/rendering issues with WebKit-based UI
4. **LD_LIBRARY_PATH**: Ensures bundled application libraries are found
5. **No `cd "$DIR"`**: Preserves filesystem access for file imports/exports

### Resources Location

The resources **must** be at the AppDir root level (`resources/`) because:
- The binary looks for `resources/fonts/` relative to its execution directory
- Resources are found via relative paths from where the binary is located
- Without resources at the root level, fonts will fail to load (returns 0 instead of 1)

### Filesystem Access

**Important**: The AppRun script does NOT use `cd "$DIR"` to change to the AppImage directory. While this was initially thought to help resources load, it actually blocks filesystem access:
- **With `cd "$DIR"`**: File dialogs cannot access your home directory or import files
- **Without `cd "$DIR"`**: Full filesystem access works correctly, and resources still load properly

The binary can find its resources through the `LD_LIBRARY_PATH` and relative path lookups without needing to change the working directory.

## Dependencies

The AppImage relies on these system libraries (should be available on most Linux distros):
- WebKit2GTK 4.1
- GTK-3
- GStreamer
- OpenGL/EGL
- Standard C/C++ libraries

## Troubleshooting

### Fonts not loading (returns 0)
- Ensure `resources/` directory is at AppDir root
- Check that all font files exist in `resources/fonts/`
- Verify the LD_LIBRARY_PATH is set correctly in AppRun

### Cannot import files / filesystem access blocked
- Ensure AppRun does NOT have `cd "$DIR"` in it
- The working directory should remain where the user launched the AppImage from
- Resources are found via relative paths from the binary location, not by changing directories

### Graphics/rendering issues
- The AppImage includes WebKit rendering fixes by default:
  - `__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json`
  - `WEBKIT_DISABLE_DMABUF_RENDERER=1`
  - `WEBKIT_FORCE_COMPOSITING_MODE=1`
  - `WEBKIT_DISABLE_COMPOSITING_MODE=1`
- These help with WebView rendering problems, UI glitches, and compositing issues
- If you still experience issues, you can override these by setting different values before running

### GLIBC_2.38 / GLIBCXX_3.4.32 / g_once_init_leave_pointer not found

If you see errors like:
```
version `GLIBC_2.38' not found
version `GLIBCXX_3.4.32' not found
undefined symbol: g_once_init_leave_pointer
```

**Your distribution is too old.** The AppImage requires glibc 2.38+ and GLib 2.76+. Distributions like Debian 12 (Bookworm) do not meet these requirements. Use the Flatpak version instead for older distributions.

### Missing library errors
- The AppImage includes application-specific libraries
- System libraries (GTK, WebKit) must be installed on the target system
- For better portability, consider using the Flatpak version

### Camera permission requests
- AnycubicSlicer has webcam integration for printer monitoring
- This is a legitimate feature, not a bug
- You can deny the permission if you don't use this feature

## File Sizes

- Original .deb: ~126 MB
- Final AppImage: ~126 MB

## GitHub Repository

Releases are published to: https://github.com/develonrails/anycubic-slicer-next

Release format:
- **Tag/Title**: The app version (e.g. `1.3.9.3`)
- **Notes**: `Anycubic Slicer Next as AppImage.`
- **Asset**: `AnycubicSlicer-<VERSION>-x86_64.AppImage`

## Credits

Build process inspired by OrcaSlicer AppImage packaging, with additional fixes for:
- Font loading
- Resource path resolution
- Filesystem access (avoiding `cd "$DIR"` to maintain file dialog access)
- WebKit rendering issues (DMA-BUF and compositing fixes)
- Wayland/NVIDIA compatibility
- Locale handling

# AnycubicSlicer AppImage

This folder contains the source files and instructions for building the AnycubicSlicer AppImage from the Ubuntu 24.04 .deb package.

Releases are built and published automatically by `.github/workflows/release.yml` whenever Anycubic publishes a new .deb (see [flatpak/HOWTO.md](../flatpak/HOWTO.md#publishing)). This page is for building one by hand and for understanding what the build does.

## System Requirements (For Running)

The AppImage requires a modern Linux distribution with glibc 2.38+ and GLib 2.80+:
- Ubuntu 24.04+, Fedora 40+, Debian 13 (Trixie)+, Arch, etc.
- For older distros (e.g. Debian 12, Ubuntu 22.04), use the Flatpak instead

**System dependencies required:**
- WebKit2GTK 4.1
- GTK-3
- GStreamer
- GLib 2.80+
- glibc 2.38+
- libtiff 6 (since 2.0.0.5)
- OpenGL/EGL drivers
- X11 or XWayland (the app forces `GDK_BACKEND=x11`)

**FUSE:** the AppImage needs a setuid `fusermount3` (FUSE 3) **or** `fusermount` (FUSE 2), which every desktop distribution has. It does **not** need `libfuse2` / `libfuse.so.2`, unless it was built with the old AppImageKit tool (every release up to 1.3.9.4, see Troubleshooting).

## Prerequisites (For Building)

- Linux system (any distribution)
- `ar` (binutils), `tar`, `curl`, `sha256sum`
- `file` (`appimagetool` refuses to run without it)
- `gpg` and `gpgv` (to check the AppImage runtime's signature)
- Internet connection

`appimagetool` itself is downloaded by the build script.

## Files Overview

- `build.sh` - Builds the AppImage from the .deb
- `AppRun` - Launch script, the AppImage's entry point
- `AnycubicSlicer.desktop` - Desktop integration file
- `../scripts/anycubic-deb.sh` - Finds and downloads the current .deb from Anycubic's APT repository
- `../scripts/smoke-test.sh` - Starts the app on a virtual display to check it comes up

## Checking for New Versions

Anycubic publishes .deb packages to their APT repository. The deb package version does **NOT** match the actual app version (e.g. deb version `2.0.06` contains app version `2.0.0.5`).

```bash
scripts/anycubic-deb.sh latest
```

prints the current entry of the APT `Packages` file:
```
DEB_URL=https://cdn-universe-slicer.anycubic.com/prod/pool/main/a/anycubicslicernext/AnycubicSlicerNext_linux-v2.0.0.5-20260913065625.deb
DEB_SHA256=fe087a56014ed25cdfe4c3c293b517adaee0a9b2e1ded79f5e394b7968817c15
DEB_SIZE=153422098
DEB_VERSION=2.0.06
```

**Important notes:**
- The download path comes from the `Filename` field and is NOT predictable from the version number alone. It has moved before (from `dists/noble/...` to `pool/main/...`), and the filename may or may not have a `develop_` prefix.
- The script insists on exactly one `anycubicslicernext` entry. If Anycubic ever lists several, it stops rather than guess which one is current.

The real app version is in the deb's resources:

```bash
scripts/anycubic-deb.sh app-version anycubicslicernext.deb
# 2.0.0.5
```

It reads `usr/share/AnycubicSlicerNext/resources/build-version.txt`. (Up to 1.3.9.4, `strings usr/bin/AnycubicSlicerNext | grep "AnycubicSlicerNext/"` also printed the version; since 2.0.0.5 it only prints the format string `AnycubicSlicerNext/V%s (%s) %s`.)

## Build Process

```bash
scripts/anycubic-deb.sh download anycubicslicernext.deb   # downloads and checks the SHA256
appimage/build.sh anycubicslicernext.deb                  # writes the AppImage and its .zsync here
```

`build.sh` does the following:

1. **Extract the .deb**: `ar x`, then `tar xf data.tar.*`.
2. **Create the AppDir**: copy everything from `usr/`, drop the build leftovers the deb ships since 2.0.0.5 (`include/`, `lib/cmake/`, `lib/*.a`), and copy the resources to the AppDir root as well (see "Resources Location").
3. **Add the desktop file, icon and `AppRun`** from this folder.
4. **Download `appimagetool` and the AppImage runtime.** It uses the maintained `appimagetool` from [AppImage/appimagetool](https://github.com/AppImage/appimagetool), pinned by SHA256. It does **not** use the old one from `AppImage/AppImageKit`: that is marked obsolete and embeds a runtime that `dlopen()`s `libfuse.so.2`, so the AppImage fails on distributions that no longer ship FUSE 2 (issue #11). The new runtime from [AppImage/type2-runtime](https://github.com/AppImage/type2-runtime) is static and works with FUSE 3 or FUSE 2. It is taken from that project's rolling `continuous` release and checked against its signing key (`570C77ACEA40C0F1B758902CBF96CCA56490F695`) rather than a hash, so it picks up fixes without breaking the build.
5. **Build the AppImage**, zstd-compressed, with update information embedded so AppImageUpdate and Gear Lever can update it from the latest GitHub release. `appimagetool` also writes the matching `.zsync`, which has to be uploaded to the release next to the AppImage.

### Test the AppImage

```bash
./AnycubicSlicer-2.0.0.5-x86_64.AppImage --appimage-version
# AppImage runtime version: https://github.com/AppImage/type2-runtime/commit/<hash>
```

An AppImage built with the old AppImageKit tool prints `Version: 5735cc5` here instead.

Run it from the command line to view logs:
```bash
./AnycubicSlicer-2.0.0.5-x86_64.AppImage
```

You should see output like:
```
[2026-10-10 12:11:01.797875] [0x00007f56c71876c0] [trace]   Initializing StaticPrintConfigs
add font of HarmonyOS_Sans_SC_Bold returns 1
add font of HarmonyOS_Sans_SC_Regular returns 1
add font of NanumGothic-Regular returns 1
add font of NanumGothic-Bold returns 1
```

If fonts return 1, everything is working correctly! `scripts/smoke-test.sh` checks the same thing headless (it needs `xvfb-run`): `APPIMAGE_EXTRACT_AND_RUN=1 scripts/smoke-test.sh ./AnycubicSlicer-*.AppImage`.

## Version History

| App Version | Deb Version | Deb Filename | Date |
|---|---|---|---|
| 2.0.0.5 | 2.0.06 | `pool/main/a/anycubicslicernext/AnycubicSlicerNext_linux-v2.0.0.5-20260913065625.deb` | 2026-09-13 |
| 1.3.9.4 | (unknown) | (unknown) | 2026-03-19 |
| 1.3.9.3 | 1.3.96 | `develop_AnycubicSlicerNext-1.3.96_20260131_153250-Ubuntu_24_04_3_LTS.deb` | 2026-01-31 |
| 1.3.9.1 | 1.3.91 | (unknown) | 2026-01 |
| 1.3.7.3 | 1.3.7171 | `AnycubicSlicerNext-1.3.7171_20250928_162543-Ubuntu_24_04_2_LTS.deb` | 2025-09-28 |

## Important Notes

### Deb Version vs App Version

Anycubic's deb packaging uses a **different version number** than the actual application. The deb `Version` field is a flattened/abbreviated form:
- Deb `1.3.7171` = App `1.3.7.3` (roughly)
- Deb `1.3.96` = App `1.3.9.3`
- Deb `2.0.06` = App `2.0.0.5`

Always use `build-version.txt` (`scripts/anycubic-deb.sh app-version`) for naming the AppImage and GitHub release.

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
- AppRun sets these unconditionally, so setting them yourself before running has no effect. To try other values, extract the AppImage (`--appimage-extract`), edit `squashfs-root/AppRun` and run that

### GLIBC_2.38 / GLIBCXX_3.4.32 / g_once_init_leave_pointer not found

If you see errors like:
```
version `GLIBC_2.38' not found
version `GLIBCXX_3.4.32' not found
undefined symbol: g_once_init_leave_pointer
```

**Your distribution is too old.** The AppImage requires glibc 2.38+ and GLib 2.80+ (`g_once_init_leave_pointer` arrived in GLib 2.80). Distributions like Debian 12 (Bookworm) and Ubuntu 22.04 do not meet these requirements. Use the Flatpak version instead for older distributions.

### dlopen(): error loading libfuse.so.2 / AppImages require FUSE to run

The AppImage was built with the obsolete AppImageKit `appimagetool`, whose runtime needs FUSE 2 (`libfuse.so.2`). Every release up to 1.3.9.4 is affected (`--appimage-version` prints `Version: 5735cc5`). Distributions that no longer ship FUSE 2 (e.g. Debian testing) cannot mount these AppImages. AppImages built by `build.sh` do not have this problem.

Users of an affected AppImage can run it without FUSE:
- `./AnycubicSlicer-<VERSION>-x86_64.AppImage --appimage-extract-and-run` (or `APPIMAGE_EXTRACT_AND_RUN=1 ./AnycubicSlicer-<VERSION>-x86_64.AppImage`): extracts to `/tmp` on every launch and deletes it on exit, so startup is slower
- `./AnycubicSlicer-<VERSION>-x86_64.AppImage --appimage-extract` once, then run `./squashfs-root/AppRun`
- Or install the distribution's FUSE 2 library where it still exists (e.g. `libfuse2t64` on Ubuntu 24.04)

### AppImageLauncher: "Squashfs image uses (null) compression", "execv error" or "fuse: memory allocation failed"

AppImageLauncher 2.2.0 intercepts every AppImage launch. It cannot read zstd-compressed AppImages and cannot start AppImages with the static type2-runtime, so AppImages built by `build.sh` fail when it is installed (the same applies to current OrcaSlicer and Bambu Studio AppImages). Update AppImageLauncher to v3.0.0-beta-3 or newer, or uninstall it.

### Missing library errors
- The AppImage includes application-specific libraries
- System libraries (GTK, WebKit, libtiff) must be installed on the target system
- For better portability, consider using the Flatpak version

### Camera permission requests
- AnycubicSlicer has webcam integration for printer monitoring
- This is a legitimate feature, not a bug
- You can deny the permission if you don't use this feature

## File Sizes

- Original .deb: ~153 MB (2.0.0.5)
- Final AppImage: ~144 MB (2.0.0.5, zstd)

## GitHub Repository

Releases are published to: https://github.com/develonrails/anycubic-slicer-next

Release format:
- **Tag/Title**: The app version (e.g. `2.0.0.5`)
- **Assets**: `AnycubicSlicer-<VERSION>-x86_64.AppImage`, its `.zsync`, and `AnycubicSlicer-<VERSION>.flatpak`

## Credits

Build process inspired by OrcaSlicer AppImage packaging, with additional fixes for:
- Font loading
- Resource path resolution
- Filesystem access (avoiding `cd "$DIR"` to maintain file dialog access)
- WebKit rendering issues (DMA-BUF and compositing fixes)
- Wayland/NVIDIA compatibility
- Locale handling

# Anycubic Slicer Next

[![GitHub release](https://img.shields.io/github/release/develonrails/anycubic-slicer-next.svg)](https://github.com/develonrails/anycubic-slicer-next/releases)

Flatpak and AppImage of the Anycubic Slicer Next.

Anycubic only publishes the slicer as an Ubuntu 24.04 .deb. This repository repackages that
.deb, and rebuilds it automatically within the hour when Anycubic publishes a new version.
It is unofficial and not affiliated with Anycubic.

## Flatpak (recommended)

Add the repository once:

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-add --user --if-not-exists --from \
    anycubic-slicer-next https://develonrails.github.io/anycubic-slicer-next/anycubic-slicer-next.flatpakrepo

flatpak install --user anycubic-slicer-next com.anycubic.AnycubicSlicer
```

After that `flatpak update` picks up every new version, and so does GNOME Software or KDE
Discover, the same as any other Flatpak you have installed.

The first line is for the GNOME runtime the app runs on, which comes from Flathub. Most
distributions set up Flathub system-wide, but a `--user` install only looks for the runtime
in your own remotes, so it needs Flathub there too. It does nothing if you have it already.

Rather download a single file? Every [release](https://github.com/develonrails/anycubic-slicer-next/releases)
has an `AnycubicSlicer-<version>.flatpak`. Open it with your software center or run
`flatpak install --user ./AnycubicSlicer-<version>.flatpak`. It sets up the same repository
(and Flathub for the runtime) behind the scenes, so it updates too.

### Coming from 1.3.9.4 or older?

The `.flatpak` files up to 1.3.9.4 were installed per version and cannot update. Install the
current version by either route above, then remove the old one (this does not delete your
settings):

```sh
flatpak uninstall com.anycubic.AnycubicSlicer//1.3.9.4
flatpak uninstall --unused
```

`flatpak list --app` shows which versions you have.

## AppImage

- Download `AnycubicSlicer-<version>-x86_64.AppImage` from the [releases](https://github.com/develonrails/anycubic-slicer-next/releases) page
- Hit properties of file, enable "Execute as program"
- You're good to go!

The AppImage uses your system's GTK and WebKit, so it needs a recent distribution: glibc 2.38+
and GLib 2.80+ (Ubuntu 24.04+, Fedora 40+, Debian 13+, Arch). On anything older, use the
Flatpak. [Gear Lever](https://flathub.org/apps/it.mijorus.gearlever) and AppImageUpdate can
keep the AppImage up to date.

### `dlopen(): error loading libfuse.so.2`

AppImages up to 1.3.9.4 need FUSE 2, which some distributions (such as Debian testing) no
longer ship. Newer releases do not. To run an old one anyway, start it with
`--appimage-extract-and-run`.

### AppImageLauncher: "execv error" or "Squashfs image uses (null) compression"

AppImageLauncher 2.2.0 cannot start AppImages built with the current AppImage tools (the same
goes for OrcaSlicer and Bambu Studio). Update AppImageLauncher to v3.0.0-beta-3 or newer, or
uninstall it.

## Building it yourself

See [flatpak/HOWTO.md](flatpak/HOWTO.md) and [appimage/HOWTO.md](appimage/HOWTO.md). The
Flatpak HOWTO also explains how releases are published.

My first ever Flatpak/AppImage created so no guarantees given. So far all seems to work.

If this helps you please star the repo or support me on Ko-fi.

#!/usr/bin/env bash
# Packages the Linux build (docs/desktop-features-spec.md §16): the bundle into /opt/uwuHere/, a
# symlink on the PATH, the .desktop file (with the uwu:// handler) and icons, as a .deb (dpkg-deb),
# an .rpm (rpmbuild) and an AppImage (appimagetool). One set per processor, built on it.
#
# The names stay the same from version to version, so each installs over the last as an upgrade
# and an AppImage's updater finds the next: the package uwuhere-desktop, the app in /opt/uwuHere/
# as uwuhere, its menu entry uwuhere-desktop.desktop, and the files uwuhere-<version>-amd64.deb
# and uwuhere-<version>-x86_64.AppImage.
#
#   installers/linux/package.sh <version> <amd64|arm64> <bundle dir> <out dir>
set -euo pipefail

version="$1"; arch="$2"; bundle="$3"; out="$4"
here="$(cd "$(dirname "$0")" && pwd)"
icon="$here/../../assets/images/icon-512.png"
mkdir -p "$out"
case "$arch" in
  amd64) rpm_arch=x86_64; appimage_arch=x86_64 ;;
  arm64) rpm_arch=aarch64; appimage_arch=aarch64 ;;
  *) echo "unknown arch $arch" >&2; exit 1 ;;
esac

desktop_entry() {
  cat <<EOF
[Desktop Entry]
Type=Application
Name=uwuHere
GenericName=Attendance
Comment=Take attendance in one tap. People check in when they're near you
Exec=$1 %u
Icon=uwuhere
Terminal=false
Categories=Office;Education;Utility;
MimeType=x-scheme-handler/uwu;
StartupWMClass=uwuhere
Keywords=attendance;check-in;register;roll call;event;qr;
EOF
}

# ---- the tree, shared by the .deb and the .rpm ----
root="$(mktemp -d)"
mkdir -p "$root/opt/uwuHere" "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/icons/hicolor/512x512/apps" "$root/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle/." "$root/opt/uwuHere/"
ln -s /opt/uwuHere/uwuhere "$root/usr/bin/uwuhere"
desktop_entry /opt/uwuHere/uwuhere > "$root/usr/share/applications/uwuhere-desktop.desktop"
cp "$icon" "$root/usr/share/icons/hicolor/512x512/apps/uwuhere.png"
convert "$icon" -resize 256x256 "$root/usr/share/icons/hicolor/256x256/apps/uwuhere.png" 2>/dev/null || cp "$icon" "$root/usr/share/icons/hicolor/256x256/apps/uwuhere.png"
size_kb="$(du -sk "$root" | cut -f1)"

# ---- .deb ----
deb="$(mktemp -d)"
cp -a "$root/." "$deb/"
mkdir -p "$deb/DEBIAN"
cat > "$deb/DEBIAN/control" <<EOF
Package: uwuhere-desktop
Version: $version
Section: video
Priority: optional
Architecture: $arch
Maintainer: Augy Studios <noreply@uwuapps.org>
Installed-Size: $size_kb
Depends: libgtk-3-0, libayatana-appindicator3-1 | libappindicator3-1
Homepage: https://here.uwuapps.org
Description: uwuHere, attendance in one tap
 Write a script, press space, and it scrolls. Speed and font size adjust a step
 at a time while it runs, and a phone can drive it by a six-letter code.
EOF
cat > "$deb/DEBIAN/postinst" <<'EOF'
#!/bin/sh
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
EOF
chmod 755 "$deb/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$deb" "$out/uwuhere-$version-$arch.deb"

# ---- .rpm ----
if command -v rpmbuild >/dev/null; then
  top="$(mktemp -d)"
  mkdir -p "$top"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}
  cat > "$top/SPECS/uwuhere-desktop.spec" <<EOF
Name: uwuhere-desktop
Version: $version
Release: 1
Summary: uwuHere, attendance in one tap
License: MIT
URL: https://here.uwuapps.org
Requires: gtk3
AutoReqProv: no
%define _build_id_links none
%define __strip /bin/true

%description
Write a script, press space, and it scrolls, with a phone as the remote.

%install
cp -a $root/. %{buildroot}/

%files
/opt/uwuHere
/usr/bin/uwuhere
/usr/share/applications/uwuhere-desktop.desktop
/usr/share/icons/hicolor/512x512/apps/uwuhere.png
/usr/share/icons/hicolor/256x256/apps/uwuhere.png
EOF
  rpmbuild --define "_topdir $top" --target "$rpm_arch" -bb "$top/SPECS/uwuhere-desktop.spec"
  cp "$top"/RPMS/*/*.rpm "$out/uwuhere-$version-$rpm_arch.rpm"
fi

# ---- AppImage ----
appdir="$(mktemp -d)/uwuHere.AppDir"
mkdir -p "$appdir/usr/lib/uwuhere"
cp -a "$bundle/." "$appdir/usr/lib/uwuhere/"
cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/lib/uwuhere/uwuhere" "$@"
EOF
chmod 755 "$appdir/AppRun"
desktop_entry uwuhere > "$appdir/uwuhere-desktop.desktop"
cp "$icon" "$appdir/uwuhere.png"
tool="appimagetool-$appimage_arch.AppImage"
if [ ! -x "/tmp/$tool" ]; then
  curl -fsSL -o "/tmp/$tool" "https://github.com/AppImage/appimagetool/releases/download/continuous/$tool"
  chmod 755 "/tmp/$tool"
fi
ARCH="$appimage_arch" "/tmp/$tool" --appimage-extract-and-run "$appdir" "$out/uwuhere-$version-$appimage_arch.AppImage"

ls -lh "$out"

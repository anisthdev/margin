# Maintainer: Asif Arbaj <asifarbaj@gmail.com>
pkgname=margin
pkgver=r0
pkgrel=1
pkgdesc="Notes in place of Google Keep: a Quickshell app (qs -c margin) over a small SQLite backend"
arch=('x86_64')
url="https://github.com/anisthdev/margin"
license=('unknown')
depends=('quickshell' 'uwsm' 'wl-clipboard' 'xdg-utils' 'gcc-libs' 'glibc')
makedepends=('git' 'cargo')
# GCC's LTO objects from rusqlite's bundled SQLite don't link with rust-lld
options=('!lto')
source=("git+$url.git")
sha256sums=('SKIP')

pkgver() {
    cd "$pkgname"
    printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)"
}

prepare() {
    cd "$pkgname/backend"
    export RUSTUP_TOOLCHAIN=stable
    cargo fetch --locked --target "$(rustc -vV | sed -n 's/host: //p')"
}

build() {
    cd "$pkgname/backend"
    export RUSTUP_TOOLCHAIN=stable
    cargo build --frozen --release
}

package() {
    cd "$pkgname"
    install -Dm755 backend/target/release/margin "$pkgdir/usr/bin/margin"
    install -Dm755 margin-app "$pkgdir/usr/bin/margin-app"
    # The Quickshell config, where `qs -c margin` finds it; a
    # ~/.config/quickshell/margin of your own comes first
    install -d "$pkgdir/usr/share/margin"
    cp -r --no-preserve=ownership ./*.qml components icons views "$pkgdir/usr/share/margin/"
    install -d "$pkgdir/etc/xdg/quickshell"
    ln -s /usr/share/margin "$pkgdir/etc/xdg/quickshell/margin"
    install -Dm644 io.github.anisthdev.Margin.desktop \
        "$pkgdir/usr/share/applications/io.github.anisthdev.Margin.desktop"
}

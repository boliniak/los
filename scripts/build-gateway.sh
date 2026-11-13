#!/bin/sh
#
# Budowa obrazu OPNsense (aarch64) dla Mono Gateway na hoście FreeBSD 14.3 amd64.
# Odwzorowuje kroki z README oraz target `image` z we-are-mono/opnsense-deps
# (kernel -> sysroot -> libxml2 -> pakiet mono-gateway -> obraz ZFS arm-5G).
#
# Zmienne (z workflow): VERSION, SETTINGS, MIRROR, OUTDIR, DEPS_REF, TOOLS_REF

set -eu

VERSION="${VERSION:-26.1.1}"
SETTINGS="${SETTINGS:-26.1}"
MIRROR="${MIRROR:-https://opnsense.mono.si}"
OUTDIR="${OUTDIR:-$(pwd)/out}"
DEPS_REF="${DEPS_REF:-master}"
TOOLS_REF="${TOOLS_REF:-master}"
SRC_BRANCH="stable/${SETTINGS}"

BUILDROOT="/usr/local/opnsense/build/${SETTINGS}/aarch64"
SETSDIR="${BUILDROOT}/sets"
IMAGESDIR="${BUILDROOT}/images"
SYSROOT="/usr/obj/usr/src/arm64.aarch64/tmp"
LIBXML2_PKG="${LIBXML2_PKG:-libxml2-2.15.2.pkg}"
NCPU="$(sysctl -n hw.ncpu)"
TOOLS_ARGS="DEVICE=GATEWAY SETTINGS=${SETTINGS} TOOLSDIR=/usr/tools"

step() { echo; echo "=================== $* ($(date '+%H:%M:%S')) ==================="; }

step "0. Srodowisko"
uname -a
df -h
sysctl hw.ncpu hw.physmem
mkdir -p "${OUTDIR}"

step "1. Klonowanie repozytoriow"
# opnsense-src: blob:none (pelna historia commitow/tagow dla git describe w tools, bez wszystkich blobow)
[ -d /usr/src/.git ] || git clone --filter=blob:none -b "${SRC_BRANCH}" https://github.com/we-are-mono/opnsense-src.git /usr/src
[ -d /usr/tools/.git ] || git clone -b "${TOOLS_REF}" https://github.com/opnsense/tools.git /usr/tools
[ -d /usr/deps/.git ] || git clone -b "${DEPS_REF}" https://github.com/we-are-mono/opnsense-deps.git /usr/deps
[ -d /usr/core/.git ] || git clone --filter=blob:none -b "${SRC_BRANCH}" https://github.com/opnsense/core.git /usr/core \
	|| git clone --filter=blob:none https://github.com/opnsense/core.git /usr/core
cp /usr/deps/config/GATEWAY.conf /usr/tools/device/
for r in src tools deps core; do echo "/usr/${r}: $(git -C /usr/${r} rev-parse --abbrev-ref HEAD) $(git -C /usr/${r} rev-parse --short HEAD)"; done

step "2. Stub wersji pkg dla check_packages()"
# Starsze tools sprawdzaja ports-mgmt/pkg, nowsze opnsense/pkg - tworzymy oba.
for d in /usr/ports/ports-mgmt/pkg /usr/ports/opnsense/pkg; do
	mkdir -p "${d}"
	echo "PORTVERSION=$(pkg -v)" > "${d}/Makefile"
done

step "3. Prefetch base (${VERSION}) z ${MIRROR}"
make -C /usr/tools prefetch-base ${TOOLS_ARGS} MIRRORS="${MIRROR}" VERSION="${VERSION}"
cd "${SETSDIR}"
if [ ! -f "base-${VERSION}-aarch64.txz" ] && [ ! -f "base-${VERSION}-aarch64-GATEWAY.txz" ]; then
	echo "BLAD: nie pobrano base-${VERSION}-aarch64.txz z ${MIRROR}/FreeBSD:14:aarch64/${SETTINGS}/sets/" >&2
	ls -la "${SETSDIR}" >&2
	exit 1
fi
[ -f "base-${VERSION}-aarch64.txz" ] && mv "base-${VERSION}-aarch64.txz" "base-${VERSION}-aarch64-GATEWAY.txz"
[ -f "base-${VERSION}-aarch64.txz.sig" ] && mv "base-${VERSION}-aarch64.txz.sig" "base-${VERSION}-aarch64-GATEWAY.txz.sig"

step "4. Prefetch packages (${VERSION})"
make -C /usr/tools prefetch-packages ${TOOLS_ARGS} MIRRORS="${MIRROR}" VERSION="${VERSION}"
if ! ls "${SETSDIR}"/packages-${VERSION}-aarch64*.tar >/dev/null 2>&1; then
	echo "BLAD: nie pobrano packages-${VERSION}-aarch64.tar z ${MIRROR}" >&2
	ls -la "${SETSDIR}" >&2
	exit 1
fi
# xtools nie moze istniec przy cross-buildzie (zostawilby binarki amd64 w obrazie)
rm -f "${SETSDIR}"/xtools-*-aarch64*.txz*
ls -lh "${SETSDIR}"

step "5. Kernel GATEWAY (kernel-toolchain + buildkernel)"
rm -f "${SETSDIR}"/kernel-*-GATEWAY.txz
make -C /usr/tools kernel ${TOOLS_ARGS}
ls -lh "${SETSDIR}"

step "6a. Sysroot z base setu"
mkdir -p "${SYSROOT}"
tar xf "${SETSDIR}/base-${VERSION}-aarch64-GATEWAY.txz" -C "${SYSROOT}" --no-fflags \
	--include='./usr/include/*' \
	--include='./usr/lib/*.a' \
	--include='./usr/lib/*.so' \
	--include='./usr/lib/*.o' \
	--include='./lib/*.so*'

step "6b. libxml2 (aarch64) do sysroot"
if [ ! -f "${SYSROOT}/usr/local/lib/libxml2.so" ]; then
	rm -rf /tmp/libxml2.pkg /tmp/libxml2-extract
	fetch -o /tmp/libxml2.pkg "https://pkg.FreeBSD.org/FreeBSD:14:aarch64/latest/All/${LIBXML2_PKG}"
	mkdir -p /tmp/libxml2-extract
	tar xf /tmp/libxml2.pkg -C /tmp/libxml2-extract
	mkdir -p "${SYSROOT}/usr/local/include" "${SYSROOT}/usr/local/lib"
	cp -r /tmp/libxml2-extract/usr/local/include/libxml2 "${SYSROOT}/usr/local/include/"
	cp -a /tmp/libxml2-extract/usr/local/lib/libxml2* "${SYSROOT}/usr/local/lib/"
fi

step "7. Moduly, userspace i pakiet mono-gateway"
make -C /usr/deps -j"${NCPU}" package
ls -lh /usr/deps/dist

step "8. Skladanie obrazu (ZFS, arm-5G)"
kldload -n zfs || true
rm -f "${IMAGESDIR}"/OPNsense-*-GATEWAY.img "${IMAGESDIR}"/OPNsense-*-GATEWAY.img.gz
cp /usr/deps/mk-image.sh /usr/tools/build/arm.sh
cp /usr/deps/tools/mkgpt.py /usr/tools/build/mkgpt.py
make -C /usr/tools arm-5G ${TOOLS_ARGS}

step "9. Kompresja i kopiowanie do ${OUTDIR}"
IMG="$(ls "${IMAGESDIR}"/OPNsense-*-GATEWAY.img | head -1)"
[ -n "${IMG}" ] || { echo "BLAD: brak obrazu w ${IMAGESDIR}" >&2; exit 1; }
gzip -c -6 "${IMG}" > "${OUTDIR}/$(basename "${IMG}").gz"
cp /usr/deps/dist/mono-gateway-*.pkg "${OUTDIR}/" 2>/dev/null || true
cd "${OUTDIR}" && sha256 -r ./* > SHA256SUMS
ls -lh "${OUTDIR}"
step "GOTOWE"

# Contributor: @michalbednarski
# Modified for dev.lwff.dsh: vendor talloc statically so the build does not
# depend on libtalloc .deb from the com.termux repo (whose paths would not
# match this fork's prefix). Mirrors OpenMinis deps/build_proot.sh.
TERMUX_PKG_HOMEPAGE=https://proot-me.github.io/
TERMUX_PKG_DESCRIPTION="Emulate chroot, bind mount and binfmt_misc for non-root users"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="Michal Bednarski @michalbednarski"
TERMUX_PKG_VERSION="5.1.107.91"
TERMUX_PKG_SRCURL=https://github.com/termux/proot/archive/v${TERMUX_PKG_VERSION}.zip
TERMUX_PKG_SHA256=SKIP
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_UPDATE_TAG_TYPE="newest-tag"
TERMUX_PKG_DEPENDS="termux-licenses"
TERMUX_PKG_SUGGESTS="proot-distro"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_EXTRA_MAKE_ARGS="-C src proot loader/loader"

# No PROOT_UNBUNDLE_LOADER: we do NOT bake a package-specific loader path
# into the binary. The loader ships as a separate ELF (libproot-loader.so)
# that any host app installs into its nativeLibraryDir and points at via the
# PROOT_LOADER env var at runtime. This keeps the build package-name
# agnostic, so the same proot binary works under any fork/app package name.

# Standalone replace.h shim for talloc (Samba compat, minimal).
termux_step_get_source() {
	cd "$TERMUX_PKG_SRCDIR"
	# Fetch talloc 2.4.3 single-file source
	local TALLOC_TAR="talloc-2.4.3.tar.gz"
	curl -fsSL "https://www.samba.org/ftp/talloc/talloc-2.4.3.tar.gz" -o "$TALLOC_TAR"
	tar xzf "$TALLOC_TAR"
	cp "talloc-2.4.3/talloc.c" .
	cp "talloc-2.4.3/talloc.h" .
	cat > replace.h <<'REPLACE'
#ifndef REPLACE_H
#define REPLACE_H
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/auxv.h>
#define TALLOC_BUILD_VERSION_MAJOR   2
#define TALLOC_BUILD_VERSION_MINOR   4
#define TALLOC_BUILD_VERSION_RELEASE 3
#define HAVE_SYS_AUXV_H 1
#define HAVE_INTPTR_T 1
#define HAVE_VA_COPY 1
#define VALGRIND_MAKE_MEM_UNDEFINED(p, n) do { (void)(p); (void)(n); } while (0)
#define VALGRIND_MAKE_MEM_DEFINED(p, n)   do { (void)(p); (void)(n); } while (0)
#define VALGRIND_MAKE_MEM_NOACCESS(p, n)  do { (void)(p); (void)(n); } while (0)
#ifndef ZERO_STRUCT
#define ZERO_STRUCT(x) memset((char *)&(x), 0, sizeof(x))
#endif
#ifndef discard_const
#define discard_const(ptr) ((void *)((uintptr_t)(ptr)))
#endif
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif
#define HAVE_CONSTRUCTOR_ATTRIBUTE 1
#endif /* REPLACE_H */
REPLACE
	# Build static libtalloc.a in src/ so proot links it
	"$CC" -c talloc.c -o talloc.o -I. -fPIC -O2 -Wall -std=gnu99 \
		-DHAVE_STDARG_H=1 -DHAVE_VA_COPY=1 -DHAVE_UNISTD_H=1 -DHAVE_INTPTR_T=1
	"$AR" rcs src/libtalloc.a talloc.o
}

termux_step_pre_configure() {
	CPPFLAGS+=" -DARG_MAX=131072 -DVERSION=\\\"${TERMUX_PKG_VERSION}\\\" -I$TERMUX_PKG_SRCDIR"
	export TALLOC_LIBS="$TERMUX_PKG_SRCDIR/src/libtalloc.a"
}

termux_step_post_make_install() {
	mkdir -p $TERMUX_PREFIX/share/man/man1
	install -m600 $TERMUX_PKG_SRCDIR/doc/proot/man.1 $TERMUX_PREFIX/share/man/man1/proot.1

	sed -e "s|@TERMUX_PREFIX@|$TERMUX_PREFIX|g" \
		$TERMUX_PKG_BUILDER_DIR/termux-chroot \
		> $TERMUX_PREFIX/bin/termux-chroot
	chmod 700 $TERMUX_PREFIX/bin/termux-chroot

	# Install package-name-agnostic artifacts for host apps:
	#   libproot.so          -> proot binary (rename so APK installs it into
	#                           nativeLibraryDir where SELinux allows exec)
	#   libproot-loader.so   -> 64-bit loader ELF (same reason)
	#   libproot-loader32.so -> 32-bit loader ELF (same reason)
	# Host app must set PROOT_LOADER / PROOT_LOADER_32 to its own
	# nativeLibraryDir paths at runtime. No package path is baked in.
	mkdir -p $TERMUX_PREFIX/lib/proot
	install -m755 $TERMUX_PKG_SRCDIR/src/proot $TERMUX_PREFIX/lib/proot/libproot.so
	if [ -f $TERMUX_PKG_SRCDIR/src/loader/loader ]; then
		install -m755 $TERMUX_PKG_SRCDIR/src/loader/loader $TERMUX_PREFIX/lib/proot/libproot-loader.so
	fi
	if [ -f $TERMUX_PKG_SRCDIR/src/loader/loader-m32 ]; then
		install -m755 $TERMUX_PKG_SRCDIR/src/loader/loader-m32 $TERMUX_PREFIX/lib/proot/libproot-loader32.so
	fi
}

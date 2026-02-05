#!/usr/bin/env bash

set -e

BUILD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BUILD_SCRIPT_DIR"

# Set default XORG_VER if not set
XORG_VER="${XORG_VER:-21.1.7}"

# Determine XORG_PATCH version
if [[ "${XORG_VER}" == 21* ]]; then
  XORG_PATCH=21
else
  XORG_PATCH=$(echo "$XORG_VER" | grep -Po '^\d.\d+' | sed 's#\.##')
fi

echo "Building KasmVNC..."
echo "===================="
echo "X.Org version: ${XORG_VER}"
echo "X.Org patch version: ${XORG_PATCH}"
echo ""

# Create temporary directory for downloads
TMPDIR="${TMPDIR:-.}/xorg-build-tmp"
mkdir -p "$TMPDIR"

# Download and extract X.Org server if not already done
if [ ! -d unix/xserver/include ]; then
  echo "Downloading X.Org server ${XORG_VER}..."
  TARBALL="xorg-server-${XORG_VER}.tar.gz"
  TARBALL_PATH="$TMPDIR/$TARBALL"
  
  if [ ! -f "$TARBALL_PATH" ]; then
    echo "Fetching $TARBALL from X.Org archives..."
    wget --no-check-certificate -O "$TARBALL_PATH" https://www.x.org/archive/individual/xserver/"$TARBALL"
  else
    echo "Using cached $TARBALL"
  fi
  
  echo "Extracting X.Org server..."
  tar -C unix/xserver -xf "$TARBALL_PATH" --strip-components=1
  
  # Restore hw/vnc directory from git (tarball extraction deletes it)
  echo "Restoring hw/vnc from git..."
  git restore unix/xserver/hw/vnc 2>/dev/null || echo "Note: git restore failed, hw/vnc may have local changes"
  git restore unix/xserver/.gitignore 2>/dev/null || echo "Note: git restore .gitignore failed"
fi

# Build KasmVNC
echo ""
echo "Building KasmVNC CMake project..."
# Append -Wno-format-security to existing flags
export CFLAGS="${CFLAGS:-} -Wno-format-security"
export CXXFLAGS="${CXXFLAGS:-} -Wno-format-security"
cmake -DCMAKE_BUILD_TYPE=Release . -DBUILD_VIEWER:BOOL=OFF -DENABLE_GNUTLS:BOOL=OFF
make -j"$(nproc)"

# Build X.Org server if not already built
if [ ! -f unix/xserver/hw/vnc/Xvnc ]; then
  echo ""
  echo "Building X.Org server..."
  cd unix/xserver
  
  # Apply patches
  echo "Applying xserver patches..."
  if [ -f "../xserver${XORG_PATCH}.patch" ]; then
    patch -Np1 --forward -i "../xserver${XORG_PATCH}.patch" || echo "Patch may have already been applied"
  fi
  
  # Additional patches for specific versions
  case "$XORG_VER" in
    1.20.*)
      if [ -f "../CVE-2022-2320-v1.20.patch" ]; then
        patch -s -p0 < ../CVE-2022-2320-v1.20.patch || true
      fi
      if [ -f "../xserver120.7.patch" ]; then
        patch -Np1 -i ../xserver120.7.patch || true
      fi
      ;;
    1.19.*)
      if [ -f "../CVE-2022-2320-v1.19.patch" ]; then
        patch -s -p0 < ../CVE-2022-2320-v1.19.patch || true
      fi
      ;;
  esac
  
  # Run autoreconf
  echo "Running autoreconf..."
  autoreconf -fi
  
  # Fix AM_INIT_AUTOMAKE for newer automake versions
  if grep -q 'AM_INIT_AUTOMAKE(\[foreign dist-xz\])' configure.ac 2>/dev/null; then
    echo "Fixing AM_INIT_AUTOMAKE..."
    sed -i 's/AM_INIT_AUTOMAKE(\[foreign dist-xz\])/AM_INIT_AUTOMAKE([foreign dist-xz subdir-objects])/' configure.ac
    autoreconf -fi
  fi
  
  # Configure X.Org with proper library flags
  echo "Configuring X.Org server..."
  LDFLAGS="${LDFLAGS:-} -lz -lpng -ltbb -ljpeg -lfmt -lcpuid" ./configure \
    --disable-config-hal \
    --disable-config-udev \
    --disable-dmx \
    --disable-dri \
    --disable-dri2 \
    --disable-kdrive \
    --disable-static \
    --disable-xephyr \
    --disable-xinerama \
    --disable-xnest \
    --disable-xorg \
    --disable-xvfb \
    --disable-xwayland \
    --disable-xwin \
    --enable-glx \
    --prefix=/opt/kasmweb \
    --with-default-font-path="/usr/share/fonts/X11/misc,/usr/share/fonts/X11/cyrillic,/usr/share/fonts/X11/100dpi/:unscaled,/usr/share/fonts/X11/75dpi/:unscaled,/usr/share/fonts/X11/Type1,/usr/share/fonts/X11/100dpi,/usr/share/fonts/X11/75dpi,built-ins" \
    --without-dtrace \
    --with-sha1=libcrypto \
    --with-xkb-bin-directory=/usr/bin \
    --with-xkb-output=/var/lib/xkb \
    --with-xkb-path=/usr/share/X11/xkb
  
  # Remove array bounds errors for new versions of GCC
  echo "Patching Makefiles to remove array bounds warnings..."
  find . -name "Makefile" -exec sed -i 's/-Werror=array-bounds//g' {} \;
  
  echo "Building X.Org server..."
  make -j"$(nproc)"
  cd ../..
fi

# Create build structure
echo ""
echo "Creating build structure..."
mkdir -p xorg.build/bin
mkdir -p xorg.build/lib
mkdir -p xorg.build/man/man1

cd xorg.build/bin/
ln -sfn ../../unix/xserver/hw/vnc/Xvnc Xvnc
cd ..

touch man/man1/Xserver.1
cp ../unix/xserver/hw/vnc/Xvnc.man man/man1/Xvnc.1 2>/dev/null || echo "Note: Xvnc.man not found"

cd lib
# Link to DRI directory for hardware acceleration
if [ -d /usr/lib/x86_64-linux-gnu/dri ]; then
  ln -sfn /usr/lib/x86_64-linux-gnu/dri dri
elif [ -d /usr/lib/aarch64-linux-gnu/dri ]; then
  ln -sfn /usr/lib/aarch64-linux-gnu/dri dri
elif [ -d /usr/lib/arm-linux-gnueabihf/dri ]; then
  ln -sfn /usr/lib/arm-linux-gnueabihf/dri dri
elif [ -d /usr/lib/xorg/modules/dri ]; then
  ln -sfn /usr/lib/xorg/modules/dri dri
elif [ -d /usr/lib64/dri ]; then
  ln -sfn /usr/lib64/dri dri
else
  echo "Warning: DRI directory not found, hardware acceleration may not work"
fi
cd ../..

# Create server tarball
if [ ! -d builder/www ]; then
  if [ -d kasmweb/dist ]; then
    echo "Copying kasmweb/dist to builder/www for tarball..."
    mkdir -p builder
    rm -rf builder/www
    cp -r kasmweb/dist builder/www
  else
    echo "builder/www not found; creating placeholder to allow tarball creation."
    mkdir -p builder/www
    echo "<html><body><h1>KasmVNC</h1><p>Web assets not built.</p></body></html>" > builder/www/index.html
  fi
fi

echo "Creating server tarball..."
make servertarball

echo ""
echo "Build complete!"
echo "===================="
echo "Tarball created: kasmvnc-*.tar.gz"
echo ""
echo "To test the built Xvnc server, you can run:"
echo "  mkdir -p ~/.vnc"
echo "  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ~/.vnc/self.pem -out ~/.vnc/self.pem -subj '/C=US/ST=VA/L=None/O=None/OU=DoFu/CN=kasm/emailAddress=none@none.none'"
echo "  ./xorg.build/bin/Xvnc -interface 0.0.0.0 -disableBasicAuth -Log *:stdout:100 -sslOnly 1 -cert ~/.vnc/self.pem -key ~/.vnc/self.pem :1"
echo ""
#!/usr/bin/env bash

set -e

echo "Building KasmVNC..."
echo ""

# Download and extract X.Org server if not already done
if [ ! -d unix/xserver/include ]; then
  echo "Downloading X.Org server ${XORG_VER}..."
  cd /tmp
  TARBALL="xorg-server-${XORG_VER}.tar.gz"
  if [ ! -f "$TARBALL" ]; then
    wget --no-check-certificate https://www.x.org/archive/individual/xserver/"$TARBALL"
  fi
  cd "$OLDPWD"
  
  echo "Extracting X.Org server..."
  tar -C unix/xserver -xf /tmp/xorg-server-${XORG_VER}.tar.gz --strip-components=1
  
  # Restore hw/vnc directory from git (tarball extraction deletes it)
  git restore unix/xserver/hw/vnc
  git restore unix/xserver/.gitignore
fi

# Build KasmVNC
echo "Building KasmVNC..."
export CFLAGS="-Wno-format-security"
export CXXFLAGS="-Wno-format-security"
cmake -DCMAKE_BUILD_TYPE=Release . -DBUILD_VIEWER:BOOL=OFF -DENABLE_GNUTLS:BOOL=OFF
make -j"$(nproc)"

# Build X.Org server if not already built
if [ ! -f unix/xserver/hw/vnc/Xvnc ]; then
  echo "Building X.Org server..."
  cd unix/xserver
  
  # Apply patches
  XORG_PATCH=21
  patch -Np1 --forward -i ../xserver"${XORG_PATCH}".patch || true
  
  # Fix AM_INIT_AUTOMAKE for newer automake versions
  sed -i 's/AM_INIT_AUTOMAKE(\[foreign dist-xz\])/AM_INIT_AUTOMAKE([foreign dist-xz subdir-objects])/' configure.ac
  
  autoreconf -vfi
  
  # Configure X.Org with proper library flags
  LDFLAGS="-lz -lpng -ltbb -ljpeg -lfmt -lcpuid" ./configure \
    --disable-config-hal \
    --disable-config-udev \
    --disable-dmx \
    --disable-dri \
    --disable-dri2 \
    --disable-kdrive \
    --disable-static \
    --disable-xephyr \
    --disable-xinerama \
    --disable-xnest \
    --disable-xorg \
    --disable-xvfb \
    --disable-xwayland \
    --disable-xwin \
    --enable-glx \
    --prefix=/opt/kasmweb \
    --with-default-font-path="/usr/share/fonts/X11/misc,/usr/share/fonts/X11/cyrillic,/usr/share/fonts/X11/100dpi/:unscaled,/usr/share/fonts/X11/75dpi/:unscaled,/usr/share/fonts/X11/Type1,/usr/share/fonts/X11/100dpi,/usr/share/fonts/X11/75dpi,built-ins" \
    --without-dtrace \
    --with-sha1=libcrypto \
    --with-xkb-bin-directory=/usr/bin \
    --with-xkb-output=/var/lib/xkb \
    --with-xkb-path=/usr/share/X11/xkb
  
  make -j"$(nproc)"
  cd ../..
fi

# Create build structure
echo "Creating build structure..."
mkdir -p xorg.build/bin
mkdir -p xorg.build/lib
mkdir -p xorg.build/man/man1

cd xorg.build/bin/
ln -sfn ../../unix/xserver/hw/vnc/Xvnc Xvnc
cd ..

touch man/man1/Xserver.1
cp ../unix/xserver/hw/vnc/Xvnc.man man/man1/Xvnc.1

cd lib
if [ -d /usr/lib/x86_64-linux-gnu/dri ]; then
  ln -sfn /usr/lib/x86_64-linux-gnu/dri dri
elif [ -d /usr/lib/aarch64-linux-gnu/dri ]; then
  ln -sfn /usr/lib/aarch64-linux-gnu/dri dri
elif [ -d /usr/lib/arm-linux-gnueabihf/dri ]; then
  ln -sfn /usr/lib/arm-linux-gnueabihf/dri dri
elif [ -d /usr/lib/xorg/modules/dri ]; then
  ln -sfn /usr/lib/xorg/modules/dri dri
else
  ln -sfn /usr/lib64/dri dri 2>/dev/null || true
fi
cd ../..

# Create server tarball
echo "Creating server tarball..."
make servertarball

echo ""
echo "Build complete! Tarball created: kasmvnc-*.tar.gz"

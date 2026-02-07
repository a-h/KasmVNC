{
  description = "KasmVNC";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # X.Org server dependencies
        xorgDeps = with pkgs.xorg; [
          xorgproto
          libX11
          libXau
          libXdmcp
          libXext
          libXfixes
          libXfont2
          libXi
          libXrender
          libXrandr
          libXcursor
          libxcb
          libxkbfile
          libxshmfence
          libXtst
          xkbcomp
          xtrans
          fontutil
          makedepend
        ];

        # Build dependencies
        buildDeps = with pkgs; [
          cmake
          ninja
          nasm
          pkg-config
          autoconf
          automake
          libtool
          quilt
          git
          wget
          util-macros  # From nixpkgs
        ];

        # Required libraries
        libraries = with pkgs; [
          gnutls
          libpng
          libtiff
          giflib
          ffmpeg
          openssl
          libva
          zlib
          bzip2
          pixman
          mesa
          libdrm
          libepoxy
          nettle
          libjpeg_turbo
          libwebp
          tbb
          libcpuid
          fmt
          libxcrypt
          libxcvt
          mesa-gl-headers
          libgbm
          fontconfig
          freetype
          libfontenc
          dbus
          xkeyboard-config
          docbook_xsl
          docbook_xml_dtd_45
        ];

        # Development tools
        devTools = with pkgs; [
          gcc14
          gnumake
          which
          file
          patchelf
          perl
          perlPackages.Switch
          openssh
          nodejs
        ];

        xorgVersion = "21.1.7";

        xorgServerTarball = pkgs.fetchurl {
          url = "https://www.x.org/archive/individual/xserver/xorg-server-${xorgVersion}.tar.gz";
          sha256 = "1gygpqancbcw9dd3wc168hna6a4n8cj16n3pm52kda3ygks0b40s";
        };

        # Build web assets (noVNC) as a separate derivation
        kasmvncWeb = pkgs.buildNpmPackage {
          pname = "kasmvnc-www";
          version = "1.3.4";

          src = pkgs.fetchFromGitHub {
            owner = "kasmtech";
            repo = "noVNC";
            rev = "v1.3.0";
            sha256 = "sha256-NS0vE+YG0CR6RgJhOruO0UDGgMYICPuVzbmWM7mcKXY=";
          };

          npmDepsHash = "sha256-2doaGFuJsHwuXQ0RwiibBdZMIAazDlIjlV7ECc4Mwk0=";
          npmFlags = [ "--include=dev" "--legacy-peer-deps" "--ignore-scripts" ];
          npmBuild = "npm run build";
          NODE_OPTIONS = "--openssl-legacy-provider";

          installPhase = ''
            mkdir -p $out
            # Copy everything from source (app/, vendor/, vnc.html, etc.)
            cp -r . $out/
            # Also copy dist/ contents if they exist to ensure all bundles are present
            [ -d dist ] && cp -r dist/* $out/
          '';

          meta = with pkgs.lib; {
            description = "KasmVNC web client assets";
            homepage = "https://github.com/kasmtech/noVNC";
            license = licenses.mpl20;
            platforms = platforms.linux;
          };
        };

        kasmvncDerivation = pkgs.stdenv.mkDerivation {
          pname = "kasmvnc";
          version = "1.3.4";

          src = pkgs.lib.cleanSource ./.;
          stdenv = pkgs.gcc14Stdenv;

          nativeBuildInputs = buildDeps ++ devTools ++ [ pkgs.makeWrapper ];
          buildInputs = xorgDeps ++ libraries;

          XORG_VER = xorgVersion;
          KASMVNC_BUILD_OS = "nixos";
          KASMVNC_BUILD_OS_CODENAME = "nixos";
          XORG_TARBALL_PATH = xorgServerTarball;
          MESA_DRI_DRIVERS = "${pkgs.mesa}/lib/dri";
          KASMVNC_WEB_DIST = kasmvncWeb;

          dontConfigure = true;

          preBuild = ''
            # Copy pre-built web assets to both kasmweb/dist and builder/www
            echo "Copying web assets from ${kasmvncWeb}..."
            mkdir -p kasmweb/dist builder/www
            cp -r --no-preserve=mode,ownership ${kasmvncWeb}/* kasmweb/dist/
            cp -r --no-preserve=mode,ownership ${kasmvncWeb}/* builder/www/
            chmod -R u+rwX kasmweb/dist builder/www
            echo "Web assets copied successfully"
            ls -la kasmweb/dist/ | head -20
            ls -la builder/www/ | head -20
          '';

          buildPhase = ''
            runHook preBuild
            bash ./build.sh
            runHook postBuild
          '';

          installPhase = ''
            mkdir -p "$out"
            tarball=$(ls -1 kasmvnc-*.tar.gz | head -n1)
            if [ -z "$tarball" ]; then
              echo "No kasmvnc tarball produced" >&2
              exit 1
            fi
            tar -xzf "$tarball" -C "$out"
            if [ -d "$out/usr/local" ]; then
              mv "$out/usr/local"/* "$out"/
              rmdir "$out/usr/local" || true
              rmdir "$out/usr" || true
            fi
            if [ -x "$out/bin/Xvnc" ]; then
              mv "$out/bin/Xvnc" "$out/bin/Xvnc.real"
              makeWrapper "$out/bin/Xvnc.real" "$out/bin/Xvnc" \
                --set XKB_COMP "${pkgs.xorg.xkbcomp}/bin/xkbcomp" \
                --set XKB_CONFIG_ROOT "${pkgs.xkeyboard-config}/share/X11/xkb"
            fi
          '';

          meta = with pkgs.lib; {
            description = "KasmVNC server and web client";
            homepage = "https://github.com/kasmtech/KasmVNC";
            license = licenses.gpl2Plus;
            platforms = platforms.linux;
          };
        };

      in
      {
        packages.kasmvnc-www = kasmvncWeb;
        # After building, you can run the server with:
        # ./result/bin/Xvnc -interface 0.0.0.0 -disableBasicAuth -Log '*:stdout:100' -sslOnly 0 -httpd ./result/share/kasmvnc/www :1
        # Then access the web client http://localhost:6800
        packages.kasmvnc = kasmvncDerivation;
        packages.default = kasmvncDerivation;

        devShells.default = pkgs.mkShell {
          stdenv = pkgs.gcc14Stdenv;
          buildInputs = xorgDeps ++ buildDeps ++ libraries ++ devTools;

          shellHook = ''
            echo "KasmVNC development environment"
            echo "================================"
            echo ""
            echo "Run './build.sh' to build KasmVNC"
            echo "To build web assets: cd kasmweb && npm install && npm run build"
            echo ""

            # Set environment variables
            export XORG_VER="21.1.7"
            export MAKEFLAGS="-j$(nproc)"
            export KASMVNC_BUILD_OS="nixos"
            export KASMVNC_BUILD_OS_CODENAME="nixos"

            # Use a newer GCC to satisfy libstdc++ symbols required by oneTBB
            export CC="${pkgs.gcc14}/bin/gcc"
            export CXX="${pkgs.gcc14}/bin/g++"
            
            # Ensure pkg-config can find all libraries
            export PKG_CONFIG_PATH="${pkgs.lib.makeSearchPath "lib/pkgconfig" (libraries ++ xorgDeps)}:$PKG_CONFIG_PATH"
            
            # Set library path
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (libraries ++ xorgDeps)}:$LD_LIBRARY_PATH"
            
            # Set linker flags
            export LDFLAGS="-L${pkgs.lib.makeLibraryPath (libraries ++ xorgDeps)} $LDFLAGS"
            
            # Set compiler flags to find headers
            export CFLAGS="-I${pkgs.lib.makeSearchPath "include" (libraries ++ xorgDeps)} -Wno-format-security $CFLAGS"
            export CXXFLAGS="-I${pkgs.lib.makeSearchPath "include" (libraries ++ xorgDeps)} -Wno-format-security $CXXFLAGS"

            # Ensure git uses Nix-provided ssh (avoids system GLIBC mismatch)
            export GIT_SSH="${pkgs.openssh}/bin/ssh"
            export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh"
            
            # Set CMake policy for modern CMake versions on nixos-unstable
            export CMAKE_POLICY_DEFAULT_CMP0022=NEW
            export CMAKE_POLICY_DEFAULT_CMP0048=NEW
          '';
        };
      }
    );
}

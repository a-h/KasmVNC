{
  description = "KasmVNC development environment";

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

        # util-macros from https://github.com/NixOS/nixpkgs/blob/408852040c85566581528ecadf661e2c04037ac7/pkgs/top-level/aliases.nix#L2138
        util-macros = pkgs.stdenv.mkDerivation (finalAttrs: {
          pname = "util-macros";
          version = "1.20.2";

          src = pkgs.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            group = "xorg";
            owner = "util";
            repo = "macros";
            rev = "util-macros-${finalAttrs.version}";
            hash = "sha256-COIWe7GMfbk76/QUIRsN5yvjd6MEarI0j0M+Xa0WoKQ=";
          };

          strictDeps = true;

          nativeBuildInputs = [ pkgs.autoreconfHook ];

          passthru = {
            tests.pkg-config = pkgs.testers.testMetaPkgConfig finalAttrs.finalPackage;
            updateScript = pkgs.gitUpdater {
              rev-prefix = "util-macros-";
              ignoredVersions = "1_0_2";
            };
          };

          meta = {
            description = "GNU autoconf macros shared across X.Org projects";
            homepage = "https://gitlab.freedesktop.org/xorg/util/macros";
            license = with pkgs.lib.licenses; [
              hpndSellVariant
              mit
            ];
            maintainers = with pkgs.lib.maintainers; [
              raboof
              jopejoe1
            ];
            pkgConfigModules = [ "xorg-macros" ];
            platforms = pkgs.lib.platforms.unix;
          };
        });

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
          util-macros
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
        ];

      in
      {
        devShells.default = pkgs.mkShell {
          stdenv = pkgs.gcc14Stdenv;
          buildInputs = xorgDeps ++ buildDeps ++ libraries ++ devTools;

          shellHook = ''
            echo "KasmVNC development environment"
            echo "================================"
            echo ""
            echo "Run './build.sh' to build KasmVNC"
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
            
            # Set CMake policy for modern CMake versions on nixos-unstable
            export CMAKE_POLICY_DEFAULT_CMP0022=NEW
            export CMAKE_POLICY_DEFAULT_CMP0048=NEW
          '';
        };
      }
    );
}

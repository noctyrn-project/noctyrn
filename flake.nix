{
  description = "Noctyrn - Tactical FPS Game (workspace)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [
            "x86_64-unknown-linux-gnu"
            "x86_64-pc-windows-gnu"
            "wasm32-unknown-unknown"
          ];
        };
      in
      {
        devShells.default = pkgs.mkShell rec {
          nativeBuildInputs = with pkgs; [
            rustToolchain
            pkg-config
            cmake
            mold
            zip
          ];

          buildInputs = with pkgs; [
            # Server dependencies
            postgresql.lib
            openssl

            # Bevy engine dependencies
            udev
            alsa-lib
            vulkan-loader
            libx11
            libxcursor
            libxi
            libxrandr
            wayland
            libxkbcommon
          ];

          NOCTYRN_WINDOWS_DEPS = with pkgs.pkgsCross.mingwW64; [
            stdenv.cc
            windows.pthreads
          ];

          NOCTYRN_WINDOWS_LDPATH = "${pkgs.pkgsCross.mingwW64.windows.pthreads}/lib";


          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;

          # Server configuration defaults
          DATABASE_URL = "postgres://noctyrn:noctyrn@localhost:5432/noctyrn";
          JWT_SECRET = "dev-secret-change-in-production";
          HTTP_PORT = "8080";
          TCP_PORT = "7878";
          UDP_PORT = "7877";
          BIND_ADDR = "0.0.0.0";

          RUST_BACKTRACE = 1;

          shellHook = ''
            echo "Noctyrn development shell loaded"
            echo "  DATABASE_URL=$DATABASE_URL"
            echo "  Server ports: HTTP=$HTTP_PORT TCP=$TCP_PORT UDP=$UDP_PORT"
          '';
        };
      });
}

{ system ? builtins.currentSystem
, crossSystem ? null
, config ? { }
, overlays ? [ ]
, sourcesOverride ? { }
, sources
, isInFlake
, haskellNix
, checkMaterialization ? false
, enableHaskellProfiling ? false
}:
let
  ownOverlays =
    [
      # Modifications to derivations from nixpkgs
      (import ./overlays/nixpkgs-overrides.nix)
      # fix r-modules
      (import ./overlays/r.nix)
    ];

  iohkNixMain = import sources.iohk-nix { };

  # haskell-nix has to be used differently in flakes/no-flakes scenarios:
  # - When imported from flakes, 'haskellNix.overlay' needs to be passed here.
  # - When imported from default.nix without flakes, default to haskellNix.overlays
  haskellNixOverlays = if isInFlake then [ haskellNix.overlay ] else haskellNix.overlays;

  # haskell-nix provides some global config settings but it's exposed under different
  # attribute paths when imported as flake/non-flake.
  haskellNixConfig = if isInFlake then haskellNix.internal.config else haskellNix.config;

  extraOverlays =
    # Haskell.nix (https://github.com/input-output-hk/haskell.nix)
    haskellNixOverlays
    # our own overlays:
    # needed for cardano-api wich uses a patched libsodium
    ++ iohkNixMain.overlays.crypto
    ++ ownOverlays;

  pkgs = import sources.nixpkgs {
    inherit system crossSystem;
    overlays = extraOverlays ++ overlays;
    config = haskellNixConfig // config;
  };

  nativePkgs = import sources.nixpkgs {
    overlays = extraOverlays ++ overlays;
    config = haskellNix.config // config;
  };

  ghcjsPluginPkgs = if system == builtins.currentSystem && !pkgs.stdenv.hostPlatform.isGhcjs
                    then null
                    else import ./pkgs {
      pkgs = nativePkgs;
      inherit checkMaterialization enableHaskellProfiling sources;
#      -- packages: ${pkgs.pkgsCross.ghcjs.buildPackages.haskell-nix.compiler.${compiler-nix-name}.configured-src}
      cabalProjectLocal = ''

      source-repository-package
        type: git
        location: https://github.com/ghcjs/ghcjs.git
        tag: 6f20f45e384e4907cbf11ec7c258e456c4f0f4d7
        --sha256: 098n3nabc9dgsfh0mznpkaxhbwmsp5rx5wcvx4411k631lglkyk2

      allow-newer: ghcjs:base16-bytestring
                 , ghcjs:aeson
                 , stm:base
                 , cardano-binary:recursion-schemes
                 , jsaddle:ghcjs-base
                 , ghcjs-base:primitive
                 , ghcjs-base:time
                 , ghcjs-base:hashable
                 , ghcjs-base:aeson
                 , servant-foreign:lens
                 , servant-client:http-client
      constraints: plutus-tx +ghcjs-plugin


      package plutus-tx
        flags: +ghcjs-plugin

      -- The following is needed because Nix is doing something crazy.
      package byron-spec-ledger
        tests: False

      package marlowe
        tests: False

      package plutus-doc
        tests: False

      package prettyprinter-configurable
        tests: False

      package small-steps
        tests: False

      package small-steps-test
        tests: False

      package byron-spec-chain
        tests: False

    '';
  };
  plutus = import ./pkgs { inherit pkgs checkMaterialization enableHaskellProfiling sources ghcjsPluginPkgs; };

in
{
  inherit pkgs ghcjsPluginPkgs plutus sources;
}

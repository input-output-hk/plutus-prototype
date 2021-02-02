{ stdenv
, nodejs
, easyPS
}:

{ pkgs
  # path to project sources
, src
  # name of the project
, name
  # packages as generated by psc-pacakge2nix
, packages
  # spago packages as generated by spago2nix
, spagoPackages
  # a map of source directory name to contents that will be symlinked into the environment before building
, extraSrcs ? { }
  # node_modules to use
, nodeModules
  # control execution of unit tests
, checkPhase
}:
let
  addExtraSrc = k: v: "ln -sf ${v} ${k}";
  addExtraSrcs = builtins.concatStringsSep "\n" (builtins.attrValues (pkgs.lib.mapAttrs addExtraSrc extraSrcs));
  extraPSPaths = builtins.concatStringsSep " " (map (d: "${d}/**/*.purs") (builtins.attrNames extraSrcs));
in
stdenv.mkDerivation {
  inherit name src checkPhase;
  buildInputs = [
    nodejs
    nodeModules
    easyPS.purs
    easyPS.spago
    easyPS.psc-package
    spagoPackages.installSpagoStyle
    spagoPackages.buildSpagoStyle
  ];
  buildPhase = ''
    export HOME=$NIX_BUILD_TOP
    shopt -s globstar
    ln -s ${nodeModules}/node_modules node_modules
    ${addExtraSrcs}

    install-spago-style
    build-spago-style src/**/*.purs test/**/*.purs ${extraPSPaths}
    npm run webpack
  '';
  doCheck = true;
  installPhase = ''
    mv dist $out
  '';
}

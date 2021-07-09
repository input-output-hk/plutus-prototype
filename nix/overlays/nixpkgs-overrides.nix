self: super: {
  morph = super.morph.overrideAttrs (old: {
    # See https://github.com/DBCDK/morph/pull/141
    # Note that this patch does refelct the original content
    # of the PR above since it was broken.
    patches = [ ../pkgs/morph/sshopts.patch ];
    src = self.fetchFromGitHub {
      owner = "DBCDK";
      repo = "morph";
      rev = "c048d6339f18613a1544bc62ff852cb4c6de1042";
      sha256 = "0yb8prji2nqjsj1aiiqnbqaajbi5l17rg8k78ry7pl3a8sqa3h1x";
    };
  });

  python3 = super.python3.override {
    packageOverrides = python-self: python-super: {
      # New version has much better citation styles
      sphinxcontrib-bibtex = python-super.sphinxcontrib-bibtex.overrideAttrs (oldAttrs: rec {
        version = "2.2.0";
        src = python-super.fetchPypi {
          inherit (oldAttrs) pname;
          inherit version;
          sha256 = "1cp3dj5bbl122d64i3vbqhjhfplnh1rwm9dw4cy9hxjd2lz8803m";
        };
      });
    };
  };
} // super.lib.optionalAttrs (super.stdenv.targetPlatform.isGhcjs) {
  # Add config.sub and config.guess files that know about ghcjs
  gnu-config = ./gnu-config;
}
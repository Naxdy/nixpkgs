{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  git,
  bash,
  coreutils,
  compressDrvWeb,
  gzip,
  openssh,
  sqliteSupport ? true,
  nixosTests,
  stdenv,
  nodejs,
  pnpm,
}:
buildGoModule (
  finalAttrs:
  let
    version = "1.25.0-rc0";

    tags = lib.optionals sqliteSupport [
      "sqlite"
      "sqlite_unlock_notify"
    ];

    frontend = stdenv.mkDerivation {
      pname = "gitea-frontend";
      inherit (finalAttrs.finalPackage) src version;

      pnpmDeps = pnpm.fetchDeps {
        pname = "gitea-frontend-deps";
        inherit (finalAttrs.finalPackage) src version;
        fetcherVersion = 2;
        hash = "sha256-0p7P68BvO3hv0utUbnPpHSpGLlV7F9HHmOITvJAb/ww=";
      };

      nativeBuildInputs = [
        nodejs
        pnpm.configHook
      ];

      # use webpack directly instead of 'make frontend' as the packages are already installed
      buildPhase = ''
        BROWSERSLIST_IGNORE_OLD_DATA=true pnpm exec webpack --disable-interpret
      '';

      installPhase = ''
        mkdir -p $out
        cp -R public $out/
      '';
    };
  in
  {
    pname = "gitea";
    inherit version;

    src = fetchFromGitHub {
      owner = "go-gitea";
      repo = "gitea";
      tag = "v${version}";
      hash = "sha256-20nbchJkUzkdMxWl7rdJbxCYHlNp7b605vvw2DFeMWc=";
    };

    proxyVendor = true;

    vendorHash = "sha256-S0hnmPzLPTw+uLelOkVKz/MuUD00eDolb+DqtItKft8=";

    outputs = [
      "out"
      "data"
    ];

    patches = [ ./static-root-path.patch ];

    # go-modules derivation doesn't provide $data
    # so we need to wait until it is built, and then
    # at that time we can then apply the substituteInPlace
    overrideModAttrs = _: { postPatch = null; };

    postPatch = ''
      substituteInPlace modules/setting/server.go --subst-var data
    '';

    subPackages = [ "." ];

    nativeBuildInputs = [ makeWrapper ];

    inherit tags;

    ldflags = [
      "-s"
      "-w"
      "-X main.Version=${version}"
      "-X 'main.Tags=${lib.concatStringsSep " " tags}'"
    ];

    postInstall = ''
      mkdir $data
      ln -s ${frontend}/public $data/public
      cp -R ./{templates,options} $data
      mkdir -p $out
      cp -R ./options/locale $out/locale

      wrapProgram $out/bin/gitea \
        --prefix PATH : ${
          lib.makeBinPath [
            bash
            coreutils
            git
            gzip
            openssh
          ]
        }
    '';

    passthru = {
      data-compressed =
        lib.warn "gitea.passthru.data-compressed is deprecated. Use \"compressDrvWeb gitea.data\"."
          (compressDrvWeb finalAttrs.finalPackage.data { });

      tests = nixosTests.gitea;
    };

    meta = {
      description = "Git with a cup of tea";
      homepage = "https://about.gitea.com";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [
        techknowlogick
        SuperSandro2000
      ];
      mainProgram = "gitea";
    };
  }
)

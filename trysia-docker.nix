{ pkgs ? import <nixpkgs> {} }:

let
  sia = pkgs.buildGoPackage rec {
    name = "sia-${version}";
    version = "1.5.5";
    goPackagePath = "gitlab.com/NebulousLabs/Sia";

    src = pkgs.fetchgit {
      url = "https://${goPackagePath}";
      rev = "refs/tags/v${version}";
      sha256 = "1gl4gcg3z8r4mnpkgrmavrc0vk7iryq8vlm0jrpf2nlz8s2095gy";
      leaveDotGit = true;
    };

    goDeps = ./deps.nix;  # create with vgo2nix in Sia repository

    buildPhase = ''
      cd ./go/src/gitlab.com/NebulousLabs/Sia
      # We just did a clean checkout, but the Makefile will
      # not recognize this correctly, so clear GIT_DIRTY manually.
      sed -i 's/^GIT_DIRTY=.*$/GIT_DIRTY=/' Makefile
      patch -p1 < ${./force-contract-maintenance.patch}
      patch -p1 < ${./ignore-initial-scan-status.patch}
      patch -p1 < ${./small-ephemeral-accounts}
      export PATH=$PATH:${pkgs.git}/bin
      make
    '';

    meta = {
      homepage = "http://sia.tech/";
      description = "Blockchain-based marketplace for file storage";
      license = pkgs.lib.licenses.mit;
    };
  };

  sia-debug = pkgs.buildGoPackage rec {
    name = "sia-${version}";
    version = "1.5.5";
    goPackagePath = "gitlab.com/NebulousLabs/Sia";

    src = pkgs.fetchgit {
      url = "https://${goPackagePath}";
      rev = "refs/tags/v${version}";
      sha256 = "1gl4gcg3z8r4mnpkgrmavrc0vk7iryq8vlm0jrpf2nlz8s2095gy";
      leaveDotGit = true;
    };

    goDeps = ./deps.nix;  # create with vgo2nix in Sia repository

    buildPhase = ''
      cd ./go/src/gitlab.com/NebulousLabs/Sia
      # We just did a clean checkout, but the Makefile will
      # not recognize this correctly, so clear GIT_DIRTY manually.
      sed -i 's/^GIT_DIRTY=.*$/GIT_DIRTY=/' Makefile
      patch -p1 < ${./force-contract-maintenance.patch}
      patch -p1 < ${./ignore-initial-scan-status.patch}
      patch -p1 < ${./small-ephemeral-accounts}
      export PATH=$PATH:${pkgs.git}/bin
      make debug
    '';

    meta = {
      homepage = "http://sia.tech/";
      description = "Blockchain-based marketplace for file storage";
      license = pkgs.lib.licenses.mit;
    };
  };

  sia-bootstrap = pkgs.buildGoModule rec {
    name = "sia-bootstrap-${version}";
    version = "0.0.1";
    goPackagePath = "github.com/javgh/sia-bootstrap";

    src = pkgs.fetchgit {
      url = "https://${goPackagePath}";
      rev = "4ad6d55813858209420e47b75745568e8ae70b41";
      sha256 = "1prbgyrr944acdnrf2jkpsxmygqp71zy6nxrgxpmaciincad5apf";
    };

    vendorSha256 = "1acair9j4czgbbmryc98azb7fgnfy9h4f3akyjqcwd87pxn5jmp1";
  };

  set-demo-allowance = pkgs.buildGoModule rec {
    name = "set-demo-allowance-${version}";
    version = "0.0.1";

    src = ./set-demo-allowance;

    vendorSha256 = "1bbqwn24q42jgwc49r8ziwz1hjhqy671yi5fy4mig35il8ci8kdy";
  };

  sia-bootstrap-config = pkgs.writeText "config" ''
    consensus_location = "./consensus/consensus.db"
    consensus_bootstrap = "https://siastats.info/bootstrap/bootstrap.zip"
    ensure_wallet_initialized = true
    wallet_password = "password"
    ensure_wallet_unlocked = true
  '';

  start-siad = pkgs.writeScriptBin "start-siad" ''
    #!${pkgs.runtimeShell}
    mkdir -p /consensus
    mkdir -p /renter
    mkdir -p /gateway
    if [ ! -e /consensus/consensus.db ]; then
      curl http://135.181.164.108:8081/consensus.db -o /consensus/consensus.db
      curl http://135.181.164.108:8081/hostdb.json -o /renter/hostdb.json
      curl http://135.181.164.108:8081/nodes.json -o /gateway/nodes.json
    fi
    if [ -e /DEBUG ]; then
      exec ${sia-debug}/bin/siad -M gctwr --api-addr "0.0.0.0:9980" --disable-api-security
    else
      exec siad -M gctwr --api-addr "0.0.0.0:9980" --disable-api-security
    fi
  '';

  post-siad = pkgs.writeScriptBin "post-siad" ''
    #!${pkgs.runtimeShell}
    sia-bootstrap post
    if [ "$TRYSIA_PARENT" != "1" ] && [ "$TRYSIA_CHILD" != "1" ]; then
      ${set-demo-allowance}/bin/set-demo-allowance
    fi
  '';

  supervisord-config = pkgs.writeText "supervisord.conf" ''
    [supervisord]
    nodaemon = true
    user = root
    loglevel = warn
    logfile = /supervisord/supervisord.log
    pidfile = /supervisord/supervisord.pid
    directory = /supervisord

    [program:siad]
    command = ${start-siad}/bin/start-siad
    redirect_stderr = true
    autorestart = true
    startsecs = 5
    stopwaitsecs = 300
    stdout_logfile = /dev/stdout
    stdout_logfile_maxbytes = 0

    [program:sia-bootstrap]
    command = ${post-siad}/bin/post-siad
    redirect_stderr = true
    startsecs = 5
    stopwaitsecs = 300
    stdout_logfile = /dev/stdout
    stdout_logfile_maxbytes = 0
  '';

  start-script = pkgs.writeScriptBin "start" ''
    #!${pkgs.runtimeShell}
    mkdir -p .config/sia-bootstrap
    cp ${sia-bootstrap-config} .config/sia-bootstrap/config
    mkdir -p .sia
    echo "password" > .sia/apipassword
    echo "root:x:0:0:System administrator:/:/bin/bash" > /etc/passwd
    mkdir -p supervisord
    exec supervisord -c ${supervisord-config}
  '';
in pkgs.dockerTools.buildImage {
  name = "trysia";
  tag = "parent";
  contents = [
    pkgs.bashInteractive
    pkgs.cacert
    pkgs.coreutils
    pkgs.curl
    pkgs.procps
    pkgs.python3Packages.supervisor
    sia
    sia-bootstrap
    start-script
  ];
  config = {
    Cmd = ["start"];
  };
}

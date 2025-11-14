{
  description = "Nixinate your systems";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs, ... }@inputs:
    let
      version = builtins.substring 0 8 self.lastModifiedDate;
      supportedSystems = nixpkgs.lib.systems.flakeExposed;
      forSystems = systems: f:
        nixpkgs.lib.genAttrs systems
        (system: f system nixpkgs.legacyPackages.${system});
      forAllSystems = forSystems supportedSystems;
      nixpkgsFor = forAllSystems (system: pkgs: import nixpkgs { inherit system; overlays = [ self.overlays.default ]; });
    in rec
    {
      lib.genDeploy = forAllSystems (system: pkgs: nixpkgsFor.${system}.generateApps);
      overlays.default = final: prev: {
        nixinate = {
          nix = prev.pkgs.writeShellScriptBin "nix"
            ''${final.nixVersions.latest}/bin/nix --experimental-features "nix-command flakes" "$@"'';
          nixos-rebuild = prev.nixos-rebuild.override { inherit (final) nix; };
        };
        generateApps = flake:
          let
            machines = builtins.attrNames flake.nixosConfigurations;
            validMachines = final.lib.remove "" (final.lib.forEach machines (x: final.lib.optionalString (flake.nixosConfigurations."${x}"._module.args ? nixinate) "${x}" ));
            mkDeployScript = { machine }: let
              inherit (builtins) abort;
              inherit (final.lib) getExe optionalString concatStringsSep;
              nix = "${getExe final.nix}";
              nixos-rebuild = "${getExe final.nixos-rebuild}";
              openssh = "${getExe final.openssh}";
              flock = "${final.flock}/bin/flock";
              lolcat = "${getExe final.lolcat} -a -p 0.1";
              n = flake.nixosConfigurations.${machine}._module.args.nixinate;
              hermetic = n.hermetic or true;
              user = if (n ? sshUser && n.sshUser != null) then n.sshUser else throw "sshUser must be set in _module.args.nixinate";
              host = n.host;
              debug = if (n ? debug && n.debug) then "set -x;" else "";
              port = toString (n.port or 22);
              where = n.buildOn or "local";
              remote = if where == "remote" then true else if where == "local" then false else abort "_module.args.nixinate.buildOn is not either 'local' or 'remote'";
              substituteOnTarget = n.substituteOnTarget or false;
              nixOptions = concatStringsSep " " (n.nixOptions or []);
              header = ''
                  set -e
                  sw=''${1:-test}
                  echo "Deploying nixosConfigurations.${machine} from ${flake} | ${lolcat}"
                  echo "SSH Target: ${user}@${host}"
                  echo "SSH Port: ${port}"
                  echo "Rebuild Command: $sw"
                '';

                remoteCopy = if remote then ''
                  echo "Sending flake to ${machine} via nix copy:"
                  ( ${debug} NIX_SSHOPTS="-p ${port}" ${nix} ${nixOptions} copy ${flake} --to ssh://${user}@${host} )
                '' else "";

                hermeticActivation = if hermetic then ''
                  echo "Activating configuration hermetically on ${machine} via ssh:"
                              ( ${debug} NIX_SSHOPTS="-p ${port}" ${nix} ${nixOptions} copy --derivation ${nixos-rebuild} ${flock} --to ssh://${user}@${host} )
                              ( ${debug} ${openssh} -p ${port} -t ${user}@${host} "sudo nix-store --realise ${nixos-rebuild} ${flock} && sudo ${flock} -w 60 /dev/shm/nixinate-${machine} ${nixos-rebuild} ${nixOptions} $sw --flake ${flake}#${machine}" )
                '' else ''
                  echo "Activating configuration non-hermetically on ${machine} via ssh:"
                  ( ${debug} ${openssh} -p ${port} -t ${user}@${host} "sudo flock -w 60 /dev/shm/nixinate-${machine} nixos-rebuild $sw --flake ${flake}#${machine}" )
                '';

                activation = if remote then remoteCopy + hermeticActivation else ''
                  echo "Building system closure locally, copying it to remote store and activating it:"
                  ( ${debug} NIX_SSHOPTS="-t -p ${port}" ${flock} -w 60 /dev/shm/nixinate-${machine} ${nixos-rebuild} ${nixOptions} $sw --flake ${flake}#${machine} --target-host ${user}@${host} --use-remote-sudo ${optionalString substituteOnTarget "-s"} )             
                '';

                script = header + activation;
            in final.writeShellScriptBin "deploy-${machine}.sh" script;
          in
          nixpkgs.lib.genAttrs
            validMachines (x:
            {
                type = "app";
                meta = {
                  description = "Deployment Application for $x";
                };
                program = nixpkgs.lib.getExe (mkDeployScript { machine = x; });
              });
        };
    };
}

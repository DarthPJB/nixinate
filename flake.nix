{
  description = "Nixinate your systems";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs, ... }:
    let
      # some basic carte-blance tooling to handle valid archtectures.
      version = builtins.substring 0 8 self.lastModifiedDate;
      # this is still better than flake-utils, long game wins.
      forSystems = systems: f:
        nixpkgs.lib.genAttrs systems
        (system: f system nixpkgs.legacyPackages.${system});
      #  If you need to shim in your alien-nixpkgs-overlays override flakeExposed in the input nixpkgs follows packageset; not here. 
      forAllSystems = forSystems nixpkgs.lib.systems.flakeExposed;
      nixpkgsFor = forAllSystems (system: pkgs: import nixpkgs { inherit system; overlays = [ self.overlays.default ]; });
    in rec
    {
      lib.genDeploy = forAllSystems (system: pkgs: nixpkgsFor.${system}.generateApps);
      overlays.default = final: prev:
        let
          hasNg = final.lib.hasAttr "nixos-rebuild-ng" prev;
          rebuildCandidate = if hasNg then prev.nixos-rebuild-ng else prev.nixos-rebuild;
        in {
        nixinate = {
          nix = prev.pkgs.writeShellScriptBin "nix"
            ''${final.nixVersions.latest}/bin/nix --experimental-features "nix-command flakes" "$@"''; #TODO: appropriately allow passing of nix-version per-machine
          nixos-rebuild = rebuildCandidate.override { inherit (final) nix; };
        };
        generateApps = flake:
          let
            machines = builtins.attrNames flake.nixosConfigurations;
            validMachines = final.lib.remove "" (final.lib.forEach machines (x: final.lib.optionalString (flake.nixosConfigurations."${x}"._module.args ? nixinate) "${x}" ));
            mkDeployScript = { machine }: let
              inherit (final.lib) getExe getExe' optionalString concatStringsSep escapeShellArg elem;
              nix = "${getExe final.nix}";
              nixos-rebuild = "${getExe final.nixos-rebuild}";
              openssh = "${getExe final.openssh} -p ${port} -t ${safe_target_host}";
              lolcat_cmd = "${getExe final.lolcat} -p 3 -F 0.02";
              figlet_cmd = "${getExe final.figlet}";
              sem = "${getExe' final.parallel "sem"} --will-cite --line-buffer";
              safe_flake = escapeShellArg flake;
              safe_nixos_rebuild = escapeShellArg "${getExe final.nixos-rebuild}";
              safe_parallel = escapeShellArg "${getExe' final.parallel "sem"}";
              buildersOption = "--option builders ''";
              parameters = flake.nixosConfigurations.${machine}._module.args.nixinate;
              targetSystem = flake.nixosConfigurations.${machine}.config.nixpkgs.system;
              deployerSystem = final.system;
              isCrossArch = deployerSystem != targetSystem;
              hermetic = if isCrossArch then false else (parameters.hermetic or true);
              user = if (parameters ? sshUser && parameters.sshUser != null) then parameters.sshUser else (builtins.abort "sshUser must be set in _module.args.nixinate");
              host = if parameters ? host then parameters.host else builtins.abort "host must be set in _module.args.nixinate";
              debug = if (parameters ? debug && parameters.debug) then "set -x;" else "";
              where = if parameters ? buildOn then (if elem parameters.buildOn ["local" "remote"] then parameters.buildOn else builtins.abort "_module.args.nixinate.buildOn must be 'local' or 'remote'") else "local";
              nixOptionsList = if parameters ? nixOptions then (if builtins.isList parameters.nixOptions then (if builtins.all builtins.isString parameters.nixOptions then parameters.nixOptions else builtins.abort "_module.args.nixinate.nixOptions must be a list of strings") else builtins.abort "_module.args.nixinate.nixOptions must be a list") else [];
              port = toString (parameters.port or 22);
              target = "${flake}#${machine}";
              target_host = "${user}@${host}";
              ssh_uri = "ssh://${target_host}";
              safe_target = escapeShellArg target;
              safe_target_host = escapeShellArg target_host;
              safe_ssh_uri = escapeShellArg ssh_uri;
              logFile = "/tmp/deploy-${machine}.log";
              ssh_options = "NIX_SSHOPTS=\"-p ${port}\"";
              hermeticOpensshCmd = ''sudo nix-store --realise ${safe_nixos_rebuild} --realise ${safe_parallel} && sudo ${sem} --id "nixinate-${machine}" --semaphore-timeout 60 --fg "${safe_nixos_rebuild} ${nixOptions} $sw --flake ${safe_target}"'';
              nonHermeticOpensshCmd = ''sudo ${sem} --id "nixinate-${machine}" --semaphore-timeout 60 --fg "${safe_nixos_rebuild} ${nixOptions} $sw --flake ${safe_target}"'';
              remote = if where == "remote" then true else if where == "local" then false else builtins.abort "_module.args.nixinate.buildOn is not either 'local' or 'remote'";
              substituteOnTarget = parameters.substituteOnTarget or false;
              nixOptions = concatStringsSep " " nixOptionsList;
               header = ''
                   set -e
                   sw=''${1:-test}
                   echo "Deploying nixosConfigurations.${machine} from ${flake}" | ${lolcat_cmd}
                   echo "SSH Target: ${user}@${host}" | ${lolcat_cmd}
                   echo ${if port != 22 then "SSH Port: ${port}" else ""} | ${lolcat_cmd}
                   ${optionalString isCrossArch ''echo "Cross-architecture deployment detected (deployer: ${deployerSystem}, target: ${targetSystem}), disabling hermetic activation due to cross-arch policy." | ${lolcat_cmd}''}
                   echo "Rebuild Command:"
                   echo "${where} build : mode $sw  ${if hermetic then "hermetic active" else ""}" | ${figlet_cmd} | ${lolcat_cmd}
                 '';

                remoteCopy = if remote then ''
                  echo "Sending flake to ${machine} via nix copy:"
                  ( ${debug} ${ssh_options} ${nix} ${buildersOption} ${nixOptions} copy ${safe_flake} --to ${safe_ssh_uri} )
                '' else "";

                hermeticActivation = if hermetic then ''
                  echo "Activating configuration hermetically on ${machine} via ssh:"
                    ( ${debug} ${ssh_options} nix ${buildersOption} ${nixOptions} copy --derivation ${safe_nixos_rebuild} --derivation ${safe_parallel} --to ${safe_ssh_uri} )
                    ( ${debug} ${openssh} ${hermeticOpensshCmd} )
                '' else ''
                  echo "Activating configuration non-hermetically on ${machine} via ssh:"
                    ( ${openssh} ${nonHermeticOpensshCmd} )
                '';

                 activation = if remote then remoteCopy + hermeticActivation else ''
                   echo "Building system closure locally, copying it to remote store and activating it:"
                     ( ${debug} ${ssh_options} ${sem} --id "nixinate-${machine}" --semaphore-timeout 60 --fg "${safe_nixos_rebuild} ${nixOptions} \"$sw\" --flake ${safe_target} --target-host ${safe_target_host} --sudo ${optionalString substituteOnTarget "-s"}" )
                 '';
            in 
	    	final.writeShellApplication 
	    	{
	    		name = "deploy-${machine}.sh"; 
	    		meta.description = "nixinate deploy script for ${machine}";
          text = ''exec > >(tee ${logFile}) 2>&1

'' + header + activation;
          runtimeInputs = with final; [ figlet lolcat coreutils ];
	    	};
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

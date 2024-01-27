{
  description = "Entangled, the bi-directional Literate Programming tool";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = { 
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    flake-schemas.url= "github:DeterminateSystems/flake-schemas";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs = { self, nixpkgs, systems, flake-utils, flake-schemas, poetry2nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
	pkgs = import nixpkgs { inherit system; };
        p2nix = poetry2nix.lib.mkPoetry2Nix { inherit pkgs; };
        p2nix' = p2nix.overrideScope' (p2nixself: p2nixsuper: {
          defaultPoetryOverrides = p2nixsuper.defaultPoetryOverrides.extend (self: super: {
            mawk = super.mawk.overridePythonAttrs (
              old: { buildInputs = (old.buildInputs or [ ]) ++ [ super.poetry ]; });
            brei = super.brei.overridePythonAttrs (
              old: { buildInputs = (old.buildInputs or [ ]) ++ [ super.poetry ]; });
            maturin = super.maturin.overridePythonAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ 
                super.setuptools
                super.setuptools-rust
              ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ 
                pkgs.cargo
                pkgs.rustc
                pkgs.rustPlatform.cargoSetupHook
              ];        
              cargoDeps = pkgs.rustPlatform.fetchCargoTarball {
                inherit (old) src;
                name = "${old.pname}-${old.version}";
                hash = "sha256-w8XpCJ8GS2VszW/9/O2suy82zVO1UpWTrU1lFGYwhvw=";
              };        
            });
            #nh3 = super.nh3.overridePythonAttrs (
            #  old: { buildInputs = (old.buildInputs or [ ]) ++ [ self.maturin ]; });
            nh3 = super.nh3.override { preferWheel = true; };
            mkdocstrings-python = super.mkdocstrings-python.overridePythonAttrs (
              old: { propagatedBuildInputs = 
                (nixpkgs.lib.filter (x: x.pname != "mkdocstrings") 
                  old.propagatedBuildInputs) ++ [ super.pdm-backend ]; });
            griffe = super.griffe.overridePythonAttrs (
              old: { buildInputs = (old.buildInputs or [ ]) ++ [ super.pdm-backend ]; });
            findpython = super.findpython.overridePythonAttrs (
              old : { buildInputs = (old.buildInputs or [ ]) ++ [ super.pdm-backend ]; });
            unearth = super.unearth.overridePythonAttrs (
              old : { buildInputs = (old.buildInputs or [ ]) ++ [ super.pdm-backend ]; });
            dep-logic = super.dep-logic.overridePythonAttrs (
              old : { buildInputs = (old.buildInputs or [ ]) ++ [ super.pdm-backend ]; });
          }); 
        });
        inherit (p2nix') mkPoetryApplication mkPoetryEnv;
        pythonEnv = mkPoetryEnv { 
          projectDir = self; 
          extraPackages = ps: [ ps.pip ];
        };
        entangledPkg = mkPoetryApplication { 
          projectDir = self; 
        }; 
      in {    
        packages = rec {
          entangled = entangledPkg; 
          default = entangled;
        };

        apps = rec {
          entangled = flake-utils.lib.mkApp { 
            drv = self.packages.${system}.entangled;
            exePath = "/bin/entangled"; 
          };
          default = entangled;
        }; 

        devShells = {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.entangled ];
            packages = [ pythonEnv pkgs.poetry ] ;
          };
        };
      });
}

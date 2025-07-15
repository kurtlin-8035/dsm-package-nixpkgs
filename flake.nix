{
  description = "Tools for you to create Synology DSM package from nixpkgs";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    {
      overlays = {
        default = import ./overlay;
      };
      packages.x86_64-linux =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [self.overlays.default];
          };
        in pkgs;
    };
}

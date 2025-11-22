{
  pkgs ? import <nixpkgs> {
    config.allowUnfree = true;
  },
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    zig
    zls

    # AI tools
    claude-code
  ];
}


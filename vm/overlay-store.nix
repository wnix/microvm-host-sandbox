# Nix settings on the guest. The /nix overlay is set up in microvm.nix
# (lower = host /nix store share, upper = /nix/.rw-store volume).
# Do not set auto-optimise-store: microvm.nix disallows it when writableStoreOverlay is set.
{ ... }:
{
  nix = {
    settings = {
      sandbox = true;
      # Trust the read-only host store for substitution (lowest priority).
      # Paths resolve through the /nix overlay to cached objects on the host.
      extra-substituters = [ "file:///nix/.ro-store" ];
    };
  };
}

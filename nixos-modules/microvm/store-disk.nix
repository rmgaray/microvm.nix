{ config, lib, pkgs, ... }:

let
  regInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };

in
{
  options.microvm = with lib; {
    storeDiskType = mkOption {
      type = types.enum [ "squashfs" "erofs" ];
      default = "erofs";
      description = ''
        Boot disk file system type: squashfs is smaller, erofs is supposed to be faster.
      '';
    };

    storeDisk = mkOption {
      type = types.path;
      description = ''
        Generated
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.microvm.guest.enable && config.microvm.storeOnDisk) {
      boot.initrd.availableKernelModules = [
        config.microvm.storeDiskType
      ];

      microvm.storeDisk = pkgs.runCommandLocal "microvm-store-disk.${config.microvm.storeDiskType}" {
        nativeBuildInputs = with pkgs; [ {
          squashfs = [ squashfsTools ];
          erofs = [ erofs-utils ];
        }.${config.microvm.storeDiskType} ];
        passthru = {
          inherit regInfo;
        };
      } ''
        echo Copying a /nix/store
        mkdir store
        for d in $(sort -u ${
          lib.concatMapStringsSep " " pkgs.writeReferencesToFile (
            lib.optionals config.microvm.storeOnDisk (
              [ config.system.build.toplevel ]
              ++
              lib.optional config.nix.enable regInfo
            )
          )
        }); do
          cp -a $d store
        done

        echo Creating a ${config.microvm.storeDiskType}
        ${{
          squashfs = "mksquashfs store $out -reproducible -all-root -4k-align";
          erofs = "mkfs.erofs -zlz4hc -L nix-store $out store";
        }.${config.microvm.storeDiskType}}
      '';
    })

    (lib.mkIf (config.microvm.guest.enable && config.nix.enable) {
      microvm.kernelParams = [
        "regInfo=${regInfo}/registration"
      ];
      boot.postBootCommands = ''
        if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
          ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
        fi
      '';
    })
  ];
}
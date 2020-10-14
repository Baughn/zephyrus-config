# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

let
  nvidia = false;
  kernelPackages = pkgs.linuxPackages_latest;
  kernel = kernelPackages.kernel;
  nvidia-offload = pkgs.writeShellScriptBin "nvidia-offload" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec -a "$0" "$@"
  '';
  buildAsusDkms = name: src: pkgs.stdenv.mkDerivation {
    inherit name src;
    nativeBuildInputs = [
      kernel.moduleBuildDependencies
    ];
    buildPhase = ''
      make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) modules
    '';
    installPhase = ''
      make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) INSTALL_MOD_PATH=$out modules_install
    '';
  };
  hid_asus_rog = buildAsusDkms "hid-asus-rog" (builtins.fetchGit {
    url = "https://gitlab.com/asus-linux/hid-asus-rog.git";
    ref = "main";
    rev = "79332c06590584447b633b4e38cca629565fc73c";
  });
  asus_rog_nb_wmi = buildAsusDkms "asus-rog-nb-wmi" (builtins.fetchGit {
    url = "https://gitlab.com/asus-linux/asus-rog-nb-wmi.git";
    ref = "main";
    rev = "d57f78521a4a1cc974b4a1e01560e3b556cab174";
  });
in

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = kernelPackages;
  boot.kernelPatches = [
    { name = "soundfix"; patch = ./0004-alsa-hda-ga401-ga502-experimental.patch; }
  ];
  boot.blacklistedKernelModules = [ "nouveau" "hid-asus" ];
  boot.extraModulePackages = [ hid_asus_rog asus_rog_nb_wmi ];
  boot.kernelModules = [ "hid-asus-rog" "asus-rog-nb-wmi" ];

  networking.hostName = "kaho";
  networking.hostId = "8425e349";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Dublin";
  security.sudo.wheelNeedsPassword = false;
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    neovim powertop git gnome3.gnome-tweak-tool
    pciutils google-chrome nvidia-offload
    ripgrep fd
  ];

  powerManagement = {
    #powertop.enable = true;
    cpuFreqGovernor = "schedutil";
  };

  services.printing.enable = true;

  sound.enable = true;
  hardware.pulseaudio.enable = true;

  hardware.nvidia = pkgs.lib.mkIf nvidia {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    prime = {
      amdgpuBusId = "PCI:4:0:0";
      nvidiaBusId = "PCI:1:0:0";
      offload.enable = true;
      #sync.enable = true;  # Do all rendering on the dGPU
    };
  };

  services.udev.extraRules = pkgs.lib.mkIf (!nvidia) ''
    # Remove nVidia devices, when present.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{remove}="1"
  '';

  hardware.opengl = {
    enable = true;
    driSupport32Bit = true;
  };

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    videoDrivers = [ (if nvidia then "nvidia" else "amdgpu") ];
    layout = "us";
    libinput.enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome3.enable = true;
  };

  users.users.svein = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "20.03"; # Did you read the comment?

}


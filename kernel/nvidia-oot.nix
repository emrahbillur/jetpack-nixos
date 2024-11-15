{
  pkgs,
  kernel,
  runCommand,
  fetchurl,
  buildPackages,
  lib,
  breakpointHook
}:
let

  isNative = pkgs.stdenv.isAarch64;
  pkgsAarch64 = if isNative then pkgs else pkgs.pkgsCross.aarch64-multiplatform;

  src = fetchurl {
    url = "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/sources/public_sources.tbz2";
    hash = "sha256-6U2+ACWuMT7rYDBhaXr+13uWQdKgbfAiiIV0Vi3R9sU=";
  };

  source = runCommand "source-oot" { } ''
    tar xf ${src}
    cd Linux_for_Tegra/source
    mkdir $out
    tar -C $out -xf kernel_oot_modules_src.tbz2
    tar -C $out -xf nvidia_kernel_display_driver_source.tbz2
   '';

  # unclear why we need this, but some part of nvidia's conftest doesn't pick up the headers otherwise
  kernelIncludes = x: [
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/arch/${pkgsAarch64.stdenv.hostPlatform.linuxArch}/include"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/uapi/"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/arch/${pkgsAarch64.stdenv.hostPlatform.linuxArch}/include/uapi/"
  ];
in
pkgsAarch64.stdenv.mkDerivation {
  pname = "nvidia-oot";
  inherit (kernel) version;

  src = source;
  # Patch created like that:
  # nix-build ./packages.nix -A nvidia-oot-cross.src
  # mkdir source
  # cp -r result/* source
  # chmod -R +w source
  # cd source
  # git init .
  # git add .
  # git commit -m "Initial commit"
  # <make changes>
  # git diff > ../0001-build-fixes.patch
  patches = [
    ./0001-build-fixes.patch
    ./linux-6-6-build-fixes.patch
  ];

  postUnpack = ''
    # make kernel headers readable for the nvidia build system.
    cp -r ${kernel.dev} linux-dev
    chmod -R u+w linux-dev
    export KERNEL_HEADERS=$(pwd)/linux-dev/lib/modules/${kernel.modDirVersion}/build
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ breakpointHook ];
  # some calls still go to `gcc` in the build
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  makeFlags =
    [
      "ARCH=${pkgsAarch64.stdenv.hostPlatform.linuxArch}"
      "INSTALL_MOD_PATH=${placeholder "out"}"
      "modules"
    ]
    ++ lib.optionals (pkgsAarch64.stdenv.hostPlatform != pkgsAarch64.stdenv.buildPlatform) [
      "CROSS_COMPILE=${pkgsAarch64.stdenv.cc}/bin/${pkgsAarch64.stdenv.cc.targetPrefix}"
    ];

  CROSS_COMPILE = lib.optionalString (
    pkgsAarch64.stdenv.hostPlatform != pkgsAarch64.stdenv.buildPlatform
  ) "${pkgsAarch64.stdenv.cc}/bin/${pkgsAarch64.stdenv.cc.targetPrefix}";

  hardeningDisable = [ "pic" ];

  # unclear why we need to add nvidia-oot/sound/soc/tegra-virt-alt/include
  # this only happens in the nix-sandbox and not in the nix-shell
  NIX_CFLAGS_COMPILE = "-fno-stack-protector -Wno-error=attribute-warning -I ${source}/nvidia-oot/sound/soc/tegra-virt-alt/include ${
    lib.concatMapStrings (x: "-isystem ${x} ") (kernelIncludes kernel.dev)
  }";

  installTargets = [ "modules_install" ];
}

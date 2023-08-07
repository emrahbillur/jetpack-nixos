# TODO: Should try to merge with upstream nixpkgs's open.nix nvidia driver
{ stdenv
, lib
, fetchgit
, kernel
, l4tVersion
}:

stdenv.mkDerivation rec {
  pname = "nvidia-display-driver";
  version = "jetson_${l4tVersion}";

  src = fetchgit {
    url = "https://nv-tegra.nvidia.com/tegra/kernel-src/nv-kernel-display-driver.git";
    rev = version;
    sha256 = "sha256-6CThvNEyZNVy53lV3xbRN2QpOBiuxV2jGys5ITCf3v0=";
  };

  setSourceRoot = "sourceRoot=$(echo */NVIDIA-kernel-module-source-TempVersion)";

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernel.makeFlags ++ [
    "SYSSRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/source"
    "SYSOUT=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "MODLIB=$(out)/lib/modules/${kernel.modDirVersion}"
  ] ++ lib.optionals ((stdenv.buildPlatform != stdenv.hostPlatform) && stdenv.hostPlatform.isAarch64) [
    "TARGET_ARCH=aarch64"
  ];

  # Avoid an error in modpost: "__stack_chk_guard" [.../nvidia.ko] undefined
  NIX_CFLAGS_COMPILE = "-fno-stack-protector";

  installTargets = [ "modules_install" ];
  enableParallelBuilding = true;

  passthru.meta = {
    license = with lib.licenses; [ mit /* OR */ gpl2Only ];
  };
}

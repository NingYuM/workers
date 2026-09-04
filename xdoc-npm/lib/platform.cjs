"use strict";

const { release: systemRelease } = require("node:os");
const platformsDocument = require("../platforms.json");

const platforms = Object.freeze(
  platformsDocument.platforms.map((platform) => Object.freeze({ ...platform })),
);

function platformId(os = process.platform, cpu = process.arch) {
  const osName = os === "darwin" ? "macos" : os === "win32" ? "windows" : os;
  return `${osName}-${cpu}`;
}

function supportedPlatformIds() {
  return platforms.map((platform) => platform.id);
}

function getPlatform(os = process.platform, cpu = process.arch) {
  const id = platformId(os, cpu);
  const platform = platforms.find((candidate) => candidate.id === id);

  if (!platform) {
    throw new Error(
      `@s8fy/xdoc does not support ${os}/${cpu} (${id}). Supported platforms: ${supportedPlatformIds().join(", ")}.`,
    );
  }

  return platform;
}

function assertRuntimeSupport({
  os = process.platform,
  cpu = process.arch,
  kernelRelease = systemRelease(),
} = {}) {
  const platform = getPlatform(os, cpu);
  if (platform.minimumKernelMajor !== undefined) {
    const kernelMajor = Number.parseInt(kernelRelease, 10);
    if (!Number.isInteger(kernelMajor)) {
      throw new Error(
        `Unable to determine whether ${os}/${cpu} meets the minimum operating system version.`,
      );
    }
    if (kernelMajor < platform.minimumKernelMajor) {
      throw new Error(
        `@s8fy/xdoc ${platform.id} requires macOS ${platform.minimumOsVersion} or newer.`,
      );
    }
  }
  return platform;
}

function resolveBinaryPath({
  os = process.platform,
  cpu = process.arch,
  resolve = require.resolve,
  kernelRelease = systemRelease(),
} = {}) {
  const platform = assertRuntimeSupport({ os, cpu, kernelRelease });
  const request = `${platform.packageName}/bin/${platform.binaryName}`;

  try {
    return resolve(request);
  } catch (cause) {
    throw new Error(
      `The xdoc binary package "${platform.packageName}" is missing. Reinstall @s8fy/xdoc with optional dependencies enabled and without --omit=optional.`,
      { cause },
    );
  }
}

module.exports = {
  assertRuntimeSupport,
  getPlatform,
  platformId,
  platforms,
  resolveBinaryPath,
  supportedPlatformIds,
};

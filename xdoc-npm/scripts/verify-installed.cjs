#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const { getPlatform } = require("../lib/platform.cjs");
const { containsExactVersion } = require("../lib/version.cjs");

const expectedVersion = process.argv[2];
const expectedPlatform = process.argv[3];

if (!expectedVersion) {
  console.error("Usage: node scripts/verify-installed.cjs <version> [platform-id]");
  process.exit(2);
}

const platform = getPlatform();
if (expectedPlatform && platform.id !== expectedPlatform) {
  console.error(`Platform mismatch: expected ${expectedPlatform}, running on ${platform.id}.`);
  process.exit(1);
}

const result = spawnSync("xdoc", ["--version"], {
  encoding: "utf8",
  shell: process.platform === "win32",
});

if (result.error) {
  console.error(`Failed to run the installed xdoc command: ${result.error.message}`);
  process.exit(1);
}

if (result.status !== 0) {
  console.error(`The installed xdoc command exited with status ${result.status ?? "unknown"}.`);
  if (result.stderr) console.error(result.stderr.trim());
  process.exit(1);
}

const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`.trim();

if (!containsExactVersion(output, expectedVersion)) {
  console.error(
    `Installed xdoc version mismatch: expected ${expectedVersion}, received "${output}".`,
  );
  process.exit(1);
}

console.log(`Verified @s8fy/xdoc ${expectedVersion} on ${platform.id}: ${output}`);

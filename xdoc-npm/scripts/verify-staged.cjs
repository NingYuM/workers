#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { getPlatform } = require("../lib/platform.cjs");
const { containsExactVersion } = require("../lib/version.cjs");

function fail(message, detail = "") {
  throw new Error(detail ? `${message}\n${detail}` : message);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    shell: process.platform === "win32",
    ...options,
  });
  if (result.error) fail(`Failed to start ${command}: ${result.error.message}`);
  if (result.status !== 0) {
    fail(
      `${command} exited with status ${result.status ?? "unknown"}.`,
      `${result.stdout ?? ""}\n${result.stderr ?? ""}`.trim(),
    );
  }
  return result;
}

function parsePackReport(output) {
  let document;
  try {
    document = JSON.parse(output);
  } catch (error) {
    fail(`npm pack returned invalid JSON: ${error.message}`, output);
  }

  const reports = Array.isArray(document)
    ? document
    : document !== null && typeof document === "object"
      ? Object.values(document)
      : [];
  if (
    reports.length !== 1 ||
    reports[0] === null ||
    typeof reports[0] !== "object" ||
    Array.isArray(reports[0])
  ) {
    fail("npm pack did not return exactly one package report.", output);
  }

  return reports[0];
}

function pack(packageDirectory, destination) {
  const result = run("npm", [
    "pack",
    packageDirectory,
    "--json",
    "--ignore-scripts",
    "--pack-destination",
    destination,
  ]);
  const report = parsePackReport(result.stdout);
  if (!report?.filename) fail("npm pack did not report a tarball filename.");
  return path.join(destination, report.filename);
}

function main() {
  const stagingDirectory = path.resolve(process.argv[2] || "");
  const expectedVersion = process.argv[3];
  const expectedPlatform = process.argv[4];
  if (!process.argv[2] || !expectedVersion || !expectedPlatform) {
    fail("Usage: node scripts/verify-staged.cjs <staging-directory> <version> <platform-id>");
  }

  const platform = getPlatform();
  if (platform.id !== expectedPlatform) {
    fail(`Platform mismatch: expected ${expectedPlatform}, running on ${platform.id}.`);
  }

  const plan = JSON.parse(
    fs.readFileSync(path.join(stagingDirectory, "release-plan.json"), "utf8"),
  );
  if (plan.source?.version !== expectedVersion) {
    fail(
      `Release plan version mismatch: expected ${expectedVersion}, received ${plan.source?.version}.`,
    );
  }
  const base = plan.packages.find((entry) => entry.kind === "base");
  const native = plan.packages.find((entry) => entry.id === platform.id);
  if (!base || !native || native.name !== platform.packageName) {
    fail(`Release plan does not contain the expected packages for ${platform.id}.`);
  }

  const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "xdoc-npm-smoke-"));
  try {
    const tarballDirectory = path.join(temporaryDirectory, "tarballs");
    const installDirectory = path.join(temporaryDirectory, "install");
    fs.mkdirSync(tarballDirectory);
    fs.mkdirSync(installDirectory);

    const nativeTarball = pack(path.join(stagingDirectory, native.directory), tarballDirectory);
    const baseTarball = pack(path.join(stagingDirectory, base.directory), tarballDirectory);
    run("npm", [
      "install",
      "--prefix",
      installDirectory,
      "--install-links",
      "--ignore-scripts=false",
      "--registry=https://registry.npmjs.org",
      nativeTarball,
      baseTarball,
    ]);

    const launcher = path.join(
      installDirectory,
      "node_modules",
      "@s8fy",
      "xdoc",
      "lib",
      "index.cjs",
    );
    const result = run(process.execPath, [launcher, "--version"]);
    const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`.trim();
    if (!containsExactVersion(output, expectedVersion)) {
      fail(`Staged xdoc version mismatch: expected ${expectedVersion}, received "${output}".`);
    }
    console.log(`Verified staged @s8fy/xdoc ${expectedVersion} on ${platform.id}: ${output}`);
  } finally {
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(
      `xdoc staging verification error: ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exitCode = 1;
  }
}

module.exports = { parsePackReport };

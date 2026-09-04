"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const { execute } = require("../lib/index.cjs");
const {
  assertRuntimeSupport,
  getPlatform,
  platformId,
  resolveBinaryPath,
  supportedPlatformIds,
} = require("../lib/platform.cjs");
const { containsExactVersion } = require("../lib/version.cjs");
const { parsePackReport } = require("../scripts/verify-staged.cjs");

const projectDir = path.resolve(__dirname, "..");

test("maps every supported Node platform tuple to one package", () => {
  assert.equal(platformId("darwin", "arm64"), "macos-arm64");
  assert.equal(platformId("win32", "x64"), "windows-x64");
  assert.equal(getPlatform("linux", "arm64").packageName, "@s8fy/xdoc-linux-arm64");
  assert.deepEqual(supportedPlatformIds(), [
    "linux-arm64",
    "linux-x64",
    "macos-arm64",
    "windows-x64",
  ]);
});

test("rejects unsupported platform tuples with an actionable English error", () => {
  assert.throws(
    () => getPlatform("darwin", "x64"),
    /does not support darwin\/x64.*Supported platforms:/,
  );
});

test("rejects macOS versions older than the native binary deployment target", () => {
  assert.throws(
    () => assertRuntimeSupport({ os: "darwin", cpu: "arm64", kernelRelease: "21.6.0" }),
    /requires macOS 13\.0 or newer/,
  );
  assert.equal(
    assertRuntimeSupport({ os: "darwin", cpu: "arm64", kernelRelease: "22.0.0" }).id,
    "macos-arm64",
  );
});

test("reports a missing optional binary package", () => {
  assert.throws(
    () =>
      resolveBinaryPath({
        os: "linux",
        cpu: "x64",
        resolve: () => {
          throw new Error("missing");
        },
      }),
    /optional dependencies enabled.*--omit=optional/,
  );
});

test("passes arguments through and preserves a normal exit status", () => {
  let invocation;
  const result = execute(["inspect", "deck.pptx"], {
    os: "linux",
    cpu: "x64",
    resolve: () => "/tmp/xdoc",
    spawn: (command, args, options) => {
      invocation = { command, args, options };
      return { status: 23, signal: null };
    },
  });

  assert.deepEqual(invocation, {
    command: "/tmp/xdoc",
    args: ["inspect", "deck.pptx"],
    options: { stdio: "inherit" },
  });
  assert.deepEqual(result, { exitCode: 23, signal: null });
});

test("never converts spawn errors or indeterminate exits into success", () => {
  assert.throws(
    () =>
      execute([], {
        os: "linux",
        cpu: "x64",
        resolve: () => "/tmp/xdoc",
        spawn: () => ({ error: new Error("EACCES"), status: null, signal: null }),
      }),
    /Failed to start.*EACCES/,
  );

  assert.deepEqual(
    execute([], {
      os: "linux",
      cpu: "x64",
      resolve: () => "/tmp/xdoc",
      spawn: () => ({ status: null, signal: null }),
    }),
    { exitCode: 1, signal: null },
  );
});

test("maps signal termination to a non-zero conventional exit code", () => {
  const result = execute([], {
    os: "linux",
    cpu: "x64",
    resolve: () => "/tmp/xdoc",
    spawn: () => ({ status: null, signal: "SIGTERM" }),
  });

  assert.equal(result.signal, "SIGTERM");
  assert.ok(result.exitCode > 128);
});

test("keeps the public package manifest aligned with the platform manifest", () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(projectDir, "package.json"), "utf8"));
  const platforms = JSON.parse(
    fs.readFileSync(path.join(projectDir, "platforms.json"), "utf8"),
  ).platforms;
  const expectedDependencies = Object.fromEntries(
    platforms.map((platform) => [platform.packageName, packageJson.version]),
  );

  assert.equal(packageJson.name, "@s8fy/xdoc");
  assert.equal(
    packageJson.homepage,
    "https://github.com/hustcer/workers/tree/main/xdoc-npm#readme",
  );
  assert.deepEqual(packageJson.bugs, { url: "https://github.com/hustcer/workers/issues" });
  assert.deepEqual(packageJson.repository, {
    type: "git",
    url: "git+https://github.com/hustcer/workers.git",
    directory: "xdoc-npm",
  });
  assert.deepEqual(packageJson.files, ["lib", "platforms.json"]);
  assert.deepEqual(packageJson.optionalDependencies, expectedDependencies);
  assert.equal(packageJson.xdoc.releaseTag, `v${packageJson.version}`);
});

test("all launcher and install diagnostics are English-only", () => {
  for (const file of [
    "lib/index.cjs",
    "lib/check-platform.cjs",
    "lib/platform.cjs",
    "lib/version.cjs",
    "scripts/verify-installed.cjs",
    "scripts/verify-staged.cjs",
  ]) {
    const source = fs.readFileSync(path.join(projectDir, file), "utf8");
    assert.doesNotMatch(source, /[\u3400-\u9fff]/u);
  }
});

test("matches only the exact native semantic version token", () => {
  assert.equal(containsExactVersion("xdoc 0.3.10 (abc123)", "0.3.10"), true);
  assert.equal(containsExactVersion("xdoc v0.3.10", "0.3.10"), true);
  assert.equal(containsExactVersion("xdoc 0.3.100", "0.3.10"), false);
  assert.equal(containsExactVersion("xdoc 0.3.10-beta.1", "0.3.10"), false);
});

test("parses the npm 11 array-shaped pack report", () => {
  const report = parsePackReport(
    JSON.stringify([{ name: "@s8fy/xdoc", filename: "s8fy-xdoc-0.3.11.tgz" }]),
  );

  assert.equal(report.filename, "s8fy-xdoc-0.3.11.tgz");
});

test("parses the npm 12 package-keyed pack report", () => {
  const report = parsePackReport(
    JSON.stringify({
      "@s8fy/xdoc": {
        name: "@s8fy/xdoc",
        filename: "s8fy-xdoc-0.3.11.tgz",
      },
    }),
  );

  assert.equal(report.filename, "s8fy-xdoc-0.3.11.tgz");
});

test("rejects npm pack output containing multiple package reports", () => {
  assert.throws(
    () =>
      parsePackReport(
        JSON.stringify({
          "@s8fy/xdoc": { filename: "s8fy-xdoc-0.3.11.tgz" },
          "@s8fy/xdoc-linux-x64": { filename: "s8fy-xdoc-linux-x64-0.3.11.tgz" },
        }),
      ),
    /exactly one package report/,
  );
});

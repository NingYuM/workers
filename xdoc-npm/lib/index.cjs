#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const { constants } = require("node:os");
const { resolveBinaryPath } = require("./platform.cjs");

function execute(
  args = process.argv.slice(2),
  { os = process.platform, cpu = process.arch, resolve = require.resolve, spawn = spawnSync } = {},
) {
  const executable = resolveBinaryPath({ os, cpu, resolve });
  const result = spawn(executable, args, { stdio: "inherit" });

  if (result.error) {
    throw new Error(`Failed to start the xdoc binary: ${result.error.message}`, {
      cause: result.error,
    });
  }

  if (typeof result.status === "number") {
    return { exitCode: result.status, signal: null };
  }

  if (result.signal) {
    const signalNumber = constants.signals[result.signal];
    return {
      exitCode: typeof signalNumber === "number" ? 128 + signalNumber : 1,
      signal: result.signal,
    };
  }

  return { exitCode: 1, signal: null };
}

function main() {
  try {
    const result = execute();

    if (result.signal && process.platform !== "win32") {
      try {
        process.kill(process.pid, result.signal);
      } catch (cause) {
        const message = cause instanceof Error ? cause.message : String(cause);
        console.error(`xdoc launcher warning: failed to propagate ${result.signal}: ${message}`);
      }
    }

    process.exitCode = result.exitCode;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`xdoc launcher error: ${message}`);
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main();
}

module.exports = { execute, main };

#!/usr/bin/env node
"use strict";

const { assertRuntimeSupport } = require("./platform.cjs");

try {
  assertRuntimeSupport();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`xdoc install error: ${message}`);
  process.exitCode = 1;
}

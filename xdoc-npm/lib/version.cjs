"use strict";

function containsExactVersion(output, expectedVersion) {
  const escaped = expectedVersion.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|\\s)v?${escaped}(?=\\s|$)`).test(output);
}

module.exports = { containsExactVersion };

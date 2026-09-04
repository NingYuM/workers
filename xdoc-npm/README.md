# `@s8fy/xdoc`

Install the native `xdoc` CLI through npm:

```sh
npm install --global @s8fy/xdoc
xdoc --version
```

The base package selects an exact, platform-specific optional dependency. No
binary is downloaded by an install script.

## Supported platforms

| Operating system  | Architecture | Binary package           |
| ----------------- | ------------ | ------------------------ |
| Linux             | arm64        | `@s8fy/xdoc-linux-arm64` |
| Linux             | x64          | `@s8fy/xdoc-linux-x64`   |
| macOS 26 or newer | arm64        | `@s8fy/xdoc-macos-arm64` |
| Windows           | x64          | `@s8fy/xdoc-windows-x64` |

Installation fails with an actionable error on any unsupported operating
system, architecture, or operating system version. The minimum supported
Node.js version is 22. The macOS requirement reflects the deployment target of
the current upstream native binary.

The locked v0.3.10 macOS asset predates the native deployment-target fix and
must not be published as compatible with older macOS releases. The npm
preflight and smoke jobs intentionally run on macOS 15, so this asset will fail
closed. Cut a new upstream xdoc release with `MACOSX_DEPLOYMENT_TARGET=13.0`,
then update `minimumOsVersion` to `13.0` and `minimumKernelMajor` to `22` in
`platforms.json` together with the version and release lock. macOS 13 is the
current lower bound because the statically linked PDFium archive has a macOS
13 deployment target.

## Source and issue reporting

This directory contains only the npm packaging and release automation. The
native binaries come from the private `hustcer/pptx` repository and are locked
to reviewed GitHub Release SHA-256 digests in `release-lock.json`.

- Report npm installation, package selection, or launcher issues in the
  [`hustcer/pptx-nova` issue tracker](https://github.com/hustcer/pptx-nova/issues).
- Report native `xdoc` behavior through the upstream project's normal support
  channel.

Each platform package preserves the upstream `LICENSE` and all bundled PDFium
third-party license notices. This software is distributed under the PolyForm
Noncommercial License 1.0.0 unless separately licensed.


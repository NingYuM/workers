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

## Maintainer release process

The release scripts require Nushell 0.115.1, Node.js 22 or newer, and npm
11.5.1 or newer. CI pins Node.js 24 and npm 12.0.2. Human-facing output and
errors are intentionally in English. Run all commands in this `xdoc-npm`
directory.

### Repository setup

- Add `XDOC_SOURCE_TOKEN` as a repository secret. It must be a fine-grained,
  read-only GitHub token with Contents access to the private `hustcer/pptx`
  repository. The prepare job uses it only while downloading release assets.
- Create a protected GitHub environment named `npm`. The publish job alone
  enters this environment and receives the `id-token: write` permission.
  Restrict its deployment branches to `main` and add required reviewers if
  appropriate.
- After the one-time bootstrap below, configure all five npm packages to trust
  GitHub owner `NingYuM`, repository `workers`, workflow filename
  `xdoc-npm-publish.yml`, and environment `npm`; enable the `npm publish`
  allowed action. Then disable token-based publishing for maximum protection.

### Regular release

1. Confirm that the upstream GitHub Release is final and that all four expected
   assets expose SHA-256 digests. Export `XDOC_SOURCE_TOKEN` locally.
2. Update the wrapper version, all exact optional dependency versions, and the
   reviewable release lock:

   ```sh
   nu scripts/update-release.nu v0.3.10
   git diff -- package.json release-lock.json
   ```

   Review every asset name, byte size, and SHA-256 change. Also review the
   native deployment targets when the upstream build configuration changes.
   The update script never commits, tags, pushes, or stages unrelated files.

3. Run the local gates, then perform a complete local staging rehearsal:

   ```sh
   nu scripts/check.nu
   nu scripts/prepare-release.nu --out ./staging
   ```

   The staging directory is disposable and ignored by Git. This rehearsal
   downloads all assets again, rejects unexpected archive paths, verifies the
   locked sizes and digests, preserves all license files, and applies npm's
   final packing rules to every package.

4. Commit the reviewed wrapper changes, merge them to `main`, and dispatch the
   workflow:

   ```sh
   gh workflow run xdoc-npm-publish.yml -f dist_tag=latest
   gh run watch --exit-status
   ```

5. The workflow performs these gates in order:

   - prepares all five packages from the private release and uploads only the
     staged packages as a one-day workflow artifact;
   - installs the staged tarballs and runs the exact native version on Linux
     x64, Linux arm64, macOS arm64, and Windows x64 before publishing anything;
   - publishes all four platform packages with npm provenance;
   - polls npm until every exact platform version and dist-tag is visible;
   - publishes `@s8fy/xdoc` last, then waits for its exact metadata;
   - installs `@s8fy/xdoc@<exact-version>` from npm and runs a final smoke test
     on all four platforms.

6. Verify the public metadata if needed:

   ```sh
   npm view @s8fy/xdoc@0.3.10 version optionalDependencies dist.integrity
   ```

Normal releases use GitHub OIDC trusted publishing and npm provenance; they do
not use a long-lived npm token.

### Failure and rerun behavior

No workflow step uses `continue-on-error`. If a platform package was published
before a later registry or network failure, rerun the same workflow with the
same commit and dist-tag. The publisher verifies the immutable package's
version, custom provenance metadata, tarball integrity, SHA-1 shasum, and
dist-tag before skipping it. It refuses to reuse an existing version whose
metadata or packed content differs. The base package is never attempted until
all four platform packages are confirmed visible.

### One-time npm bootstrap

npm trusted publishing can normally be configured only after a package exists.
For the first release only:

1. Create a short-lived granular npm token with bypass 2FA enabled for the
   `@s8fy` packages, and temporarily add it to the protected `npm` environment
   as `NPM_BOOTSTRAP_TOKEN`.
2. Dispatch the same protected workflow with its bootstrap switch enabled:

```sh
gh workflow run xdoc-npm-publish.yml -f dist_tag=latest -f bootstrap_token_auth=true
gh run watch --exit-status
```

The bootstrap still runs every staging and four-platform preflight gate on a
GitHub-hosted runner and publishes provenance. The temporary token is scoped to
the publish job; normal workflow runs leave the switch disabled and do not read
this secret.

3. While the short-lived token is still valid, configure the five trusted
   publishers. Keep the token itself in an environment variable rather than in
   the npm configuration file:

```sh
export NODE_AUTH_TOKEN='replace-with-the-short-lived-token'
export NPM_CONFIG_USERCONFIG="$(mktemp)"
printf '%s\n' '//registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN}' > "$NPM_CONFIG_USERCONFIG"
npm install --global npm@12.0.2 --ignore-scripts
npm trust github @s8fy/xdoc --file xdoc-npm-publish.yml --repo NingYuM/workers --env npm --allow-publish -y
npm trust github @s8fy/xdoc-linux-arm64 --file xdoc-npm-publish.yml --repo NingYuM/workers --env npm --allow-publish -y
npm trust github @s8fy/xdoc-linux-x64 --file xdoc-npm-publish.yml --repo NingYuM/workers --env npm --allow-publish -y
npm trust github @s8fy/xdoc-macos-arm64 --file xdoc-npm-publish.yml --repo NingYuM/workers --env npm --allow-publish -y
npm trust github @s8fy/xdoc-windows-x64 --file xdoc-npm-publish.yml --repo NingYuM/workers --env npm --allow-publish -y
npm logout --registry=https://registry.npmjs.org
rm "$NPM_CONFIG_USERCONFIG"
```

4. Delete the `NPM_BOOTSTRAP_TOKEN` environment secret, immediately revoke the
   token, verify the trusted publisher settings for all five packages on
   npmjs.com, and disable token-based publishing. Every later release uses the
   default `bootstrap_token_auth=false` OIDC path.

The update and publish scripts never create Git commits, tags, or pushes.

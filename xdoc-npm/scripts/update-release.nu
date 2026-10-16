#!/usr/bin/env nu

use release-lib.nu *

# Update the reviewable release lock and base package manifest from GitHub.
def main [
  tag: string # Upstream xdoc release tag, for example v0.3.10
  --package-version: string # npm version for all five packages; defaults to the upstream version
] {
  let identity = (normalize-release-tag $tag)
  let npm_version = (normalize-release-tag ($package_version | default $identity.version)).version
  validate-package-version $npm_version $identity.version
  let release = (fetch-upstream-release $identity.tag)
  let lock = (lock-from-release $release)
  let package = (
    open $PACKAGE_PATH
    | update version $npm_version
    | update optionalDependencies (expected-optional-dependencies $npm_version)
    | update xdoc.releaseTag $identity.tag
    | update xdoc.sourceRepository $SOURCE_REPOSITORY
  )

  save-json $RELEASE_LOCK_PATH $lock
  save-json $PACKAGE_PATH $package
  validate-project | ignore

  print $'Updated xdoc npm manifests to ($npm_version) using upstream ($identity.tag).'
  print 'Review the release-lock.json digest changes before committing.'
  print 'No Git commit, tag, or push was performed.'
}

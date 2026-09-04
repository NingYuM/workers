#!/usr/bin/env nu

use release-lib.nu *

export def validate-dist-tag [dist_tag: string]: nothing -> string {
  let value = ($dist_tag | str trim)
  if $value !~ '^[A-Za-z][A-Za-z0-9._-]*$' {
    fail $'Invalid npm dist-tag: ($dist_tag)'
  }
  let is_semver = (try {
    $value | into semver | ignore
    true
  } catch { false })
  if $is_semver {
    fail $'An npm dist-tag must not be a semantic version: ($value)'
  }
  $value
}

export def package-path [staging_dir: path, relative: string]: nothing -> path {
  let normalized = ($relative | str replace --all '\\' '/')
  if (
    ($normalized | is-empty)
    or ($normalized | str starts-with '/')
    or ($normalized =~ '^[A-Za-z]:')
    or ($normalized | split row '/' | any {|part| $part == '..' })
  ) {
    fail $'Invalid package directory in release plan: ($relative)'
  }
  $staging_dir | path join $normalized
}

def registry-package [name: string, version: string]: nothing -> any {
  let spec = $'($name)@($version)'
  let result = (^npm view $spec --json --registry $NPM_REGISTRY | complete)
  if $result.exit_code != 0 {
    let diagnostic = $'($result.stdout)($result.stderr)'
    if $diagnostic =~ 'E404|404 Not Found' {
      return null
    }
    fail $'Failed to query npm metadata for ($spec).' ($result.stderr | str trim)
  }

  try {
    $result.stdout | from json
  } catch {|error|
    fail $'npm returned invalid metadata for ($spec).' ($error.msg? | default '')
  }
}

def validate-existing [plan_entry: record, package_dir: path, metadata: record, dist_tag: string] {
  let expected = (open ($package_dir | path join 'package.json'))
  if ($metadata.name? | default '') != $expected.name or ($metadata.version? | default '') != $expected.version {
    fail $'Existing npm metadata does not match ($plan_entry.name)@($plan_entry.version).'
  }
  if ($metadata.xdoc? | default {}) != ($expected.xdoc? | default {}) {
    fail $'Existing npm package ($plan_entry.name)@($plan_entry.version) has different xdoc provenance metadata.'
  }
  if ($metadata.dist.integrity? | default '') != $plan_entry.packageIntegrity or ($metadata.dist.shasum? | default '') != $plan_entry.packageShasum {
    fail $'Existing npm package ($plan_entry.name)@($plan_entry.version) has different packed content integrity.'
  }
  if $plan_entry.kind == 'base' and ($metadata.optionalDependencies? | default {}) != $expected.optionalDependencies {
    fail $'Existing base package ($plan_entry.name)@($plan_entry.version) has different optional dependencies.'
  }
  let published_tag = ($metadata.'dist-tags'? | default {} | get --optional $dist_tag | default '')
  $published_tag == $plan_entry.version
}

def publish-one [plan_entry: record, package_dir: path, dist_tag: string, allow_token_auth: bool] {
  let existing = (registry-package $plan_entry.name $plan_entry.version)
  if $existing != null {
    let tag_is_ready = (validate-existing $plan_entry $package_dir $existing $dist_tag)
    let tag_status = if $tag_is_ready { 'with the expected dist-tag' } else { 'while the dist-tag is still pending' }
    print $'Verified existing package ($plan_entry.name)@($plan_entry.version) ($tag_status); skipping publish.'
    return
  }

  print $'Publishing ($plan_entry.name)@($plan_entry.version) with dist-tag ($dist_tag)...'
  let oidc_provenance = (($env.GITHUB_ACTIONS? | default '') == 'true' and ($env.ACTIONS_ID_TOKEN_REQUEST_URL? | default '' | is-not-empty) and ($env.ACTIONS_ID_TOKEN_REQUEST_TOKEN? | default '' | is-not-empty))
  let result = if (not $allow_token_auth) or $oidc_provenance {
    ^npm publish $package_dir --tag $dist_tag --access public --provenance --registry $NPM_REGISTRY | complete
  } else {
    ^npm publish $package_dir --tag $dist_tag --access public --provenance=false --registry $NPM_REGISTRY | complete
  }
  if $result.exit_code != 0 {
    fail $'Failed to publish ($plan_entry.name)@($plan_entry.version).' ($result.stderr | str trim)
  }
}

def wait-for-package [plan_entry: record, package_dir: path, dist_tag: string] {
  for attempt in 1..24 {
    let metadata = (registry-package $plan_entry.name $plan_entry.version)
    if $metadata != null {
      let tag_is_ready = (validate-existing $plan_entry $package_dir $metadata $dist_tag)
      if $tag_is_ready {
        print $'Registry confirmed ($plan_entry.name)@($plan_entry.version) with dist-tag ($dist_tag).'
        return
      }
    }
    if $attempt < 24 {
      sleep 5sec
    }
  }
  fail $'Timed out waiting for ($plan_entry.name)@($plan_entry.version) and dist-tag ($dist_tag) to become visible on npm.' 'Use a new package version or update the dist-tag through an explicitly authorized maintenance process.'
}

def validate-auth [allow_token_auth: bool] {
  if $allow_token_auth {
    let whoami = (^npm whoami --registry $NPM_REGISTRY | complete)
    if $whoami.exit_code != 0 {
      fail 'npm token authentication is not configured.' 'Authenticate with a short-lived granular token before using --allow-token-auth.'
    }
    print $'WARNING: Token authentication as ($whoami.stdout | str trim) is enabled for one-time package bootstrap only.'
    return
  }

  let oidc_url = ($env.ACTIONS_ID_TOKEN_REQUEST_URL? | default '')
  let oidc_token = ($env.ACTIONS_ID_TOKEN_REQUEST_TOKEN? | default '')
  if ($env.GITHUB_ACTIONS? | default '') != 'true' or ($oidc_url | is-empty) or ($oidc_token | is-empty) {
    fail 'GitHub Actions OIDC is required for normal publishing.' 'Use the protected publish workflow, or use --allow-token-auth only for the one-time npm bootstrap.'
  }
}

def validate-npm-version [] {
  let result = (^npm --version | complete)
  if $result.exit_code != 0 {
    fail 'Failed to determine the npm version.' ($result.stderr | str trim)
  }
  let version = try {
    $result.stdout | str trim | into semver
  } catch {|error|
    fail 'npm returned an invalid version.' ($error.msg? | default '')
  }
  if $version < ('11.5.1' | into semver) {
    fail $'npm 11.5.1 or newer is required for trusted publishing; found ($version).'
  }
}

# Publish a fully prepared release. Platform packages are made visible first.
def main [
  staging: path # Directory created by prepare-release.nu
  --dist-tag: string = 'latest' # npm dist-tag applied to every package
  --allow-token-auth # One-time bootstrap only; normal releases require OIDC
] {
  require-external 'npm'
  validate-npm-version
  validate-auth $allow_token_auth
  let tag = (validate-dist-tag $dist_tag)
  let staging_dir = ($staging | path expand)
  let plan_path = ($staging_dir | path join 'release-plan.json')
  if not ($plan_path | path exists) {
    fail $'Release plan not found: ($plan_path)'
  }

  let plan = (open $plan_path)
  let project = (validate-project)
  if ($plan.schemaVersion? | default '') != 'xdoc-npm-release-plan/v1' {
    fail 'Unsupported release plan schema.'
  }
  if $plan.source != $project.lock.source {
    fail 'The staged release plan does not match the checked-in release lock.'
  }

  let expected_names = (
    $project.platforms
    | get packageName
    | append '@s8fy/xdoc'
    | sort
  )
  if ($plan.packages | get name | sort) != $expected_names {
    fail 'The release plan does not contain exactly the expected npm packages.'
  }
  if ($plan.packages | get name | uniq | length) != ($plan.packages | length) {
    fail 'The release plan contains duplicate npm package names.'
  }

  let checked = (
    $plan.packages
    | each {|entry|
        if $entry.version != $project.lock.source.version {
          fail $'Unexpected package version in release plan: ($entry.name)@($entry.version)'
        }
        let directory = (package-path $staging_dir $entry.directory)
        let required = if $entry.kind == 'base' {
          ['package.json', 'README.md', 'LICENSE', 'lib/index.cjs', 'lib/version.cjs', 'platforms.json']
        } else {
          let matches = ($project.platforms | where id == $entry.id)
          if ($matches | length) != 1 {
            fail $'Unknown platform package in release plan: ($entry.id)'
          }
          let platform = ($matches | first)
          ['package.json', 'LICENSE', $'bin/($platform.binaryName)', 'provenance.json']
        }
        let report = (verify-pack $directory $required)
        if $report.name != $entry.name or $report.version != $entry.version {
          fail $'Packed package identity does not match the release plan for ($entry.name).'
        }
        if $report.integrity != $entry.packageIntegrity or $report.shasum != $entry.packageShasum {
          fail $'Packed content does not match the release plan for ($entry.name)@($entry.version).'
        }
        {entry: $entry, directory: $directory}
      }
  )
  let platforms = ($checked | where entry.kind == 'platform')
  let bases = ($checked | where entry.kind == 'base')
  if ($bases | length) != 1 or ($platforms | length) != ($project.platforms | length) {
    fail 'The release plan must contain four platform packages and one base package.'
  }

  for item in $platforms {
    publish-one $item.entry $item.directory $tag $allow_token_auth
  }
  for item in $platforms {
    wait-for-package $item.entry $item.directory $tag
  }

  let base = ($bases | first)
  publish-one $base.entry $base.directory $tag $allow_token_auth
  wait-for-package $base.entry $base.directory $tag
  print $'Published and verified all packages for ($project.lock.source.tag).'
  print 'No Git commit, tag, or push was performed.'
}

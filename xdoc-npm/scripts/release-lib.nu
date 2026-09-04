#!/usr/bin/env nu

export const PROJECT_DIR = path self ..
export const PLATFORMS_PATH = path self ../platforms.json
export const RELEASE_LOCK_PATH = path self ../release-lock.json
export const PACKAGE_PATH = path self ../package.json
export const SOURCE_REPOSITORY = 'hustcer/pptx'
export const NPM_REGISTRY = 'https://registry.npmjs.org'

# Raise a consistent, unspanned release error.
export def fail [message: string, help_text?: string] {
  error make --unspanned {
    msg: $message
    help: ($help_text | default '')
  }
}

def duplicate-values [values: list<string>]: nothing -> list<string> {
  $values
  | group-by --to-table
  | where {|group| ($group.items | length) > 1 }
  | get group
}

# Read and validate the supported platform manifest.
export def load-platforms []: nothing -> list<record> {
  let document = (open $PLATFORMS_PATH)
  if ($document.schemaVersion? | default '') != 'xdoc-npm-platforms/v1' {
    fail 'Unsupported platform manifest schema.'
  }

  let platforms = ($document.platforms? | default [])
  if ($platforms | is-empty) {
    fail 'The platform manifest must contain at least one platform.'
  }

  let duplicate_ids = (duplicate-values ($platforms | get id))
  let duplicate_packages = (duplicate-values ($platforms | get packageName))
  let duplicate_assets = (duplicate-values ($platforms | get assetName))
  let duplicate_tuples = (duplicate-values ($platforms | each {|platform| $'($platform.os)/($platform.cpu)' }))
  if ($duplicate_ids | is-not-empty) {
    fail $'Duplicate platform IDs: ($duplicate_ids | str join ", ")'
  }
  if ($duplicate_packages | is-not-empty) {
    fail $'Duplicate platform package names: ($duplicate_packages | str join ", ")'
  }
  if ($duplicate_assets | is-not-empty) {
    fail $'Duplicate release asset names: ($duplicate_assets | str join ", ")'
  }
  if ($duplicate_tuples | is-not-empty) {
    fail $'Duplicate operating system and architecture pairs: ($duplicate_tuples | str join ", ")'
  }

  for platform in $platforms {
    let os_name = if $platform.os == 'darwin' { 'macos' } else if $platform.os == 'win32' { 'windows' } else { $platform.os }
    if $platform.id != $'($os_name)-($platform.cpu)' {
      fail $'Platform ID does not match its operating system and architecture: ($platform.id)'
    }
    if $platform.packageName != $'@s8fy/xdoc-($platform.id)' {
      fail $'Platform package name does not match its ID: ($platform.id)'
    }
    if $platform.archiveType not-in ['tar.gz', 'zip'] {
      fail $'Unsupported archive type for ($platform.id): ($platform.archiveType)'
    }
    if ($platform.binaryName | is-empty) or ($platform.binaryName | str contains '/') or ($platform.binaryName | str contains '\\') {
      fail $'Invalid binary name for ($platform.id): ($platform.binaryName)'
    }
    if ($platform.minimumOsVersion? | default '') != '' and ($platform.minimumKernelMajor? | default 0) <= 0 {
      fail $'Platform ($platform.id) must define a positive minimumKernelMajor.'
    }
  }

  $platforms
}

# Read the checked-in release lock.
export def load-release-lock []: nothing -> record {
  let lock = (open $RELEASE_LOCK_PATH)
  if ($lock.schemaVersion? | default '') != 'xdoc-npm-release-lock/v1' {
    fail 'Unsupported release lock schema.'
  }
  if ($lock.source.repository? | default '') != $SOURCE_REPOSITORY {
    fail $'The release lock must reference ($SOURCE_REPOSITORY).'
  }
  $lock
}

# Normalize a release tag and validate its semantic version.
export def normalize-release-tag [tag: string]: nothing -> record<tag: string, version: string> {
  let trimmed = ($tag | str trim)
  let version = ($trimmed | str replace -r '^v' '')
  if ($version | is-empty) {
    fail 'The release tag must not be empty.'
  }

  try {
    $version | into semver | ignore
  } catch {|error|
    fail $'Invalid semantic version in release tag: ($tag)' ($error.msg? | default '')
  }

  {tag: $'v($version)', version: $version}
}

# Build the exact optional dependency map for a release version.
export def expected-optional-dependencies [version: string]: nothing -> record {
  load-platforms
  | reduce --fold {} {|platform, dependencies|
      $dependencies | upsert $platform.packageName $version
    }
}

# Return GitHub API headers without exposing the source token in argv or logs.
export def github-headers [accept: string = 'application/vnd.github+json']: nothing -> record {
  let token = ($env.ACCESS_TOKEN? | default ($env.GH_TOKEN? | default ''))
  if ($token | is-empty) {
    fail 'ACCESS_TOKEN is required to read releases from the private hustcer/pptx repository.' 'Use a fine-grained, read-only token with Contents access.'
  }

  {
    Accept: $accept
    Authorization: $'Bearer ($token)'
    'User-Agent': 'xdoc-npm-release'
    'X-GitHub-Api-Version': '2022-11-28'
  }
}

# Fetch one release from the private upstream repository.
export def fetch-upstream-release [tag: string]: nothing -> record {
  let url = $'https://api.github.com/repos/($SOURCE_REPOSITORY)/releases/tags/($tag)'
  try {
    http get --max-time 1min --headers (github-headers) $url
  } catch {|error|
    fail $'Failed to fetch upstream release ($tag).' ($error.msg? | default '')
  }
}

# Convert GitHub release metadata into the reviewable lock format.
export def lock-from-release [release: record]: nothing -> record {
  let identity = (normalize-release-tag ($release.tag_name? | default ''))
  let platforms = (load-platforms)
  let release_assets = ($release.assets? | default [])
  let assets = (
    $platforms
    | reduce --fold {} {|platform, locked|
        let matches = ($release_assets | where name == $platform.assetName)
        if ($matches | length) != 1 {
          fail $'Expected exactly one upstream asset named ($platform.assetName).'
        }

        let asset = ($matches | first)
        let digest = ($asset.digest? | default '')
        if $digest !~ '^sha256:[0-9a-f]{64}$' {
          fail $'Upstream asset ($platform.assetName) has no valid SHA-256 digest.'
        }

        $locked | upsert $platform.id {
          name: $platform.assetName
          sha256: ($digest | str replace 'sha256:' '')
          sizeBytes: ($asset.size? | default 0 | into int)
        }
      }
  )

  {
    schemaVersion: 'xdoc-npm-release-lock/v1'
    source: {
      repository: $SOURCE_REPOSITORY
      tag: $identity.tag
      version: $identity.version
    }
    assets: $assets
  }
}

# Validate all checked-in manifests before preparing or publishing packages.
export def validate-project []: nothing -> record {
  let platforms = (load-platforms)
  let lock = (load-release-lock)
  let package = (open $PACKAGE_PATH)
  let identity = (normalize-release-tag $lock.source.tag)
  let expected_dependencies = (expected-optional-dependencies $identity.version)

  if $identity.version != $lock.source.version {
    fail 'The release lock tag and version do not match.'
  }
  if ($lock.assets | columns | sort) != ($platforms | get id | sort) {
    fail 'The release lock does not contain exactly one entry for every supported platform.'
  }
  if ($package.name? | default '') != '@s8fy/xdoc' {
    fail 'The base package name must be @s8fy/xdoc.'
  }
  if ($package.version? | default '') != $identity.version {
    fail 'The base package version does not match the release lock.'
  }
  if ($package.xdoc.releaseTag? | default '') != $identity.tag {
    fail 'The base package release tag does not match the release lock.'
  }
  if ($package.xdoc.sourceRepository? | default '') != $SOURCE_REPOSITORY {
    fail 'The base package source repository does not match the release lock.'
  }
  if $package.optionalDependencies != $expected_dependencies {
    fail 'The base package optional dependencies do not match the platform manifest.'
  }

  for platform in $platforms {
    let asset = ($lock.assets | get $platform.id)
    if $asset.name != $platform.assetName {
      fail $'Locked asset name does not match the platform manifest for ($platform.id).'
    }
    if $asset.sha256 !~ '^[0-9a-f]{64}$' {
      fail $'Locked SHA-256 is invalid for ($platform.id).'
    }
    if ($asset.sizeBytes | into int) <= 0 {
      fail $'Locked asset size must be positive for ($platform.id).'
    }
  }

  {platforms: $platforms, lock: $lock, package: $package}
}

# Write formatted JSON with a final newline.
export def save-json [path: path, value: any]: nothing -> nothing {
  let json = ($value | to json --indent 2)
  $'($json)(char nl)' | save --force $path
}

# Calculate a file's SHA-256 digest.
export def file-sha256 [path: path]: nothing -> string {
  open --raw $path | hash sha256
}

# Validate an archive path before extraction.
export def validate-archive-entry [entry: string, binary_name: string]: nothing -> string {
  let normalized = (
    $entry
    | str trim
    | str replace --all '\' '/'
    | str replace -r '^\./' ''
    | str trim -r -c '/'
  )

  if ($normalized | is-empty) {
    return ''
  }
  if ($normalized | str starts-with '/') or ($normalized =~ '^[A-Za-z]:') {
    fail $'Archive entry uses an absolute path: ($entry)'
  }
  if ($normalized | split row '/' | any {|component| $component == '..' }) {
    fail $'Archive entry escapes the extraction directory: ($entry)'
  }

  let allowed = (
    $normalized == $binary_name
    or $normalized == 'LICENSE'
    or $normalized == 'licenses-pdfium'
    or ($normalized | str starts-with 'licenses-pdfium/')
  )
  if not $allowed {
    fail $'Unexpected file in upstream archive: ($entry)'
  }

  $normalized
}

# List and validate every archive member before extraction.
export def validate-archive [archive: path, platform: record]: nothing -> list<string> {
  let result = if $platform.archiveType == 'zip' {
    ^unzip -Z1 $archive | complete
  } else {
    ^tar -tzf $archive | complete
  }
  if $result.exit_code != 0 {
    fail $'Failed to list archive entries for ($platform.assetName).' ($result.stderr | str trim)
  }

  let raw_entries = (
    $result.stdout
    | lines
    | where {|entry| $entry | str trim | is-not-empty }
  )
  let entries = (
    $raw_entries
    | each {|entry| validate-archive-entry $entry $platform.binaryName }
    | where {|entry| $entry | is-not-empty }
  )
  if $platform.binaryName not-in $entries {
    fail $'Archive ($platform.assetName) does not contain ($platform.binaryName).'
  }
  if 'LICENSE' not-in $entries {
    fail $'Archive ($platform.assetName) does not contain LICENSE.'
  }
  if not ($entries | any {|entry| $entry | str starts-with 'licenses-pdfium/' }) {
    fail $'Archive ($platform.assetName) does not contain PDFium license notices.'
  }

  let type_result = if $platform.archiveType == 'zip' {
    ^unzip -Z -l $archive | complete
  } else {
    ^tar -tvzf $archive | complete
  }
  if $type_result.exit_code != 0 {
    fail $'Failed to inspect archive entry types for ($platform.assetName).' ($type_result.stderr | str trim)
  }
  let typed_entries = (
    $type_result.stdout
    | lines
    | where {|line| $line =~ '^[bcdlps-]' }
  )
  if ($typed_entries | length) != ($raw_entries | length) {
    fail $'Could not classify every archive entry type for ($platform.assetName).'
  }
  let unsafe_types = (
    $typed_entries
    | where {|line| not (($line | str starts-with '-') or ($line | str starts-with 'd')) }
  )
  if ($unsafe_types | is-not-empty) {
    fail $'Archive ($platform.assetName) contains links, devices, or other unsafe entry types.'
  }

  $entries
}

# Verify that a required external command is available.
export def require-external [name: string]: nothing -> nothing {
  let matches = (which --all $name | where type == external)
  if ($matches | is-empty) {
    fail $'Required command is not installed: ($name)'
  }
}

# Parse the single-package report emitted by npm 11 and npm 12.
export def parse-pack-report [package_dir: path]: string -> record {
  let document = (try {
    $in | from json
  } catch {|error|
    fail $'npm pack returned invalid JSON for ($package_dir).' ($error.msg? | default '')
  })
  let document_type = (($document | describe --detailed).type)
  let reports = if $document_type == 'list' {
    $document
  } else if $document_type == 'record' {
    $document | values
  } else {
    fail $'npm pack returned an unsupported JSON structure for ($package_dir).'
  }

  if ($reports | length) != 1 {
    fail $'npm pack did not return exactly one package report for ($package_dir).'
  }
  let report = ($reports | first)
  if (($report | describe --detailed).type) != 'record' {
    fail $'npm pack returned an invalid package report for ($package_dir).'
  }

  $report
}

# Verify package contents using npm's final packing rules.
export def verify-pack [package_dir: path, required_files: list<string>]: nothing -> record {
  let result = (^npm pack --dry-run --json --ignore-scripts $package_dir | complete)
  if $result.exit_code != 0 {
    fail $'npm pack validation failed for ($package_dir).' ($result.stderr | str trim)
  }

  let report = ($result.stdout | parse-pack-report $package_dir)
  let files = ($report.files | get path)
  for required in $required_files {
    if $required not-in $files {
      fail $'Required package file is missing: ($required)'
    }
  }

  let forbidden = (
    $files
    | where {|file|
        (($file | str starts-with 'tests/') or ($file | str starts-with 'scripts/') or $file == 'release-lock.json' or $file == 'pnpm-workspace.yaml')
      }
  )
  if ($forbidden | is-not-empty) {
    fail $'Forbidden files would be published: ($forbidden | str join ", ")'
  }

  $report
}

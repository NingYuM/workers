#!/usr/bin/env nu

use release-lib.nu *

def file-size [path: path]: nothing -> int {
  ls $path | first | get size | into int
}

def download-asset [asset: record, destination: path] {
  let body = try {
    http get --raw --max-time 10min --headers (github-headers 'application/octet-stream') $asset.url
  } catch {|error|
    fail $'Failed to download upstream asset ($asset.name).' ($error.msg? | default '')
  }
  $body | save $destination
}

def copy-release-files [extract_dir: path, package_dir: path, platform: record] {
  mkdir ($package_dir | path join 'bin')
  cp ($extract_dir | path join $platform.binaryName) ($package_dir | path join 'bin' $platform.binaryName)
  cp ($extract_dir | path join 'LICENSE') ($package_dir | path join 'LICENSE')
  cp --recursive ($extract_dir | path join 'licenses-pdfium') ($package_dir | path join 'licenses-pdfium')

  if $platform.os != 'win32' {
    let chmod = (^chmod 755 ($package_dir | path join 'bin' $platform.binaryName) | complete)
    if $chmod.exit_code != 0 {
      fail $'Failed to mark ($platform.binaryName) as executable.' ($chmod.stderr | str trim)
    }
  }
}

def platform-package [project: record, release: record, platform: record, extract_dir: path, package_dir: path] {
  let locked = ($project.lock.assets | get $platform.id)
  let upstream_asset = (
    $release.assets
    | where name == $platform.assetName
    | first
  )
  let binary_path = ($extract_dir | path join $platform.binaryName)
  if (open --raw ($extract_dir | path join 'LICENSE')) != (open --raw ($PROJECT_DIR | path join 'LICENSE')) {
    fail $'The upstream LICENSE in ($platform.assetName) does not match the reviewed wrapper license.'
  }
  let binary_sha256 = (file-sha256 $binary_path)
  let binary_size = (file-size $binary_path)
  let package_manifest = {
    name: $platform.packageName
    version: $project.lock.source.version
    description: $'Native xdoc binary for ($platform.id).'
    homepage: $PACKAGE_HOMEPAGE
    bugs: {url: $PACKAGE_BUGS_URL}
    license: 'PolyForm-Noncommercial-1.0.0'
    author: 'hustcer'
    repository: {
      type: 'git'
      url: $PACKAGE_GIT_URL
      directory: 'xdoc-npm'
    }
    os: [$platform.os]
    cpu: [$platform.cpu]
    files: ['bin', 'licenses-pdfium', 'provenance.json']
    engines: {node: '>=22.0.0'}
    preferUnplugged: true
    publishConfig: {
      access: 'public'
      provenance: true
      registry: $NPM_REGISTRY
    }
    xdoc: {
      platform: $platform.id
      sourceRepository: $SOURCE_REPOSITORY
      releaseTag: $project.lock.source.tag
      assetName: $platform.assetName
      archiveSha256: $locked.sha256
      binarySha256: $binary_sha256
    }
  }
  let provenance = {
    schemaVersion: 'xdoc-npm-provenance/v1'
    source: {
      repository: $SOURCE_REPOSITORY
      releaseTag: $project.lock.source.tag
      releaseUrl: $release.html_url
    }
    archive: {
      name: $platform.assetName
      url: $upstream_asset.browser_download_url
      sha256: $locked.sha256
      sizeBytes: $locked.sizeBytes
    }
    binary: {
      name: $platform.binaryName
      sha256: $binary_sha256
      sizeBytes: $binary_size
    }
  }

  copy-release-files $extract_dir $package_dir $platform
  save-json ($package_dir | path join 'package.json') $package_manifest
  save-json ($package_dir | path join 'provenance.json') $provenance

  let report = (verify-pack $package_dir [
    'package.json'
    'LICENSE'
    $'bin/($platform.binaryName)'
    'provenance.json'
  ])
  if not ($report.files | get path | any {|path| $path | str starts-with 'licenses-pdfium/' }) {
    fail $'Package ($platform.packageName) does not contain PDFium license notices.'
  }

  {
    kind: 'platform'
    id: $platform.id
    name: $platform.packageName
    version: $project.lock.source.version
    directory: $'packages/($platform.id)'
    archiveSha256: $locked.sha256
    binarySha256: $binary_sha256
    packageIntegrity: $report.integrity
    packageShasum: $report.shasum
  }
}

# Download, verify, and stage every xdoc npm package without publishing.
def main [
  --out: path = './staging' # New staging directory; an existing path is rejected
] {
  require-external 'npm'
  require-external 'tar'
  require-external 'unzip'
  require-external 'chmod'

  let out_dir = ($out | path expand)
  if ($out_dir | path exists) {
    fail $'The staging path already exists: ($out_dir)' 'Choose a new path. The script never deletes existing content.'
  }

  let project = (validate-project)
  let release = (fetch-upstream-release $project.lock.source.tag)
  let live_lock = (lock-from-release $release)
  if $live_lock != $project.lock {
    fail 'The live GitHub release metadata does not match release-lock.json.' 'Run update-release.nu and review the digest changes.'
  }

  mkdir ($out_dir | path join 'downloads')
  mkdir ($out_dir | path join 'extract')
  mkdir ($out_dir | path join 'packages')

  let platform_plans = (
    $project.platforms
    | each {|platform|
        let locked = ($project.lock.assets | get $platform.id)
        let upstream_asset = (
          $release.assets
          | where name == $platform.assetName
          | first
        )
        let archive = ($out_dir | path join 'downloads' $platform.assetName)
        let extract_dir = ($out_dir | path join 'extract' $platform.id)
        let package_dir = ($out_dir | path join 'packages' $platform.id)

        print $'Downloading and verifying ($platform.assetName)...'
        download-asset $upstream_asset $archive
        let actual_size = (file-size $archive)
        if $actual_size != $locked.sizeBytes {
          fail $'Size mismatch for ($platform.assetName): expected ($locked.sizeBytes), got ($actual_size).'
        }
        let actual_sha256 = (file-sha256 $archive)
        if $actual_sha256 != $locked.sha256 {
          fail $'SHA-256 mismatch for ($platform.assetName): expected ($locked.sha256), got ($actual_sha256).'
        }

        validate-archive $archive $platform | ignore
        mkdir $extract_dir
        let extract = if $platform.archiveType == 'zip' {
          ^unzip -q $archive -d $extract_dir | complete
        } else {
          ^tar -xzf $archive -C $extract_dir | complete
        }
        if $extract.exit_code != 0 {
          fail $'Failed to extract ($platform.assetName).' ($extract.stderr | str trim)
        }

        mkdir $package_dir
        platform-package $project $release $platform $extract_dir $package_dir
      }
  )

  let base_dir = ($out_dir | path join 'packages' 'base')
  mkdir $base_dir
  cp $PACKAGE_PATH ($base_dir | path join 'package.json')
  cp ($PROJECT_DIR | path join 'README.md') ($base_dir | path join 'README.md')
  cp ($PROJECT_DIR | path join 'LICENSE') ($base_dir | path join 'LICENSE')
  cp --recursive ($PROJECT_DIR | path join 'lib') ($base_dir | path join 'lib')
  cp $PLATFORMS_PATH ($base_dir | path join 'platforms.json')
  let base_report = (verify-pack $base_dir ['package.json', 'README.md', 'LICENSE', 'lib/index.cjs', 'lib/check-platform.cjs', 'lib/platform.cjs', 'lib/version.cjs', 'platforms.json'])

  let plan = {
    schemaVersion: 'xdoc-npm-release-plan/v1'
    source: $project.lock.source
    packages: ($platform_plans | append {
      kind: 'base'
      id: 'base'
      name: '@s8fy/xdoc'
      version: $project.lock.source.version
      directory: 'packages/base'
      packageIntegrity: $base_report.integrity
      packageShasum: $base_report.shasum
    })
  }
  save-json ($out_dir | path join 'release-plan.json') $plan

  print $'Prepared ($plan.packages | length) packages for ($project.lock.source.tag) in ($out_dir).'
  print 'No package was published and no Git state was changed.'
}

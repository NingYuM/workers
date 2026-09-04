#!/usr/bin/env nu

use std/assert
use ../scripts/release-lib.nu *
use ../scripts/check.nu [cjs-source-paths normalize-glob-path]
use ../scripts/publish-release.nu [
  package-path
  parse-registry-metadata
  validate-dist-tag
  validate-existing
]

let project = (validate-project)

assert equal ($project.platforms | length) 4
assert equal $project.lock.source.tag $'v($project.lock.source.version)'
assert equal $project.package.version $project.lock.source.version
assert ($project.lock.assets.linux-x64.sha256 =~ '^[0-9a-f]{64}$')

assert equal (normalize-release-tag '0.3.10') {tag: 'v0.3.10', version: '0.3.10'}
assert equal (normalize-release-tag 'v0.3.10') {tag: 'v0.3.10', version: '0.3.10'}
assert error {|| normalize-release-tag 'not-a-version' }

assert equal (validate-archive-entry './xdoc' 'xdoc') 'xdoc'
assert equal (validate-archive-entry 'licenses-pdfium/pdfium.txt' 'xdoc') 'licenses-pdfium/pdfium.txt'
assert error {|| validate-archive-entry '../xdoc' 'xdoc' }
assert error {|| validate-archive-entry '/tmp/xdoc' 'xdoc' }
assert error {|| validate-archive-entry 'unexpected.dll' 'xdoc' }

assert equal (validate-dist-tag 'latest') 'latest'
assert equal (validate-dist-tag 'next-1') 'next-1'
assert error {|| validate-dist-tag '0.3.10' }
assert error {|| validate-dist-tag '../latest' }
let staging_dir = ($PROJECT_DIR | path join '.test-staging')
assert equal (package-path $staging_dir 'packages/base') ($staging_dir | path join 'packages' 'base')
assert error {|| package-path $staging_dir '../outside' }

let npm_11_pack_json = '[{"name":"@s8fy/xdoc","files":[{"path":"package.json"}]}]'
let npm_12_pack_json = '{"@s8fy/xdoc":{"name":"@s8fy/xdoc","files":[{"path":"package.json"}]}}'
let expected_pack_report = {name: '@s8fy/xdoc', files: [{path: 'package.json'}]}
assert equal ($npm_11_pack_json | parse-pack-report '/tmp/xdoc-npm') $expected_pack_report
assert equal ($npm_12_pack_json | parse-pack-report '/tmp/xdoc-npm') $expected_pack_report

let npm_11_registry_json = '{"name":"@s8fy/xdoc","version":"0.3.11"}'
let npm_12_registry_json = '[{"name":"@s8fy/xdoc","version":"0.3.11"}]'
let expected_registry_metadata = {name: '@s8fy/xdoc', version: '0.3.11'}
assert equal ($npm_11_registry_json | parse-registry-metadata '@s8fy/xdoc@0.3.11') $expected_registry_metadata
assert equal ($npm_12_registry_json | parse-registry-metadata '@s8fy/xdoc@0.3.11') $expected_registry_metadata
assert error {|| '[]' | parse-registry-metadata '@s8fy/xdoc@0.3.11' }
assert error {|| '[{"name":"first"},{"name":"second"}]' | parse-registry-metadata '@s8fy/xdoc@0.3.11' }

let base_plan = {
  kind: 'base'
  name: $project.package.name
  version: $project.package.version
  packageIntegrity: 'sha512-expected'
  packageShasum: 'expected-shasum'
}
let existing_base = {
  name: $project.package.name
  version: $project.package.version
  xdoc: $project.package.xdoc
  dist: {
    integrity: $base_plan.packageIntegrity
    shasum: $base_plan.packageShasum
  }
  optionalDependencies: $project.package.optionalDependencies
  'dist-tags': {latest: $project.package.version}
}
assert (validate-existing $base_plan $PROJECT_DIR $existing_base 'latest')
assert not (validate-existing $base_plan $PROJECT_DIR ($existing_base | update 'dist-tags' {latest: '0.3.10'}) 'latest')
assert error {|| validate-existing $base_plan $PROJECT_DIR ($existing_base | update name '@s8fy/not-xdoc') 'latest' }
assert error {|| validate-existing $base_plan $PROJECT_DIR ($existing_base | update xdoc.releaseTag 'v0.0.0') 'latest' }
assert error {|| validate-existing $base_plan $PROJECT_DIR ($existing_base | update dist.integrity 'sha512-different') 'latest' }
assert error {|| validate-existing $base_plan $PROJECT_DIR ($existing_base | update dist.shasum 'different-shasum') 'latest' }
assert error {|| validate-existing $base_plan $PROJECT_DIR ($existing_base | update optionalDependencies {}) 'latest' }

let cjs_source_names = (cjs-source-paths | each {|source| $source | path basename })
assert ('index.cjs' in $cjs_source_names)
assert ('verify-installed.cjs' in $cjs_source_names)
assert ('launcher.test.cjs' in $cjs_source_names)
assert equal ('D:\a\workers\workers\xdoc-npm\lib\**\*.cjs' | normalize-glob-path) 'D:/a/workers/workers/xdoc-npm/lib/**/*.cjs'

let publish_workflow = (open --raw ($PROJECT_DIR | path join '..' '.github' 'workflows' 'xdoc-npm-publish.yml'))
assert ($publish_workflow | str contains 'xdoc npm releases must run from hustcer/workers.')

print 'Release manifest tests passed.'

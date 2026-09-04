#!/usr/bin/env nu

use std/assert
use ../scripts/release-lib.nu *
use ../scripts/check.nu [cjs-source-paths normalize-glob-path]
use ../scripts/publish-release.nu [validate-dist-tag package-path]

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

let cjs_source_names = (cjs-source-paths | each {|source| $source | path basename })
assert ('index.cjs' in $cjs_source_names)
assert ('verify-installed.cjs' in $cjs_source_names)
assert ('launcher.test.cjs' in $cjs_source_names)
assert equal ('D:\a\workers\workers\xdoc-npm\lib\**\*.cjs' | normalize-glob-path) 'D:/a/workers/workers/xdoc-npm/lib/**/*.cjs'

print 'Release manifest tests passed.'

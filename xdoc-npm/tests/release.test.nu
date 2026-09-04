#!/usr/bin/env nu

use std/assert
use ../scripts/release-lib.nu *
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
assert equal (package-path '/tmp/xdoc-staging' 'packages/base') '/tmp/xdoc-staging/packages/base'
assert error {|| package-path '/tmp/xdoc-staging' '../outside' }

let npm_11_pack_json = '[{"name":"@s8fy/xdoc","files":[{"path":"package.json"}]}]'
let npm_12_pack_json = '{"@s8fy/xdoc":{"name":"@s8fy/xdoc","files":[{"path":"package.json"}]}}'
let expected_pack_report = {name: '@s8fy/xdoc', files: [{path: 'package.json'}]}
assert equal ($npm_11_pack_json | parse-pack-report '/tmp/xdoc-npm') $expected_pack_report
assert equal ($npm_12_pack_json | parse-pack-report '/tmp/xdoc-npm') $expected_pack_report

print 'Release manifest tests passed.'

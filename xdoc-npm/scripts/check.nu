#!/usr/bin/env nu

use release-lib.nu *

def check-nushell-source [source: path] {
  let result = (^nu --no-config-file --ide-check 100 $source | complete)
  if $result.exit_code != 0 {
    fail $'Nushell parse check failed for ($source).' ($result.stderr | str trim)
  }
  let diagnostics = (
    $result.stdout
    | lines
    | where {|line| $line | str trim | is-not-empty }
    | each {|line|
        try { $line | from json } catch {|error|
          fail $'Nushell returned an invalid IDE diagnostic for ($source).' ($error.msg? | default '')
        }
      }
    | where type != 'hint'
  )
  if ($diagnostics | is-not-empty) {
    fail $'Nushell reported diagnostics for ($source).' ($diagnostics | to json)
  }
}

# Run every local release and package gate without modifying the project.
def main [] {
  require-external 'node'
  require-external 'npm'
  require-external 'nu'

  let launcher_test = ($PROJECT_DIR | path join 'tests/launcher.test.cjs' | into string)
  print 'Running Node.js tests...'
  let node_tests = (^node --test $launcher_test | complete)
  if $node_tests.exit_code != 0 {
    fail 'Node.js tests failed.' ($'($node_tests.stdout)(char nl)($node_tests.stderr)' | str trim)
  }
  print ($node_tests.stdout | str trim)

  for source in (
    glob ($PROJECT_DIR | path join '{lib,scripts,tests}/**/*.cjs')
    | each {|path| $path | into string }
  ) {
    let syntax = (^node --check $source | complete)
    if $syntax.exit_code != 0 {
      fail $'Node.js syntax check failed for ($source).' ($syntax.stderr | str trim)
    }
  }
  print 'Node.js syntax checks passed.'

  print 'Running Nushell release tests...'
  let release_test = ($PROJECT_DIR | path join 'tests/release.test.nu' | into string)
  let nu_tests = (^nu --no-config-file $release_test | complete)
  if $nu_tests.exit_code != 0 {
    fail 'Nushell release tests failed.' ($'($nu_tests.stdout)(char nl)($nu_tests.stderr)' | str trim)
  }
  print ($nu_tests.stdout | str trim)

  for source in (glob ($PROJECT_DIR | path join 'scripts/*.nu') | each {|path| $path | into string }) {
    check-nushell-source $source
  }
  print 'Nushell source checks passed.'

  validate-project | ignore
  verify-pack $PROJECT_DIR [
    'package.json'
    'README.md'
    'LICENSE'
    'lib/index.cjs'
    'lib/check-platform.cjs'
    'lib/platform.cjs'
    'lib/version.cjs'
    'platforms.json'
  ] | ignore
  print 'npm package contents passed.'
  print 'All checks passed.'
}

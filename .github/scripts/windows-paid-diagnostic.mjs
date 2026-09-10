import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, win32 } from 'node:path'
import { pathToFileURL } from 'node:url'

// Diagnostic only: the independently hashed observation is not a release gate.
// Never print candidate output, License facts, private paths or assertion diffs.
const [sourceRoot, artifactRoot, evidenceRoot] = process.argv.slice(2).map((path) => realpathSync(path))
const sourceModule = (name) => import(pathToFileURL(join(sourceRoot, 'tools/lib', name)))
const { runProbeCandidate } = await sourceModule('xdoc-cli-probe-runner.mjs')
const { inspectPaidInstall, inspectPaidStatus, verifyStoredPaidClock } = await sourceModule('xdoc-cli-paid-probe-auth.mjs')
const binary = realpathSync(join(artifactRoot, 'native-facts/xdoc.exe'))
const license = realpathSync(join(evidenceRoot, 'paid/d9fa2cc8/enterprise/xdoc-cli-license.json'))
const digest = (path) => createHash('sha256').update(readFileSync(path)).digest('hex')
assert.equal(digest(binary), '2dc1a94ab8eee5123bcc2d44ca143013e20c59f1ae0fb068d4399a1f2607d6e1')
assert.equal(digest(license), '4130d63fce595601a857dabea690f34c66193f173afa7e9da31a9b7be1e24f50')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'xdoc-paid-diagnostic-')))
let stage = 'setup'
try {
  const config = join(work, 'config')
  mkdirSync(config, { mode: 0o700 })
  const expected = { config, payload: JSON.parse(readFileSync(license)).payload, licenseSha256: digest(license) }
  stage = 'install-command'
  const install = runProbeCandidate({ binary, cwd: work, config, args: ['auth', 'install', license] })
  const body = JSON.parse(install.stdout)
  const reasons = ['cli_license_clock_unavailable', 'cli_license_clock_invalid', 'cli_license_expired', 'cli_license_not_yet_valid', 'cli_license_invalid', 'local_auth_config_path_invalid', 'local_auth_storage_unavailable', 'local_auth_install_failed', 'cli_license_read_failed']
  console.log(JSON.stringify({ stage: 'install-reason', knownReason: reasons.find((reason) => reason === body.reason) ?? 'other' }))
  if (install.exitCode !== 0) {
    stage = 'explicit-directory-owner'
    const identity = execFileSync('whoami.exe', ['/user', '/fo', 'csv', '/nh'], { encoding: 'utf8' })
    const sid = identity.match(/S-1-[0-9-]+/)[0]
    execFileSync('icacls.exe', [config, '/setowner', `*${sid}`], { stdio: 'pipe' })
    const retried = runProbeCandidate({ binary, cwd: work, config, args: ['auth', 'install', license] })
    const retryBody = JSON.parse(retried.stdout)
    console.log(JSON.stringify({ stage, exitCode: retried.exitCode, success: retryBody.status === 'success', knownReason: reasons.find((reason) => reason === retryBody.reason) ?? 'other' }))
    if (retried.exitCode === 0) {
      const verified = inspectPaidInstall(retried, expected)
      verifyStoredPaidClock(config, verified.lastSeenUnixMs)
      console.log(JSON.stringify({ stage: 'explicit-owner-auth', passed: true }))
    }
  }
  console.log(JSON.stringify({ stage, exitCode: install.exitCode, success: body.status === 'success', installed: body.outcome === 'installed', configMatches: body.configDirectory === config, pathMatches: body.installedPath === join(config, 'xdoc-license.json'), digestMatches: body.installedSha256 === expected.licenseSha256, reasonIsStorageUnavailable: body.reason === 'local_auth_storage_unavailable' }))
  stage = 'install-inspection'
  const installed = inspectPaidInstall(install, expected)
  stage = 'stored-clock'
  verifyStoredPaidClock(config, installed.lastSeenUnixMs)
  stage = 'status-inspection'
  const status = runProbeCandidate({ binary, cwd: work, config, args: ['auth', 'status'] })
  const statusBody = JSON.parse(status.stdout)
  const path = statusBody.source?.path ?? ''
  const installedPath = join(config, 'xdoc-license.json')
  console.log(JSON.stringify({ stage: 'status-source', kindMatches: statusBody.source?.kind === 'config-path', pathMatches: path === installedPath, digestMatches: statusBody.source?.sha256 === expected.licenseSha256, normalizedMatches: win32.normalize(path) === installedPath, namespacedMatches: path === win32.toNamespacedPath(installedPath), caseMatches: path.toLowerCase() === installedPath.toLowerCase(), fieldCount: Object.keys(statusBody.source ?? {}).length }))
  console.log(JSON.stringify({ stage: 'status-native-path', namespacedCaseMatches: path.toLowerCase() === win32.toNamespacedPath(installedPath).toLowerCase(), nativeMatches: path === realpathSync.native(installedPath), nativeNamespaceMatches: path === win32.toNamespacedPath(realpathSync.native(installedPath)), readbackMatches: realpathSync.native(path) === realpathSync.native(installedPath) }))
  inspectPaidStatus(status, { ...expected, previousAnchor: installed.lastSeenUnixMs })
  console.log(JSON.stringify({ stage: 'auth-complete', passed: true }))
} catch (error) {
  const line = String(error.stack).match(/xdoc-cli-paid-probe-auth\.mjs:(\d+):/)
  console.log(JSON.stringify({ stage, passed: false, authAssertionLine: line ? Number(line[1]) : null }))
  process.exitCode = 1
} finally {
  rmSync(work, { recursive: true, force: true })
}

import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
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
  console.log(JSON.stringify({ stage, exitCode: install.exitCode, success: body.status === 'success', installed: body.outcome === 'installed', configMatches: body.configDirectory === config, pathMatches: body.installedPath === join(config, 'xdoc-license.json'), digestMatches: body.installedSha256 === expected.licenseSha256, reasonIsStorageUnavailable: body.reason === 'local_auth_storage_unavailable' }))
  stage = 'install-inspection'
  const installed = inspectPaidInstall(install, expected)
  stage = 'stored-clock'
  verifyStoredPaidClock(config, installed.lastSeenUnixMs)
  stage = 'status-inspection'
  inspectPaidStatus(runProbeCandidate({ binary, cwd: work, config, args: ['auth', 'status'] }), { ...expected, previousAnchor: installed.lastSeenUnixMs })
  console.log(JSON.stringify({ stage: 'auth-complete', passed: true }))
} catch (error) {
  const line = String(error.stack).match(/xdoc-cli-paid-probe-auth\.mjs:(\d+):/)
  console.log(JSON.stringify({ stage, passed: false, authAssertionLine: line ? Number(line[1]) : null }))
  process.exitCode = 1
} finally {
  rmSync(work, { recursive: true, force: true })
}

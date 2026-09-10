import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mkdtempSync, readFileSync, realpathSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

// Diagnostic only; never print candidate output, License facts or private paths.
const [sourceRoot, artifactRoot, evidenceRoot] = process.argv.slice(2).map((path) => realpathSync(path))
const sourceModule = (name) => import(pathToFileURL(join(sourceRoot, 'tools/lib', name)))
const { runProbeCandidate } = await sourceModule('xdoc-cli-probe-runner.mjs')
const { createProbeConfigDirectory } = await sourceModule('xdoc-cli-probe-config.mjs')
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
  createProbeConfigDirectory(config)
  const expected = { config, payload: JSON.parse(readFileSync(license)).payload, licenseSha256: digest(license) }
  stage = 'install-inspection'
  const installed = inspectPaidInstall(runProbeCandidate({ binary, cwd: work, config, args: ['auth', 'install', license] }), expected)
  stage = 'installed-clock'
  verifyStoredPaidClock(config, installed.lastSeenUnixMs)
  stage = 'status-inspection'
  const status = inspectPaidStatus(runProbeCandidate({ binary, cwd: work, config, args: ['auth', 'status'] }), { ...expected, previousAnchor: installed.lastSeenUnixMs })
  stage = 'status-clock'
  verifyStoredPaidClock(config, status.lastSeenUnixMs)
  console.log(JSON.stringify({ stage: 'auth-complete', passed: true }))
} catch (error) {
  const line = String(error.stack).match(/xdoc-cli-paid-probe-auth\.mjs:(\d+):/)
  console.log(JSON.stringify({ stage, passed: false, authAssertionLine: line ? Number(line[1]) : null }))
  process.exitCode = 1
} finally {
  rmSync(work, { recursive: true, force: true })
}

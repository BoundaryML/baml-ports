// Generates the testset body of baml_src/tests/doc/YAML-1.2.spec.baml from tests/doc/YAML-1.2.spec.ts
// (evaluates the upstream `spec` object in node). Usage: node tools/gen_yaml12_spec.cjs > body.baml,
// then replace `special: SPECIAL_<n>,` with `special: (src: string) -> null { tspec_sp_<n>(src) },`.
const fs = require('fs')
const txt = fs.readFileSync(process.env.HOME + '/work-repos/yaml-baml-port-src/tests/doc/YAML-1.2.spec.ts', 'utf8')
const start = txt.indexOf('> = {', txt.indexOf('const spec')) + 4
const end = txt.indexOf('\nconst mockWarn')
let body = txt.slice(start, end)
// strip TS generics / annotations in special functions
body = body.replace(/\(str: string\)/g, '(str)').replace(/parseDocument<[^(]*>\(/g, 'parseDocument(')
const collectionKeyWarning = /^Keys with collection values will be stringified due to JS Object restrictions/
const spec = eval('(' + body + ')')

function bstr(s) {
  let out = '"', parts = []
  for (const ch of s) {
    const c = ch.codePointAt(0)
    if (ch === '\\') out += '\\\\'
    else if (ch === '"') out += '\\"'
    else if (ch === '\n') out += '\\n'
    else if (ch === '\t') out += '\\t'
    else if (ch === '\r') out += '\\r'
    else if (c < 0x20 || c === 0x7f || (c >= 0x80 && c < 0xa0) || c === 0xfeff || c === 0x2028 || c === 0x2029) {
      out += '" + chr(' + c + ') + "'
    } else out += ch
  }
  out += '"'
  return out.replace(/^"" \+ /, '').replace(/ \+ ""$/, '')
}
function num(n) {
  if (Number.isNaN(n)) return 'baml.Float.nan()'
  if (n === Infinity) return 'baml.Float.inf()'
  if (n === -Infinity) return '(0.0 - baml.Float.inf())'
  if (Number.isInteger(n)) return String(n)
  const s = String(n)
  if (/e/.test(s)) throw new Error('exp float ' + s)
  return s
}
function val(v, ind) {
  const pad = '  '.repeat(ind)
  if (v === null || v === undefined) return 'null'
  if (typeof v === 'string') return bstr(v)
  if (typeof v === 'number') return num(v)
  if (typeof v === 'boolean') return String(v)
  if (Array.isArray(v)) {
    if (v.length === 0) return '[]'
    const items = v.map(x => val(x, ind + 1))
    const one = '[' + items.join(', ') + ']'
    if (one.length < 80 && !one.includes('\n')) return one
    return '[\n' + items.map(i => pad + '  ' + i).join(',\n') + '\n' + pad + ']'
  }
  if (v instanceof Set) return 'tspec_set(' + val([...v], ind) + ')'
  if (v instanceof Map) return 'tspec_jsmap(' + val([...v].map(e => [...e]), ind) + ')'
  if (v instanceof Uint8Array) return 'tspec_bytes(' + val([...v], ind) + ')'
  if (Object.getPrototypeOf(v) !== Object.prototype) throw new Error('unknown obj ' + v)
  const keys = Object.keys(v)
  if (keys.length === 0) return 'tspec_obj()'
  for (const k of keys) if (bstr(k).includes('chr(')) throw new Error('bad key ' + k)
  const items = keys.map(k => bstr(k) + ': ' + val(v[k], ind + 1))
  const one = '{ ' + items.join(', ') + ' }'
  if (one.length < 80 && !one.includes('\n')) return one
  return '{\n' + items.map(i => pad + '  ' + i).join(',\n') + '\n' + pad + '}'
}
let out = []
let idx = 0
for (const section in spec) {
  out.push(`  testset ${bstr(section)} {`)
  for (const name in spec[section]) {
    idx++
    const c = spec[section][name]
    out.push(`    test ${bstr(name)} {`)
    out.push(`      tspec_run(TspecCase {`)
    out.push(`        src: ${bstr(c.src)},`)
    out.push(`        tgt: ${val(c.tgt, 4)},`)
    if (c.errors) out.push(`        errors: ${val(c.errors, 4)},`)
    if (c.warnings) out.push(`        warnings: ${val(c.warnings, 4)},`)
    if (c.jsWarnings) out.push(`        jsWarnings: true,`)
    if (c.special) {
      out.push(`        // special: ${c.special.toString().split('\n').join('\n        // ')}`)
      out.push(`        special: SPECIAL_${idx},`)
    }
    out.push(`      })`)
    out.push(`    }`)
    out.push('')
  }
  if (out[out.length - 1] === '') out.pop()
  out.push(`  }`)
  out.push('')
}
out.pop()
console.log(out.join('\n'))
console.error('cases', idx)

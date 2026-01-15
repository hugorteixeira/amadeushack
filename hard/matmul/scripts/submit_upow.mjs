import { readFileSync } from 'fs'
import { dirname, resolve } from 'path'
import { fileURLToPath } from 'url'
import bs58 from 'bs58'
import { bls12_381 as bls } from '@noble/curves/bls12-381'
import { sha256 } from '@noble/hashes/sha2'

const DST_TX = 'AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_TX_'
const SEED_LEN = 64
const BLS12_381_ORDER = BigInt(
  '0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001'
)

function getArg(flag) {
  const idx = process.argv.indexOf(flag)
  if (idx === -1 || idx + 1 >= process.argv.length) return null
  return process.argv[idx + 1]
}

function normalizeBaseUrl(url) {
  return url.replace(/\/+$/, '')
}

function reduce512To256LE(bytes64) {
  if (!(bytes64 instanceof Uint8Array) || bytes64.length !== SEED_LEN) {
    throw new Error('Expected 64-byte Uint8Array seed')
  }
  let x = BigInt(0)
  for (let i = 0; i < SEED_LEN; i += 1) {
    x += BigInt(bytes64[i]) << (BigInt(8) * BigInt(i))
  }
  x = x % BLS12_381_ORDER
  const out = new Uint8Array(32)
  for (let i = 31; i >= 0; i -= 1) {
    out[i] = Number(x & BigInt(0xff))
    x >>= BigInt(8)
  }
  return out
}

function deriveSkAndSeed64FromBase58Seed(base58Seed64) {
  const seed64 = bs58.decode(base58Seed64)
  if (seed64.length !== SEED_LEN) {
    throw new Error('Invalid base58 seed: must be 64 bytes')
  }
  const sk = reduce512To256LE(seed64)
  return { sk, seed64 }
}

function getPublicKey(seed64) {
  const sk = reduce512To256LE(seed64)
  return bls.longSignatures.getPublicKey(sk).toBytes()
}

const TYPE_NULL = 0x00
const TYPE_TRUE = 0x01
const TYPE_FALSE = 0x02
const TYPE_INT = 0x03
const TYPE_BYTES = 0x05
const TYPE_LIST = 0x06
const TYPE_MAP = 0x07

function appendBytes(out, bytes) {
  for (const b of bytes) out.push(b)
}

function compareBytes(a, b) {
  const n = Math.min(a.length, b.length)
  for (let i = 0; i < n; i += 1) {
    if (a[i] !== b[i]) return a[i] - b[i]
  }
  return a.length - b.length
}

function encodeVarint(n, out) {
  let value = typeof n === 'bigint' ? n : BigInt(n)
  if (value === 0n) {
    out.push(0)
    return
  }
  const isNegative = value < 0n
  if (isNegative) value = -value
  const magBytes = []
  while (value > 0n) {
    magBytes.push(Number(value & 0xffn))
    value >>= 8n
  }
  magBytes.reverse()
  const len = magBytes.length
  if (len === 0 || len > 16) throw new Error('bad_varint_length')
  if (magBytes[0] === 0) throw new Error('varint_leading_zero')
  const header = ((isNegative ? 1 : 0) << 7) | len
  out.push(header)
  appendBytes(out, magBytes)
}

function encodeTerm(value, out) {
  if (value === null) {
    out.push(TYPE_NULL)
  } else if (typeof value === 'boolean') {
    out.push(value ? TYPE_TRUE : TYPE_FALSE)
  } else if (typeof value === 'number' || typeof value === 'bigint') {
    out.push(TYPE_INT)
    encodeVarint(value, out)
  } else if (typeof value === 'string') {
    out.push(TYPE_BYTES)
    const utf8 = new TextEncoder().encode(value)
    encodeVarint(utf8.length, out)
    appendBytes(out, utf8)
  } else if (value instanceof Uint8Array) {
    out.push(TYPE_BYTES)
    encodeVarint(value.length, out)
    appendBytes(out, value)
  } else if (Array.isArray(value)) {
    out.push(TYPE_LIST)
    encodeVarint(value.length, out)
    for (const element of value) encodeTerm(element, out)
  } else if (typeof value === 'object') {
    const entries = []
    for (const k of Object.keys(value)) {
      const bytes = []
      encodeTerm(k, bytes)
      entries.push({ k, v: value[k], bytes })
    }
    entries.sort((a, b) => compareBytes(a.bytes, b.bytes))
    out.push(TYPE_MAP)
    encodeVarint(entries.length, out)
    for (const entry of entries) {
      encodeTerm(entry.k, out)
      encodeTerm(entry.v, out)
    }
  } else {
    throw new Error(`Unsupported type: ${typeof value}`)
  }
}

function encode(term) {
  const out = []
  encodeTerm(term, out)
  return new Uint8Array(out)
}

function buildTxPacked({ seedBase58, contract, method, args }) {
  const { sk, seed64 } = deriveSkAndSeed64FromBase58Seed(seedBase58)
  const pk = getPublicKey(seed64)
  const tx = {
    signer: pk,
    nonce: BigInt(Date.now()) * 1_000_000n,
    action: {
      op: 'call',
      contract,
      function: method,
      args
    }
  }
  const txEncoded = encode(tx)
  const hash = sha256(txEncoded)
  const signature = bls.sign(hash, sk, { DST: DST_TX })
  const txPacked = encode({ tx, hash, signature })
  return { txPacked, txHash: bs58.encode(hash) }
}

async function main() {
  const scriptDir = dirname(fileURLToPath(import.meta.url))
  const matmulDir = resolve(scriptDir, '..')
  const solutionPath =
    process.env.SOLUTION_BIN ||
    getArg('--solution') ||
    resolve(matmulDir, 'build_ttnn/solution.bin')
  const seedBase58 = process.env.AMA_SEED_BASE58 || getArg('--seed-base58')
  const rpcBase = normalizeBaseUrl(
    process.env.AMA_RPC ||
      process.env.RPC_URL ||
      getArg('--rpc') ||
      'https://testnet.ama.one'
  )
  const contract = getArg('--contract') || 'Epoch'
  const method = getArg('--function') || 'submit_sol'
  const argMode = (process.env.SUBMIT_SOL_AS || getArg('--as') || 'bytes').toLowerCase()

  if (!seedBase58) {
    console.error('Missing AMA_SEED_BASE58 (wallet seed, not API key)')
    process.exit(1)
  }

  const solBytes = new Uint8Array(readFileSync(solutionPath))
  if (solBytes.length !== 1264) {
    console.warn(`Warning: solution size is ${solBytes.length} bytes (expected 1264)`)
  }

  const args = [
    argMode === 'base58' ? bs58.encode(solBytes) : solBytes
  ]

  const { txPacked, txHash } = buildTxPacked({
    seedBase58,
    contract,
    method,
    args
  })

  const endpoint = `${rpcBase}/api/tx/submit_and_wait`
  const res = await fetch(endpoint, {
    method: 'POST',
    body: txPacked,
    headers: { 'Content-Type': 'application/octet-stream' }
  })
  const text = await res.text()
  let json = null
  try {
    json = JSON.parse(text)
  } catch {}
  if (!res.ok) {
    console.error(`HTTP ${res.status}: ${text}`)
    process.exit(1)
  }
  console.log(`tx_hash=${txHash}`)
  if (json) {
    console.log(JSON.stringify(json, null, 2))
  } else {
    console.log(text)
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})

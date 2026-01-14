import crypto from 'crypto'
import { writeFile } from 'fs/promises'
import bs58 from 'bs58'
import { bls12_381 as bls } from '@noble/curves/bls12-381'
import { blake3 } from '@noble/hashes/blake3'

const DST_POP = 'AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_'
const SEED_LEN = 64
const BLS12_381_ORDER = BigInt(
  '0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001'
)

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

function seed64ToKeypair(seed64) {
  const sk = reduce512To256LE(seed64)
  const pk = bls.longSignatures.getPublicKey(sk).toBytes()
  return [pk, sk]
}

function getPublicKey(seed64) {
  return seed64ToKeypair(seed64)[0]
}

function deriveSkAndSeed64FromBase58Seed(base58Seed64) {
  const seed64 = bs58.decode(base58Seed64)
  if (seed64.length !== SEED_LEN) {
    throw new Error('Invalid base58Seed: must be 64 bytes.')
  }
  const sk = reduce512To256LE(seed64)
  return { sk, seed64 }
}

function generateKeypair() {
  const seed64 = crypto.randomBytes(SEED_LEN)
  const [pk] = seed64ToKeypair(seed64)
  return {
    publicKey: bs58.encode(pk),
    privateKey: bs58.encode(seed64)
  }
}

function toBase58(bytes) {
  return bs58.encode(bytes)
}

function getArg(flag) {
  const idx = process.argv.indexOf(flag)
  if (idx === -1 || idx + 1 >= process.argv.length) return null
  return process.argv[idx + 1]
}

function u32le(num) {
  const buf = Buffer.alloc(4)
  buf.writeUInt32LE(num >>> 0, 0)
  return buf
}

function tryDecodeString(str, expectedLen) {
  const base58Re = /^[1-9A-HJ-NP-Za-km-z]+$/
  const base64Re = /^[A-Za-z0-9+/=]+$/
  if (base58Re.test(str)) {
    try {
      const b58 = bs58.decode(str)
      if (!expectedLen || b58.length === expectedLen) return b58
    } catch {}
  }
  if (base64Re.test(str)) {
    try {
      const b64 = new Uint8Array(Buffer.from(str, 'base64'))
      if (!expectedLen || b64.length === expectedLen) return b64
    } catch {}
  }
  const utf8 = new Uint8Array(Buffer.from(str, 'utf8'))
  if (!expectedLen || utf8.length === expectedLen) return utf8
  const latin1 = new Uint8Array(Buffer.from(str, 'latin1'))
  if (!expectedLen || latin1.length === expectedLen) return latin1
  return null
}

function decodeJsonBinary(text, expectedLen) {
  const parsed = JSON.parse(text)
  if (typeof parsed === 'string') {
    const decoded = tryDecodeString(parsed, expectedLen)
    if (decoded) return decoded
  }
  if (Array.isArray(parsed)) {
    const arr = Uint8Array.from(parsed)
    if (!expectedLen || arr.length === expectedLen) return arr
  }
  if (parsed && typeof parsed === 'object') {
    if (Array.isArray(parsed.result)) {
      const arr = Uint8Array.from(parsed.result)
      if (!expectedLen || arr.length === expectedLen) return arr
    }
    if (typeof parsed.result === 'string') {
      const decoded = tryDecodeString(parsed.result, expectedLen)
      if (decoded) return decoded
    }
  }
  throw new Error('Unsupported response for binary payload')
}

async function fetchEpoch(rpc) {
  const res = await fetch(`${rpc}/api/chain/stats`)
  if (!res.ok) throw new Error(`chain/stats failed: ${res.status}`)
  const data = await res.json()
  if (data?.stats?.epoch !== undefined) return data.stats.epoch
  if (data?.epoch !== undefined) return data.epoch
  if (data?.stats?.height !== undefined) {
    return Math.floor(Number(data.stats.height) / 100000)
  }
  if (data?.stats?.tip?.header?.height !== undefined) {
    return Math.floor(Number(data.stats.tip.header.height) / 100000)
  }
  // Fallback: /api/chain/tip
  const tipRes = await fetch(`${rpc}/api/chain/tip`)
  if (!tipRes.ok) throw new Error(`chain/tip failed: ${tipRes.status}`)
  const tipData = await tipRes.json()
  const height = tipData?.entry?.header?.height
  if (height === undefined) throw new Error('epoch not found in chain stats')
  return Math.floor(Number(height) / 100000)
}

async function fetchSegmentVrHash(rpc) {
  try {
    const key = new TextEncoder().encode('bic:epoch:segment_vr_hash')
    const res = await fetch(`${rpc}/api/contract/get`, {
      method: 'POST',
      body: key,
      headers: { 'Content-Type': 'application/octet-stream' }
    })
    if (!res.ok) throw new Error(`contract/get failed: ${res.status}`)
    const text = await res.text()
    const bytes = decodeJsonBinary(text, 32)
    if (bytes.length !== 32) {
      throw new Error(`segment_vr_hash length ${bytes.length}, expected 32`)
    }
    return bytes
  } catch (err) {
    const bytes = await fetchSegmentVrHashFromChain(rpc)
    console.warn(`contract/get failed, using chain-derived segment_vr_hash (${err.message})`)
    return bytes
  }
}

async function fetchSegmentVrHashFromChain(rpc) {
  const res = await fetch(`${rpc}/api/chain/stats`)
  if (!res.ok) throw new Error(`chain/stats failed: ${res.status}`)
  const data = await res.json()
  const height =
    data?.stats?.height ??
    data?.stats?.tip?.header?.height ??
    data?.tip?.header?.height
  if (height === undefined) throw new Error('height not found for segment_vr_hash')
  const segmentHeight = Math.floor(Number(height) / 1000) * 1000
  const entryRes = await fetch(`${rpc}/api/chain/height/${segmentHeight}`)
  if (!entryRes.ok) throw new Error(`chain/height failed: ${entryRes.status}`)
  const entryData = await entryRes.json()
  const entry = entryData?.entries?.[0]
  const vrB58 = entry?.header?.vr
  if (!vrB58) throw new Error('vr not found in chain height response')
  const vrBytes = bs58.decode(vrB58)
  return blake3(vrBytes)
}

function buildSeed({ epoch, segmentVrHash, pk, pop, nonce, solverPk }) {
  const seed = Buffer.concat([
    u32le(epoch),
    Buffer.from(segmentVrHash),
    Buffer.from(pk),
    Buffer.from(pop),
    Buffer.from(solverPk),
    Buffer.from(nonce)
  ])
  if (seed.length !== 240) {
    throw new Error(`seed length ${seed.length}, expected 240`)
  }
  return seed
}

async function main() {
  const rpc = getArg('--rpc') || 'https://nodes.amadeus.bot'
  const out = getArg('--out') || 'seed.bin'
  const seedBase58 = getArg('--seed-base58')
  const useGenerate = process.argv.includes('--generate')
  const printHex = !process.argv.includes('--no-hex')

  let seed64Base58 = seedBase58
  if (!seed64Base58) {
    if (!useGenerate) {
      console.error('Missing --seed-base58. Use --generate to create one.')
      process.exit(1)
    }
    const kp = generateKeypair()
    seed64Base58 = kp.privateKey
    console.log(`Generated seed-base58: ${seed64Base58}`)
    console.log(`Public key: ${kp.publicKey}`)
  }

  const { sk, seed64 } = deriveSkAndSeed64FromBase58Seed(seed64Base58)
  const pk = getPublicKey(seed64)
  const pop = bls.sign(pk, sk, { DST: DST_POP })
  const solverPk = pk
  const nonce = crypto.randomBytes(12)

  const epoch = await fetchEpoch(rpc)
  const segmentVrHash = await fetchSegmentVrHash(rpc)

  const seed = buildSeed({ epoch, segmentVrHash, pk, pop, nonce, solverPk })
  await writeFile(out, seed)

  console.log(`Seed written to ${out}`)
  if (printHex) {
    console.log(`seed_hex=${Buffer.from(seed).toString('hex')}`)
  }
  console.log(`epoch=${epoch}`)
  console.log(`segment_vr_hash_b58=${toBase58(segmentVrHash)}`)
  console.log(`pk_b58=${toBase58(pk)}`)
  console.log(`pop_b58=${toBase58(pop)}`)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})

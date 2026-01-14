#include <cstdint>
#include <cstdio>
#include <cstring>
#include <unistd.h>

#include "blake3.h"

#ifndef MERKLE_LEAVES
#define MERKLE_LEAVES 1024
#endif

#ifndef MERKLE_PROOFS
#define MERKLE_PROOFS 16
#endif

#ifndef MERKLE_ITERS
#define MERKLE_ITERS 1
#endif

#ifndef MERKLE_PROGRESS
#define MERKLE_PROGRESS 0
#endif

#ifndef MERKLE_SEED_HEX
#define MERKLE_SEED_HEX "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
#endif

namespace {
constexpr size_t kHashSize = 32;
constexpr size_t kSeedSize = 32;
constexpr size_t kTotalNodes = 2 * MERKLE_LEAVES - 1;
constexpr size_t kLeafBase = MERKLE_LEAVES - 1;

uint8_t g_tree[kTotalNodes * kHashSize];
uint8_t g_seed[kSeedSize];

int hex_val(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

bool hex_to_bytes(const char *hex, uint8_t *out, size_t out_len) {
    size_t len = std::strlen(hex);
    if (len != out_len * 2) return false;
    for (size_t i = 0; i < out_len; ++i) {
        int hi = hex_val(hex[2 * i]);
        int lo = hex_val(hex[2 * i + 1]);
        if (hi < 0 || lo < 0) return false;
        out[i] = static_cast<uint8_t>((hi << 4) | lo);
    }
    return true;
}

static size_t u64_to_dec(char *dst, uint64_t value) {
    char tmp[32];
    size_t pos = 0;
    if (value == 0) {
        dst[0] = '0';
        return 1;
    }
    while (value > 0) {
        tmp[pos++] = static_cast<char>('0' + (value % 10));
        value /= 10;
    }
    for (size_t i = 0; i < pos; ++i) {
        dst[i] = tmp[pos - 1 - i];
    }
    return pos;
}

inline uint8_t *node_ptr(size_t idx) {
    return g_tree + idx * kHashSize;
}

void hash_leaf(uint32_t idx, uint8_t out[kHashSize]) {
    blake3_hasher h;
    blake3_hasher_init(&h);
    blake3_hasher_update(&h, g_seed, sizeof(g_seed));
    uint8_t idx_bytes[4] = {
        static_cast<uint8_t>(idx & 0xff),
        static_cast<uint8_t>((idx >> 8) & 0xff),
        static_cast<uint8_t>((idx >> 16) & 0xff),
        static_cast<uint8_t>((idx >> 24) & 0xff),
    };
    blake3_hasher_update(&h, idx_bytes, sizeof(idx_bytes));
    blake3_hasher_finalize(&h, out, kHashSize);
}

void hash_node(const uint8_t *left, const uint8_t *right, uint8_t out[kHashSize]) {
    blake3_hasher h;
    blake3_hasher_init(&h);
    blake3_hasher_update(&h, left, kHashSize);
    blake3_hasher_update(&h, right, kHashSize);
    blake3_hasher_finalize(&h, out, kHashSize);
}

bool is_power_of_two(size_t v) {
    return v && ((v & (v - 1)) == 0);
}

void build_tree() {
    for (size_t i = 0; i < MERKLE_LEAVES; ++i) {
        hash_leaf(static_cast<uint32_t>(i), node_ptr(kLeafBase + i));
    }
    for (size_t i = kLeafBase; i-- > 0;) {
        hash_node(node_ptr(2 * i + 1), node_ptr(2 * i + 2), node_ptr(i));
    }
}

size_t build_proof(uint32_t leaf_idx, uint8_t *path, size_t max_path) {
    size_t node = kLeafBase + leaf_idx;
    size_t depth = 0;
    while (node > 0 && depth + 1 <= max_path) {
        size_t sibling = (node % 2 == 0) ? node - 1 : node + 1;
        std::memcpy(path + depth * kHashSize, node_ptr(sibling), kHashSize);
        node = (node - 1) / 2;
        depth++;
    }
    return depth;
}

bool verify_proof(uint32_t leaf_idx, const uint8_t *path, size_t depth) {
    uint8_t cur[kHashSize];
    uint8_t tmp[kHashSize];
    hash_leaf(leaf_idx, cur);

    size_t node = kLeafBase + leaf_idx;
    for (size_t i = 0; i < depth; ++i) {
        const uint8_t *sib = path + i * kHashSize;
        if (node % 2 == 1) {
            hash_node(cur, sib, tmp);
        } else {
            hash_node(sib, cur, tmp);
        }
        std::memcpy(cur, tmp, kHashSize);
        node = (node - 1) / 2;
    }
    return std::memcmp(cur, node_ptr(0), kHashSize) == 0;
}
} // namespace

int main() {
    if (!is_power_of_two(MERKLE_LEAVES)) {
        const char msg[] = "MERKLE_LEAVES must be power of two\n";
        (void)write(2, msg, sizeof(msg) - 1);
        return 1;
    }
    if (!hex_to_bytes(MERKLE_SEED_HEX, g_seed, sizeof(g_seed))) {
        const char msg[] = "Invalid MERKLE_SEED_HEX\n";
        (void)write(2, msg, sizeof(msg) - 1);
        return 1;
    }

    build_tree();

    uint8_t path[32 * 20];
    uint64_t checksum = 0;
    uint64_t total = static_cast<uint64_t>(MERKLE_PROOFS) * static_cast<uint64_t>(MERKLE_ITERS);

    for (uint32_t iter = 0; iter < MERKLE_ITERS; ++iter) {
#if MERKLE_PROGRESS
        const char tag[] = "iter=";
        char pbuf[32];
        size_t pidx = 0;
        std::memcpy(pbuf + pidx, tag, sizeof(tag) - 1);
        pidx += sizeof(tag) - 1;
        pidx += u64_to_dec(pbuf + pidx, static_cast<uint64_t>(iter + 1));
        pbuf[pidx++] = '\n';
        (void)write(2, pbuf, pidx);
#endif
        for (uint32_t i = 0; i < MERKLE_PROOFS; ++i) {
            uint32_t idx = (i * 2654435761u + iter) & (MERKLE_LEAVES - 1);
            size_t depth = build_proof(idx, path, 20);
            bool ok = verify_proof(idx, path, depth);
            checksum += ok ? 1 : 0;
            checksum += node_ptr(0)[0];
        }
    }

    char buf[256];
    size_t pos = 0;
    const char p1[] = "{\"mode\":\"merkle_baremetal\",\"leaves\":";
    std::memcpy(buf + pos, p1, sizeof(p1) - 1);
    pos += sizeof(p1) - 1;
    pos += u64_to_dec(buf + pos, MERKLE_LEAVES);
    const char p2[] = ",\"proofs\":";
    std::memcpy(buf + pos, p2, sizeof(p2) - 1);
    pos += sizeof(p2) - 1;
    pos += u64_to_dec(buf + pos, MERKLE_PROOFS);
    const char p3[] = ",\"iters\":";
    std::memcpy(buf + pos, p3, sizeof(p3) - 1);
    pos += sizeof(p3) - 1;
    pos += u64_to_dec(buf + pos, MERKLE_ITERS);
    const char p4[] = ",\"total_proofs\":";
    std::memcpy(buf + pos, p4, sizeof(p4) - 1);
    pos += sizeof(p4) - 1;
    pos += u64_to_dec(buf + pos, total);
    const char p5[] = ",\"checksum\":";
    std::memcpy(buf + pos, p5, sizeof(p5) - 1);
    pos += sizeof(p5) - 1;
    pos += u64_to_dec(buf + pos, checksum);
    buf[pos++] = '}';
    buf[pos++] = '\n';
    (void)write(1, buf, pos);
    return 0;
}

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#ifndef TT_BAREMETAL
#include <algorithm>
#include <chrono>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <vector>
#endif

#ifdef _OPENMP
#include <omp.h>
#endif

#include "blake3.h"

#ifdef TT_BAREMETAL
#include <unistd.h>
namespace {
constexpr size_t kSeedSize = 240;
constexpr size_t kABytes = 16 * 50240;
constexpr size_t kBBytes = 50240 * 16;
constexpr size_t kABBytes = kABytes + kBBytes;

uint8_t g_ab[kABBytes];
int32_t g_c[16 * 16];

#ifndef TT_CPU_HZ
#define TT_CPU_HZ 1000000000ULL
#endif

#ifndef TT_USE_RDCYCLE
#define TT_USE_RDCYCLE 0
#endif

static inline uint64_t rdcycle() {
#if defined(__riscv) && __riscv_xlen == 32
    uint32_t hi1, lo, hi2;
    do {
        asm volatile("rdcycleh %0" : "=r"(hi1));
        asm volatile("rdcycle %0" : "=r"(lo));
        asm volatile("rdcycleh %0" : "=r"(hi2));
    } while (hi1 != hi2);
    return (static_cast<uint64_t>(hi2) << 32) | lo;
#elif defined(__riscv)
    uint64_t cycles;
    asm volatile("rdcycle %0" : "=r"(cycles));
    return cycles;
#else
    return 0;
#endif
}

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

int run_baremetal(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    const char *seed_hex = nullptr;
    bool no_output = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--seed-hex") == 0 && i + 1 < argc) {
            seed_hex = argv[++i];
        } else if (std::strcmp(argv[i], "--no-output") == 0) {
            no_output = true;
        }
    }
    if (!seed_hex) {
        seed_hex = std::getenv("SEED_HEX");
    }
#ifdef TT_SEED_HEX
    if (!seed_hex) {
        seed_hex = TT_SEED_HEX;
    }
#endif
    if (!seed_hex) {
        std::fprintf(stderr, "Missing --seed-hex (or SEED_HEX env / TT_SEED_HEX)\n");
        return 1;
    }

    uint8_t seed[kSeedSize];
    if (!hex_to_bytes(seed_hex, seed, kSeedSize)) {
        std::fprintf(stderr, "Invalid seed hex\n");
        return 1;
    }

    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, seed, sizeof(seed));
    blake3_hasher_finalize(&hasher, g_ab, sizeof(g_ab));

    const uint8_t *a = g_ab;
    const int8_t *b = reinterpret_cast<const int8_t *>(g_ab + kABytes);

    uint64_t start_cycles = 0;
#if TT_USE_RDCYCLE
    start_cycles = rdcycle();
#endif
    for (int r = 0; r < 16; ++r) {
        for (int c = 0; c < 16; ++c) {
            int32_t sum = 0;
            for (int k = 0; k < 50240; ++k) {
                int a_val = static_cast<int>(a[r * 50240 + k]);
                int b_val = static_cast<int>(b[k * 16 + c]);
                sum += a_val * b_val;
            }
            g_c[r * 16 + c] = sum;
        }
    }
    uint64_t end_cycles = 0;
#if TT_USE_RDCYCLE
    end_cycles = rdcycle();
#endif

    (void)no_output;
    uint64_t elapsed_cycles = end_cycles - start_cycles;
    double elapsed_ms = (elapsed_cycles == 0)
        ? 0.0
        : (static_cast<double>(elapsed_cycles) * 1000.0) / static_cast<double>(TT_CPU_HZ);
    double ops = 2.0 * 16.0 * 16.0 * 50240.0;
    double gflops = (elapsed_cycles == 0)
        ? 0.0
        : (ops * static_cast<double>(TT_CPU_HZ)) / (static_cast<double>(elapsed_cycles) * 1e9);
    char buf[160];
    int n = std::snprintf(buf, sizeof(buf),
                          "{\"mode\":\"upow_baremetal\",\"elapsed_ms\":%.6f,\"gflops\":%.6f}\n",
                          elapsed_ms, gflops);
    if (n > 0) {
        (void)write(1, buf, static_cast<size_t>(n));
    }
    return 0;
}
} // namespace

int main(int argc, char **argv) {
    return run_baremetal(argc, argv);
}
#else

struct Options {
    int m = 256;
    int n = 256;
    int k = 256;
    int block = 64;
    unsigned int seed = 1;
    std::string algo = "blocked";
    std::string input_path;
    std::string output_path;
    bool upow = false;
    std::string seed_path;
    std::string seed_hex;
    bool no_output = false;
};

static void usage(const char *argv0) {
    std::fprintf(
        stderr,
        "Usage: %s [--m M] [--n N] [--k K] [--algo naive|blocked] [--block B] [--seed S] [--input PATH] [--output PATH] [--no-output] [--upow --seed-path PATH|--seed-hex HEX]\n",
        argv0);
}

static bool parse_arg(int argc, char **argv, int &i, Options &opt) {
    std::string arg = argv[i];
    auto require_value = [&](const char *name) -> const char * {
        if (i + 1 >= argc) {
            std::fprintf(stderr, "Missing value for %s\n", name);
            std::exit(1);
        }
        return argv[++i];
    };

    if (arg == "--m") {
        opt.m = std::atoi(require_value("--m"));
    } else if (arg == "--n") {
        opt.n = std::atoi(require_value("--n"));
    } else if (arg == "--k") {
        opt.k = std::atoi(require_value("--k"));
    } else if (arg == "--block") {
        opt.block = std::atoi(require_value("--block"));
    } else if (arg == "--seed") {
        opt.seed = static_cast<unsigned int>(std::strtoul(require_value("--seed"), nullptr, 10));
    } else if (arg == "--algo") {
        opt.algo = require_value("--algo");
    } else if (arg == "--input") {
        opt.input_path = require_value("--input");
    } else if (arg == "--output") {
        opt.output_path = require_value("--output");
    } else if (arg == "--no-output") {
        opt.no_output = true;
    } else if (arg == "--upow") {
        opt.upow = true;
    } else if (arg == "--seed-path") {
        opt.seed_path = require_value("--seed-path");
    } else if (arg == "--seed-hex") {
        opt.seed_hex = require_value("--seed-hex");
    } else if (arg == "--help" || arg == "-h") {
        usage(argv[0]);
        std::exit(0);
    } else {
        return false;
    }
    return true;
}

static void load_or_generate(const Options &opt, std::vector<float> &a, std::vector<float> &b) {
    if (!opt.input_path.empty()) {
        std::ifstream in(opt.input_path, std::ios::binary);
        if (!in) {
            std::perror("Failed to open input");
            std::exit(1);
        }
        int32_t m = 0, n = 0, k = 0;
        in.read(reinterpret_cast<char *>(&m), sizeof(m));
        in.read(reinterpret_cast<char *>(&n), sizeof(n));
        in.read(reinterpret_cast<char *>(&k), sizeof(k));
        if (!in || m != opt.m || n != opt.n || k != opt.k) {
            std::fprintf(stderr, "Input header mismatch (expected %d,%d,%d)\n", opt.m, opt.n, opt.k);
            std::exit(1);
        }
        a.resize(static_cast<size_t>(opt.m) * opt.k);
        b.resize(static_cast<size_t>(opt.k) * opt.n);
        in.read(reinterpret_cast<char *>(a.data()), static_cast<std::streamsize>(a.size() * sizeof(float)));
        in.read(reinterpret_cast<char *>(b.data()), static_cast<std::streamsize>(b.size() * sizeof(float)));
        if (!in) {
            std::fprintf(stderr, "Input file truncated\n");
            std::exit(1);
        }
        return;
    }

    a.resize(static_cast<size_t>(opt.m) * opt.k);
    b.resize(static_cast<size_t>(opt.k) * opt.n);
    std::mt19937 rng(opt.seed);
    std::uniform_real_distribution<float> dist(-1.0f, 1.0f);
    for (auto &v : a) {
        v = dist(rng);
    }
    for (auto &v : b) {
        v = dist(rng);
    }
}

static void matmul_naive(const Options &opt, const std::vector<float> &a, const std::vector<float> &b, std::vector<float> &c) {
    const int m = opt.m;
    const int n = opt.n;
    const int k = opt.k;
    c.assign(static_cast<size_t>(m) * n, 0.0f);

#ifdef _OPENMP
#pragma omp parallel for
#endif
    for (int i = 0; i < m; ++i) {
        for (int p = 0; p < k; ++p) {
            float av = a[static_cast<size_t>(i) * k + p];
            for (int j = 0; j < n; ++j) {
                c[static_cast<size_t>(i) * n + j] += av * b[static_cast<size_t>(p) * n + j];
            }
        }
    }
}

static void matmul_blocked(const Options &opt, const std::vector<float> &a, const std::vector<float> &b, std::vector<float> &c) {
    const int m = opt.m;
    const int n = opt.n;
    const int k = opt.k;
    const int bs = opt.block;
    c.assign(static_cast<size_t>(m) * n, 0.0f);

#ifdef _OPENMP
#pragma omp parallel for collapse(2)
#endif
    for (int ii = 0; ii < m; ii += bs) {
        for (int jj = 0; jj < n; jj += bs) {
            for (int kk = 0; kk < k; kk += bs) {
                int i_max = std::min(ii + bs, m);
                int j_max = std::min(jj + bs, n);
                int k_max = std::min(kk + bs, k);
                for (int i = ii; i < i_max; ++i) {
                    for (int p = kk; p < k_max; ++p) {
                        float av = a[static_cast<size_t>(i) * k + p];
                        for (int j = jj; j < j_max; ++j) {
                            c[static_cast<size_t>(i) * n + j] += av * b[static_cast<size_t>(p) * n + j];
                        }
                    }
                }
            }
        }
    }
}

static void write_output(const Options &opt, const std::vector<float> &c) {
    if (opt.output_path.empty()) {
        return;
    }
    std::ofstream out(opt.output_path, std::ios::binary);
    if (!out) {
        std::perror("Failed to open output");
        std::exit(1);
    }
    int32_t m = opt.m;
    int32_t n = opt.n;
    int32_t k = opt.k;
    out.write(reinterpret_cast<const char *>(&m), sizeof(m));
    out.write(reinterpret_cast<const char *>(&n), sizeof(n));
    out.write(reinterpret_cast<const char *>(&k), sizeof(k));
    out.write(reinterpret_cast<const char *>(c.data()), static_cast<std::streamsize>(c.size() * sizeof(float)));
}

static std::vector<uint8_t> read_binary_file(const std::string &path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        std::perror("Failed to open file");
        std::exit(1);
    }
    in.seekg(0, std::ios::end);
    std::streamsize size = in.tellg();
    in.seekg(0, std::ios::beg);
    std::vector<uint8_t> data(static_cast<size_t>(size));
    if (size > 0) {
        in.read(reinterpret_cast<char *>(data.data()), size);
    }
    return data;
}

static int hex_to_nibble(char c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return 10 + (c - 'a');
    }
    if (c >= 'A' && c <= 'F') {
        return 10 + (c - 'A');
    }
    return -1;
}

static std::vector<uint8_t> parse_hex(const std::string &hex_in) {
    std::string hex;
    hex.reserve(hex_in.size());
    for (char c : hex_in) {
        if (c == ' ' || c == '\n' || c == '\t') {
            continue;
        }
        if (c == '0' && (hex.empty() || hex.back() == 'x')) {
            hex.push_back(c);
        } else if (c == 'x' && !hex.empty() && hex.back() == '0') {
            hex.pop_back();
        } else {
            hex.push_back(c);
        }
    }
    if (hex.size() % 2 != 0) {
        std::fprintf(stderr, "Hex string has odd length\n");
        std::exit(1);
    }
    std::vector<uint8_t> out(hex.size() / 2);
    for (size_t i = 0; i < out.size(); ++i) {
        int hi = hex_to_nibble(hex[2 * i]);
        int lo = hex_to_nibble(hex[2 * i + 1]);
        if (hi < 0 || lo < 0) {
            std::fprintf(stderr, "Invalid hex character\n");
            std::exit(1);
        }
        out[i] = static_cast<uint8_t>((hi << 4) | lo);
    }
    return out;
}

static std::vector<uint8_t> load_seed(const Options &opt, size_t expected_size) {
    std::vector<uint8_t> seed;
    if (!opt.seed_path.empty()) {
        seed = read_binary_file(opt.seed_path);
    } else if (!opt.seed_hex.empty()) {
        seed = parse_hex(opt.seed_hex);
    } else {
        std::fprintf(stderr, "Missing seed. Provide --seed-path or --seed-hex\n");
        std::exit(1);
    }
    if (seed.size() != expected_size) {
        std::fprintf(stderr, "Seed size mismatch. Expected %zu bytes, got %zu\n", expected_size, seed.size());
        std::exit(1);
    }
    return seed;
}

static void write_solution(const Options &opt, const std::vector<uint8_t> &seed, const std::vector<int32_t> &c) {
    if (opt.output_path.empty()) {
        return;
    }
    std::ofstream out(opt.output_path, std::ios::binary);
    if (!out) {
        std::perror("Failed to open output");
        std::exit(1);
    }
    out.write(reinterpret_cast<const char *>(seed.data()), static_cast<std::streamsize>(seed.size()));
    out.write(reinterpret_cast<const char *>(c.data()), static_cast<std::streamsize>(c.size() * sizeof(int32_t)));
}

static void matmul_upow(const std::vector<uint8_t> &a, const std::vector<int8_t> &b, std::vector<int32_t> &c) {
    constexpr int m = 16;
    constexpr int k = 50240;
    constexpr int n = 16;
    c.assign(static_cast<size_t>(m) * n, 0);

#ifdef _OPENMP
#pragma omp parallel for
#endif
    for (int i = 0; i < m; ++i) {
        const uint8_t *row_a = a.data() + static_cast<size_t>(i) * k;
        for (int kk = 0; kk < k; ++kk) {
            int32_t av = static_cast<int32_t>(row_a[kk]);
            const int8_t *row_b = b.data() + static_cast<size_t>(kk) * n;
            for (int j = 0; j < n; ++j) {
                c[static_cast<size_t>(i) * n + j] += av * static_cast<int32_t>(row_b[j]);
            }
        }
    }
}

int main(int argc, char **argv) {
    Options opt;
    int arg_start = 1;
    // Some runners pass a mount/root path as the first argument.
    if (argc > 1 && argv[1][0] == '/') {
        arg_start = 2;
    }
    for (int i = arg_start; i < argc; ++i) {
        if (!parse_arg(argc, argv, i, opt)) {
            std::fprintf(stderr, "Unknown arg: %s\n", argv[i]);
            usage(argv[0]);
            return 1;
        }
    }

    if (opt.upow) {
        constexpr size_t kSeedSize = 240;
        constexpr size_t kABytes = 16 * 50240;
        constexpr size_t kBBytes = 50240 * 16;
        constexpr size_t kB2Bytes = 16 * 64;
        constexpr size_t kABBytes = kABytes + kBBytes + kB2Bytes;

        std::vector<uint8_t> seed = load_seed(opt, kSeedSize);
        std::vector<uint8_t> ab(kABBytes);

        auto gen_start = std::chrono::steady_clock::now();
        blake3_hasher hasher;
        blake3_hasher_init(&hasher);
        blake3_hasher_update(&hasher, seed.data(), seed.size());
        blake3_hasher_finalize(&hasher, ab.data(), ab.size());

        std::vector<uint8_t> a_bytes(kABytes);
        std::vector<int8_t> b_bytes(kBBytes);
        std::memcpy(a_bytes.data(), ab.data(), kABytes);
        std::memcpy(b_bytes.data(), ab.data() + kABytes, kBBytes);

        std::vector<int32_t> c_int;

        auto gen_end = std::chrono::steady_clock::now();
        auto matmul_start = gen_end;
        matmul_upow(a_bytes, b_bytes, c_int);
        auto matmul_end = std::chrono::steady_clock::now();

        if (!opt.no_output) {
            write_solution(opt, seed, c_int);
        }

        std::chrono::duration<double, std::milli> gen_ms = gen_end - gen_start;
        std::chrono::duration<double, std::milli> matmul_ms = matmul_end - matmul_start;
        double ops = 2.0 * 16.0 * 16.0 * 50240.0;
        double gflops = ops / (matmul_ms.count() * 1e6);

        std::cout << "{"
                  << "\"mode\":\"upow\","
                  << "\"gen_ms\":" << gen_ms.count() << ","
                  << "\"elapsed_ms\":" << matmul_ms.count() << ","
                  << "\"gflops\":" << gflops
                  << "}" << std::endl;
        return 0;
    }

    std::vector<float> a;
    std::vector<float> b;
    std::vector<float> c;
    load_or_generate(opt, a, b);

    auto start = std::chrono::steady_clock::now();
    if (opt.algo == "naive") {
        matmul_naive(opt, a, b, c);
    } else if (opt.algo == "blocked") {
        matmul_blocked(opt, a, b, c);
    } else {
        std::fprintf(stderr, "Unknown algo: %s\n", opt.algo.c_str());
        return 1;
    }
    auto end = std::chrono::steady_clock::now();

    write_output(opt, c);

    std::chrono::duration<double, std::milli> elapsed_ms = end - start;
    double ops = 2.0 * static_cast<double>(opt.m) * opt.n * opt.k;
    double gflops = ops / (elapsed_ms.count() * 1e6);

    std::cout << "{"
              << "\"m\":" << opt.m << ","
              << "\"n\":" << opt.n << ","
              << "\"k\":" << opt.k << ","
              << "\"algo\":\"" << opt.algo << "\","
              << "\"block\":" << opt.block << ","
              << "\"elapsed_ms\":" << elapsed_ms.count() << ","
              << "\"gflops\":" << gflops
              << "}" << std::endl;

    return 0;
}
#endif

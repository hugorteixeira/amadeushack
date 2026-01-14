#include <cuda_runtime.h>

#include <chrono>
#include <cstdlib>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "blake3.h"

namespace {

struct Options {
  std::string seed_path;
  std::string seed_hex;
  std::string output = "solution.bin";
};

void usage(const char *prog) {
  std::fprintf(stderr,
               "Usage: %s --seed-path PATH|--seed-hex HEX [--output PATH]\n",
               prog);
}

bool has_prefix(const std::string &s, const std::string &prefix) {
  return s.rfind(prefix, 0) == 0;
}

std::vector<uint8_t> hex_to_bytes(const std::string &hex) {
  if (hex.size() % 2 != 0) {
    throw std::runtime_error("hex string must have even length");
  }
  std::vector<uint8_t> out(hex.size() / 2);
  for (size_t i = 0; i < out.size(); ++i) {
    char buf[3] = {hex[2 * i], hex[2 * i + 1], 0};
    out[i] = static_cast<uint8_t>(std::strtoul(buf, nullptr, 16));
  }
  return out;
}

std::vector<uint8_t> load_seed(const Options &opt, size_t expected) {
  std::vector<uint8_t> seed;
  if (!opt.seed_hex.empty()) {
    seed = hex_to_bytes(opt.seed_hex);
  } else if (!opt.seed_path.empty()) {
    std::ifstream in(opt.seed_path, std::ios::binary);
    if (!in) {
      throw std::runtime_error("failed to open seed file");
    }
    seed.assign(std::istreambuf_iterator<char>(in),
                std::istreambuf_iterator<char>());
  }
  if (seed.size() != expected) {
    throw std::runtime_error("seed length mismatch");
  }
  return seed;
}

void write_solution(const Options &opt, const std::vector<uint8_t> &seed,
                    const std::vector<int32_t> &c) {
  std::ofstream out(opt.output, std::ios::binary);
  if (!out) {
    throw std::runtime_error("failed to open output file");
  }
  out.write(reinterpret_cast<const char *>(seed.data()), seed.size());
  out.write(reinterpret_cast<const char *>(c.data()),
            static_cast<std::streamsize>(c.size() * sizeof(int32_t)));
}

void check_cuda(cudaError_t err, const char *msg) {
  if (err != cudaSuccess) {
    std::fprintf(stderr, "%s: %s\n", msg, cudaGetErrorString(err));
    std::exit(1);
  }
}

__global__ void matmul_kernel(const uint8_t *a, const int8_t *b, int32_t *c) {
  int row = static_cast<int>(threadIdx.y);
  int col = static_cast<int>(threadIdx.x);
  if (row >= 16 || col >= 16) {
    return;
  }
  int32_t sum = 0;
  const int k_dim = 50240;
  for (int k = 0; k < k_dim; ++k) {
    int a_val = static_cast<int>(a[row * k_dim + k]);
    int b_val = static_cast<int>(b[k * 16 + col]);
    sum += a_val * b_val;
  }
  c[row * 16 + col] = sum;
}

} // namespace

int main(int argc, char **argv) {
  Options opt;
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    if ((arg == "--seed-path" || arg == "--input") && i + 1 < argc) {
      opt.seed_path = argv[++i];
    } else if (arg == "--seed-hex" && i + 1 < argc) {
      opt.seed_hex = argv[++i];
    } else if (arg == "--output" && i + 1 < argc) {
      opt.output = argv[++i];
    } else if (arg == "--upow") {
      continue;
    } else {
      usage(argv[0]);
      return 1;
    }
  }

  if (opt.seed_path.empty() && opt.seed_hex.empty()) {
    usage(argv[0]);
    return 1;
  }

  constexpr size_t kSeedSize = 240;
  constexpr size_t kABytes = 16 * 50240;
  constexpr size_t kBBytes = 50240 * 16;
  constexpr size_t kABBytes = kABytes + kBBytes;

  std::vector<uint8_t> seed;
  try {
    seed = load_seed(opt, kSeedSize);
  } catch (const std::exception &e) {
    std::fprintf(stderr, "seed error: %s\n", e.what());
    return 1;
  }

  std::vector<uint8_t> ab(kABBytes);
  blake3_hasher hasher;
  blake3_hasher_init(&hasher);
  blake3_hasher_update(&hasher, seed.data(), seed.size());
  blake3_hasher_finalize(&hasher, ab.data(), ab.size());

  std::vector<uint8_t> a_bytes(kABytes);
  std::vector<int8_t> b_bytes(kBBytes);
  std::memcpy(a_bytes.data(), ab.data(), kABytes);
  std::memcpy(b_bytes.data(), ab.data() + kABytes, kBBytes);

  uint8_t *d_a = nullptr;
  int8_t *d_b = nullptr;
  int32_t *d_c = nullptr;
  check_cuda(cudaMalloc(&d_a, kABytes), "cudaMalloc A");
  check_cuda(cudaMalloc(&d_b, kBBytes), "cudaMalloc B");
  check_cuda(cudaMalloc(&d_c, 16 * 16 * sizeof(int32_t)), "cudaMalloc C");
  check_cuda(cudaMemcpy(d_a, a_bytes.data(), kABytes, cudaMemcpyHostToDevice),
             "cudaMemcpy A");
  check_cuda(cudaMemcpy(d_b, b_bytes.data(), kBBytes, cudaMemcpyHostToDevice),
             "cudaMemcpy B");

  dim3 block(16, 16);
  dim3 grid(1, 1);

  auto start = std::chrono::steady_clock::now();
  matmul_kernel<<<grid, block>>>(d_a, d_b, d_c);
  check_cuda(cudaGetLastError(), "kernel launch");
  check_cuda(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
  auto end = std::chrono::steady_clock::now();

  std::vector<int32_t> c_int(16 * 16);
  check_cuda(cudaMemcpy(c_int.data(), d_c, c_int.size() * sizeof(int32_t),
                        cudaMemcpyDeviceToHost),
             "cudaMemcpy C");

  cudaFree(d_a);
  cudaFree(d_b);
  cudaFree(d_c);

  try {
    write_solution(opt, seed, c_int);
  } catch (const std::exception &e) {
    std::fprintf(stderr, "write error: %s\n", e.what());
    return 1;
  }

  std::chrono::duration<double, std::milli> elapsed_ms = end - start;
  double ops = 2.0 * 16.0 * 16.0 * 50240.0;
  double gflops = ops / (elapsed_ms.count() * 1e6);

  std::cout << "{"
            << "\"mode\":\"upow_cuda\","
            << "\"elapsed_ms\":" << elapsed_ms.count() << ","
            << "\"gflops\":" << gflops
            << "}" << std::endl;
  return 0;
}

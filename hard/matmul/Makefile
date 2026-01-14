CC ?= gcc
CXX ?= g++
NVCC ?= nvcc
CFLAGS ?= -O3 -std=c11
CXXFLAGS ?= -O3 -std=c++17
CUDAFLAGS ?= -O3 -std=c++17

# Use portable BLAKE3 on environments without SIMD object files.
CFLAGS += -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512
CXXFLAGS += -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512
LDFLAGS ?=

BLAKE3_DIR = third_party/blake3
BLAKE3_SRCS = \
	$(BLAKE3_DIR)/blake3.c \
	$(BLAKE3_DIR)/blake3_dispatch.c \
	$(BLAKE3_DIR)/blake3_portable.c

CFLAGS += -I$(BLAKE3_DIR)
CXXFLAGS += -I$(BLAKE3_DIR)
CUDAFLAGS += -I$(BLAKE3_DIR)

ifdef OPENMP
CXXFLAGS += -fopenmp
endif

OBJS = src/matmul.o $(BLAKE3_SRCS:.c=.o)
CUDA_OBJS = src/matmul_cuda.o

all: matmul

matmul: $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

matmul_cuda: $(CUDA_OBJS) $(BLAKE3_SRCS:.c=.o)
	$(NVCC) $(CUDAFLAGS) -o $@ $^ $(LDFLAGS)

src/matmul.o: src/matmul.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

src/matmul_cuda.o: src/matmul_cuda.cu
	$(NVCC) $(CUDAFLAGS) -c $< -o $@

$(BLAKE3_DIR)/%.o: $(BLAKE3_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f matmul matmul_cuda $(OBJS) $(CUDA_OBJS)

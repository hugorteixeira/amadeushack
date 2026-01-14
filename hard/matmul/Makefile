CXX ?= g++
CXXFLAGS ?= -O3 -std=c++17
LDFLAGS ?=

BLAKE3_DIR = third_party/blake3
BLAKE3_SRCS = \
	$(BLAKE3_DIR)/blake3.c \
	$(BLAKE3_DIR)/blake3_dispatch.c \
	$(BLAKE3_DIR)/blake3_portable.c

CXXFLAGS += -I$(BLAKE3_DIR)

ifdef OPENMP
CXXFLAGS += -fopenmp
endif

all: matmul

matmul: src/matmul.cpp $(BLAKE3_SRCS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f matmul

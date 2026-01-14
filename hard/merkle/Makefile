CC ?= gcc
CXX ?= g++
CFLAGS ?= -O3 -std=c11 -I../matmul/third_party/blake3 -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512
CXXFLAGS ?= -O3 -std=c++17 -I../matmul/third_party/blake3 -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512

BIN ?= merkle

SRCS = src/merkle.cpp \
       ../matmul/third_party/blake3/blake3.c \
       ../matmul/third_party/blake3/blake3_dispatch.c \
       ../matmul/third_party/blake3/blake3_portable.c

OBJS = $(SRCS:.c=.o)
OBJS := $(OBJS:.cpp=.o)

.PHONY: all clean

all: $(BIN)

$(BIN): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(BIN) $(OBJS)

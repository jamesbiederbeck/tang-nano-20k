// CPU reference for three cmtz projects (F_17), timed two ways:
//   throughput: independent inputs from an array, results written to an array
//   latency:    each result feeds the next call, so nothing can overlap
// Kernels match the datapaths in projects/cmtz/{cmtz-mul,cmtz-fibonacci,cmtz-ntt-butterfly}.
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

static constexpr unsigned P = 17;

static inline uint8_t mul(uint8_t a, uint8_t b) { return (a * b) % P; }

static inline uint8_t fib12(uint8_t a, uint8_t b) {  // F3..F12 as an unrolled add chain
    unsigned x = a, y = b;
    for (int i = 3; i <= 12; i++) { unsigned z = x + y; if (z >= P) z -= P; x = y; y = z; }
    return y;
}

static inline void ntt(uint8_t a, uint8_t b, uint8_t &plus, uint8_t &minus) {
    uint8_t t = (b * 13) % P;                 // omega^4 = 13
    plus  = (a + t) % P;
    minus = (a + (t * 16) % P) % P;           // -t as multiply by omega^8 = 16
}

static double now() {
    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

template <class F> static double best(F f, int reps = 7) {
    double b = 1e30;
    for (int i = 0; i < reps; i++) { double t = now(); f(); t = now() - t; if (t < b) b = t; }
    return b;
}

int main(int argc, char **argv) {
    const size_t N = 1 << 16;           // 64 KiB per array, stays in L2
    const int ITER = 200;               // passes over the array per timing
    const size_t CH = 50'000'000;       // dependent chain length
    std::vector<uint8_t> A(N), B(N), O1(N), O2(N);
    srand(1);
    for (size_t i = 0; i < N; i++) { A[i] = rand() % P; B[i] = rand() % P; }
    volatile unsigned sink = 0;

    auto report = [&](const char *name, double tp_s, double lat_s) {
        printf("%-14s throughput %8.1f Mop/s (%6.2f ns/op)   latency %6.2f ns/op\n",
               name, N * ITER / tp_s / 1e6, tp_s / (N * ITER) * 1e9, lat_s / CH * 1e9);
    };

    {   // mul
        double tp = best([&] { for (int it = 0; it < ITER; it++) for (size_t i = 0; i < N; i++) O1[i] = mul(A[i], B[i]); });
        sink += O1[7];
        double lt = best([&] { uint8_t x = 3; for (size_t i = 0; i < CH; i++) x = mul(x, B[i & (N-1)]); sink += x; }, 3);
        report("mul", tp, lt);
    }
    {   // fibonacci
        double tp = best([&] { for (int it = 0; it < ITER; it++) for (size_t i = 0; i < N; i++) O1[i] = fib12(A[i], B[i]); });
        sink += O1[7];
        double lt = best([&] { uint8_t x = 3; for (size_t i = 0; i < CH; i++) x = fib12(x, A[i & (N-1)]); sink += x; }, 3);
        report("fibonacci", tp, lt);
    }
    {   // ntt butterfly (two outputs)
        double tp = best([&] { for (int it = 0; it < ITER; it++) for (size_t i = 0; i < N; i++) ntt(A[i], B[i], O1[i], O2[i]); });
        sink += O1[7] + O2[7];
        double lt = best([&] { uint8_t x = 3, y = 5, p, m; for (size_t i = 0; i < CH; i++) { ntt(x, y, p, m); x = p; y = m; } sink += x + y; }, 3);
        report("ntt-butterfly", tp, lt);
    }
    if (argc > 1) {  // print reference vectors for cross-checking against the board
        for (int a = 0; a < 17; a++) for (int b = 0; b < 17; b++) {
            uint8_t p, m; ntt(a, b, p, m);
            printf("V %d %d %d %d %d %d\n", a, b, mul(a, b), fib12(a, b), p, m);
        }
    }
    return 0;
}

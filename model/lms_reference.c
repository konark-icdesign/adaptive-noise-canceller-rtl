#include <stdint.h>
#include <stdio.h>

#define MU_SHIFT 4
#define UPDATE_SHIFT (15 + MU_SHIFT)
#define NSAMPLES 3000

static int16_t sat16(int64_t v)
{
    if (v > 32767) return 32767;
    if (v < -32768) return -32768;
    return (int16_t)v;
}

static int32_t arshift32(int32_t v, unsigned s)
{
    if (v >= 0) return v >> s;
    return -(((-v) + ((1u << s) - 1u)) >> s);
}

static int64_t arshift64(int64_t v, unsigned s)
{
    if (v >= 0) return v >> s;
    return -(((-v) + (((int64_t)1 << s) - 1)) >> s);
}

int main(void)
{
    int16_t w[4] = {0, 0, 0, 0};
    int16_t x1 = 0, x2 = 0, x3 = 0;
    int16_t x_prev = 0;
    uint16_t lfsr = 0xACE1u;

    uint64_t early_sum = 0, late_sum = 0;
    unsigned early_count = 0, late_count = 0;

    for (int n = 0; n < NSAMPLES; ++n) {
        uint16_t fb = ((lfsr >> 15) ^ (lfsr >> 13) ^ (lfsr >> 12) ^ (lfsr >> 10)) & 1u;
        lfsr = (uint16_t)((lfsr << 1) | fb);

        int16_t x = (int16_t)arshift32((int16_t)lfsr, 1);

        int64_t plant = (int32_t)x * 16384;
        plant += (int32_t)x_prev * -8192;
        int16_t d = (int16_t)arshift64(plant, 15);

        int64_t acc = 0;
        acc += (int32_t)x  * w[0];
        acc += (int32_t)x1 * w[1];
        acc += (int32_t)x2 * w[2];
        acc += (int32_t)x3 * w[3];

        int16_t y = sat16(arshift64(acc, 15));
        int16_t e = sat16((int32_t)d - (int32_t)y);

        int16_t taps[4] = {x, x1, x2, x3};
        for (int i = 0; i < 4; ++i) {
            int32_t corr = (int32_t)e * (int32_t)taps[i];
            int32_t delta = arshift32(corr, UPDATE_SHIFT);
            w[i] = sat16((int32_t)w[i] + delta);
        }

        int32_t err = e;
        uint64_t err_sq = (uint64_t)((int64_t)err * err);

        if (n >= 100 && n < 600) {
            early_sum += err_sq;
            ++early_count;
        }
        if (n >= 2500 && n < 3000) {
            late_sum += err_sq;
            ++late_count;
        }

        x3 = x2;
        x2 = x1;
        x1 = x;
        x_prev = x;
    }

    uint64_t early_avg = early_sum / early_count;
    uint64_t late_avg = late_sum / late_count;

    printf("C reference model\n");
    printf("early MSE : %llu\n", (unsigned long long)early_avg);
    printf("late MSE  : %llu\n", (unsigned long long)late_avg);
    printf("coeffs    : %d, %d, %d, %d\n", w[0], w[1], w[2], w[3]);

    if (late_avg >= early_avg / 10) return 1;
    if (w[0] < 14884 || w[0] > 17884) return 1;
    if (w[1] < -9692 || w[1] > -6692) return 1;
    if (w[2] < -1500 || w[2] > 1500) return 1;
    if (w[3] < -1500 || w[3] > 1500) return 1;

    return 0;
}

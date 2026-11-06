// DSP.c - AFLATOON
#include "DSP.h"
#include <math.h>
#include <string.h>

#define AP_PI 3.14159265358979323846

static void bq_set(AP_Biquad *b, double b0, double b1, double b2, double a0, double a1, double a2) {
    b->b0 = b0 / a0; b->b1 = b1 / a0; b->b2 = b2 / a0;
    b->a1 = a1 / a0; b->a2 = a2 / a0;
}

static void bq_peak(AP_Biquad *b, double fs, double f0, double dB, double Q) {
    double A = pow(10.0, dB / 40.0);
    double w0 = 2.0 * AP_PI * f0 / fs, cs = cos(w0), sn = sin(w0);
    double alpha = sn / (2.0 * Q);
    bq_set(b, 1 + alpha * A, -2 * cs, 1 - alpha * A, 1 + alpha / A, -2 * cs, 1 - alpha / A);
}

static void bq_lowshelf(AP_Biquad *b, double fs, double f0, double dB) {
    double A = pow(10.0, dB / 40.0);
    double w0 = 2.0 * AP_PI * f0 / fs, cs = cos(w0), sn = sin(w0);
    double alpha = sn * 0.70710678118654752;
    double sq = 2.0 * sqrt(A) * alpha;
    bq_set(b,
           A * ((A + 1) - (A - 1) * cs + sq),
           2 * A * ((A - 1) - (A + 1) * cs),
           A * ((A + 1) - (A - 1) * cs - sq),
           (A + 1) + (A - 1) * cs + sq,
           -2 * ((A - 1) + (A + 1) * cs),
           (A + 1) + (A - 1) * cs - sq);
}

static void bq_highshelf(AP_Biquad *b, double fs, double f0, double dB) {
    double A = pow(10.0, dB / 40.0);
    double w0 = 2.0 * AP_PI * f0 / fs, cs = cos(w0), sn = sin(w0);
    double alpha = sn * 0.70710678118654752;
    double sq = 2.0 * sqrt(A) * alpha;
    bq_set(b,
           A * ((A + 1) + (A - 1) * cs + sq),
           -2 * A * ((A - 1) + (A + 1) * cs),
           A * ((A + 1) + (A - 1) * cs - sq),
           (A + 1) - (A - 1) * cs + sq,
           2 * ((A - 1) - (A + 1) * cs),
           (A + 1) - (A - 1) * cs - sq);
}

static inline double bq_run(AP_Biquad *b, double x) {
    double y = b->b0 * x + b->z1;
    b->z1 = b->b1 * x - b->a1 * y + b->z2;
    b->z2 = b->b2 * x - b->a2 * y;
    return y;
}

void ap_voice_init(AP_Voice *v, double fs) {
    memset(v, 0, sizeof(*v));
    v->fs = (fs > 1000.0) ? fs : 48000.0;
    for (int c = 0; c < AP_MAXCH; c++) {
        v->bass[c].b0 = 1; v->mid[c].b0 = 1; v->treb[c].b0 = 1;
    }
}

static void eq_update(AP_Voice *v, float bass, float mid, float treble) {
    if (v->eqInit && bass == v->lastBass && mid == v->lastMid && treble == v->lastTreb) return;
    double lim = v->fs * 0.45;
    double fl = fmin(120.0, lim), fm = fmin(1000.0, lim), fh = fmin(6000.0, lim);
    for (int c = 0; c < AP_MAXCH; c++) {
        bq_lowshelf(&v->bass[c], v->fs, fl, bass);
        bq_peak(&v->mid[c], v->fs, fm, mid, 0.9);
        bq_highshelf(&v->treb[c], v->fs, fh, treble);
    }
    v->lastBass = bass; v->lastMid = mid; v->lastTreb = treble; v->eqInit = 1;
}

static inline float get_s(void *buf[2], int interleaved, int ch, int i, int c, int isFloat) {
    void *b = interleaved ? buf[0] : buf[c];
    int idx = interleaved ? (i * ch + c) : i;
    if (isFloat) return ((float *)b)[idx];
    return (float)((int16_t *)b)[idx] * (1.0f / 32768.0f);
}

static inline void put_s(void *buf[2], int interleaved, int ch, int i, int c, int isFloat, float x) {
    void *b = interleaved ? buf[0] : buf[c];
    int idx = interleaved ? (i * ch + c) : i;
    if (x > 1.0f) x = 1.0f; else if (x < -1.0f) x = -1.0f;
    if (isFloat) ((float *)b)[idx] = x;
    else ((int16_t *)b)[idx] = (int16_t)lrintf(x * 32767.0f);
}

static inline double tap(const float *ring, double pos) {
    double fl = floor(pos);
    double fr = pos - fl;
    int64_t i0 = (int64_t)fl;
    double a = ring[(uint64_t)i0 & AP_RMASK];
    double b = ring[(uint64_t)(i0 + 1) & AP_RMASK];
    return a + (b - a) * fr;
}

// 3-grain overlap-add instead of 2: smoother time-stretch, less "flutter"/doubling at
// extreme ratios. For N equally-spaced Hann grains, sum_k cos(theta + 2*pi*k/N) == 0,
// so sum_k weight_k is exactly constant (== N/2) for any phase - we just normalize by 2/N.
#define AP_GRAINS 3

void ap_voice_process(AP_Voice *v, void *buf[2], int ch, int interleaved, int isFloat,
                      int frames, int pitchOn, float pitch,
                      int eqOn, float bassDB, float midDB, float trebleDB) {
    if (!v || ch < 1 || ch > AP_MAXCH || frames <= 0) return;
    if (!buf[0] || (!interleaved && ch > 1 && !buf[1])) return;

    if (eqOn) eq_update(v, bassDB, midDB, trebleDB);
    if (pitch < 0.5f) pitch = 0.5f;
    if (pitch > 4.0f) pitch = 4.0f;   // raised ceiling: more headroom for room-voice speed
    int doPitch = pitchOn && fabsf(pitch - 1.0f) > 0.005f;
    double dphi = (1.0 - (double)pitch) / AP_DELAY;
    const double norm = 2.0 / (double)AP_GRAINS;

    for (int i = 0; i < frames; i++) {
        float x[AP_MAXCH] = {0, 0};
        for (int c = 0; c < ch; c++) {
            double s = get_s(buf, interleaved, ch, i, c, isFloat);
            if (eqOn) {
                s = bq_run(&v->bass[c], s);
                s = bq_run(&v->mid[c], s);
                s = bq_run(&v->treb[c], s);
            }
            x[c] = (float)s;
        }
        if (!doPitch) {
            if (eqOn) for (int c = 0; c < ch; c++) put_s(buf, interleaved, ch, i, c, isFloat, x[c]);
            continue;
        }
        for (int c = 0; c < ch; c++) v->ring[c][(uint64_t)v->w & AP_RMASK] = x[c];

        double g[AP_GRAINS], d[AP_GRAINS];
        for (int k = 0; k < AP_GRAINS; k++) {
            double p = v->phi + (double)k / AP_GRAINS; p -= floor(p);
            g[k] = (0.5 - 0.5 * cos(2.0 * AP_PI * p)) * norm;
            d[k] = p * AP_DELAY;
        }
        for (int c = 0; c < ch; c++) {
            double y = 0.0;
            for (int k = 0; k < AP_GRAINS; k++) y += g[k] * tap(v->ring[c], (double)v->w - d[k]);
            put_s(buf, interleaved, ch, i, c, isFloat, (float)y);
        }
        v->w++;
        v->phi += dphi;
        v->phi -= floor(v->phi);
    }
}

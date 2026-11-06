// Time.c - live voice delay + tempo - AFLATOON
#include "VoiceTime.h"
#include <math.h>
#include <string.h>

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

static inline double tapr(const float *ring, double pos) {
    double fl = floor(pos);
    double fr = pos - fl;
    int64_t i0 = (int64_t)fl;
    double a = ring[(uint64_t)i0 & AT_MASK];
    double b = ring[(uint64_t)(i0 + 1) & AT_MASK];
    return a + (b - a) * fr;
}

void ap_time_init(AP_Time *t, double fs) {
    memset(t, 0, sizeof(*t));
    t->fs = (fs > 1000.0) ? fs : 48000.0;
}

void ap_time_process(AP_Time *t, void *buf[2], int ch, int interleaved, int isFloat,
                     int frames, float tempo, float delayMs) {
    if (!t || ch < 1 || ch > AT_MAXCH || frames <= 0 || !buf[0]) return;
    if (!interleaved && ch > 1 && !buf[1]) return;

    if (!(tempo >= 0.5f)) tempo = 0.5f;
    if (tempo > 2.0f) tempo = 2.0f;
    if (!(delayMs > 0.0f)) delayMs = 0.0f;
    if (delayMs > 2000.0f) delayMs = 2000.0f;

    int tempoOn = fabsf(tempo - 1.0f) > 0.01f;
    if (!tempoOn && delayMs < 1.0f) { t->active = 0; return; }     // bypass

    const double fs = t->fs;
    const double cap = (double)(AT_RING - 4096);
    const double span = tempoOn ? 0.25 * fs : 64.0;
    double lo = delayMs * fs / 1000.0;
    if (tempoOn && lo < 0.015 * fs) lo = 0.015 * fs;
    if (lo < 8.0) lo = 8.0;
    if (lo + span > cap) lo = cap - span;
    const double hi = lo + span;
    const double rate = tempoOn ? (double)tempo : 1.0;
    const int FADE = (int)(0.010 * fs);

    if (!t->active) {
        memset(t->ring, 0, sizeof t->ring);
        t->w = 0;
        t->r1 = -((tempoOn && tempo > 1.0f) ? hi : lo);     // fast: start high and drain; else start low
        t->r2 = t->r1;
        t->fade = 0;
        t->active = 1;
    }

    for (int i = 0; i < frames; i++) {
        float x[AT_MAXCH] = {0, 0};
        for (int c = 0; c < ch; c++) x[c] = get_s(buf, interleaved, ch, i, c, isFloat);
        for (int c = 0; c < ch; c++) t->ring[c][(uint64_t)t->w & AT_MASK] = x[c];
        t->w++;

        double lat = (double)t->w - t->r1;
        if (t->fade <= 0) {
            if (lat < lo - 0.5)      { t->r2 = t->r1; t->r1 = (double)t->w - hi; t->fade = FADE; }  // repeat a little
            else if (lat > hi + 0.5) { t->r2 = t->r1; t->r1 = (double)t->w - lo; t->fade = FADE; }  // skip a little
        }

        for (int c = 0; c < ch; c++) {
            double y = tapr(t->ring[c], t->r1);
            if (t->fade > 0) {
                double a = 1.0 - (double)t->fade / (double)FADE;
                y = y * a + tapr(t->ring[c], t->r2) * (1.0 - a);
            }
            put_s(buf, interleaved, ch, i, c, isFloat, (float)y);
        }
        t->r1 += rate;
        if (t->fade > 0) { t->r2 += rate; t->fade--; }
    }
}

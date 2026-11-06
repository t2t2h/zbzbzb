// DSP.h - voice pitch shifter + 3-band EQ (pure C, no platform dependencies)
// AFLATOON
#ifndef AP_DSP_H
#define AP_DSP_H
#include <stdint.h>

#define AP_MAXCH  2
#define AP_RING   8192
#define AP_RMASK  (AP_RING - 1)
#define AP_DELAY  1024.0

typedef struct {
    double b0, b1, b2, a1, a2;
    double z1, z2;
} AP_Biquad;

typedef struct {
    double   fs;
    int64_t  w;
    double   phi;
    float    ring[AP_MAXCH][AP_RING];
    AP_Biquad bass[AP_MAXCH], mid[AP_MAXCH], treb[AP_MAXCH];
    float    lastBass, lastMid, lastTreb;
    int      eqInit;
} AP_Voice;

void ap_voice_init(AP_Voice *v, double fs);

// buf: interleaved -> buf[0] holds all channels; planar -> buf[c] holds channel c
// isFloat: 1 = Float32, 0 = SInt16
void ap_voice_process(AP_Voice *v, void *buf[2], int ch, int interleaved, int isFloat,
                      int frames, int pitchOn, float pitch,
                      int eqOn, float bassDB, float midDB, float trebleDB);

#endif

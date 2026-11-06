// Time.h - live voice DELAY + TEMPO (pure C) - AFLATOON
//
//  delay : the stream is held back by N ms (clean, no artifacts)
//  tempo : 0.5x .. 2.0x. A live stream cannot be played faster/slower forever, so the read head
//          drifts inside a 250 ms window and is re-centred with a 10 ms crossfade
//          (slow -> skips a little audio, fast -> repeats a little audio). Pitch is kept
//          by the pitch shifter in Audio.c.
#ifndef AP_TIME_H
#define AP_TIME_H
#include <stdint.h>

#define AT_MAXCH 2
#define AT_RING  131072            /* power of two, ~2.7 s @ 48 kHz */
#define AT_MASK  (AT_RING - 1)

typedef struct {
    double  fs;
    int64_t w;
    double  r1, r2;
    int     fade;
    int     active;
    float   ring[AT_MAXCH][AT_RING];
} AP_Time;

void ap_time_init(AP_Time *t, double fs);

// in-place on the render buffer (same layout rules as ap_voice_process)
void ap_time_process(AP_Time *t, void *buf[2], int ch, int interleaved, int isFloat,
                     int frames, float tempo, float delayMs);
#endif

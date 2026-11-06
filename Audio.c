// Audio.c - AudioUnitRender compatibility path for Agora-style RemoteIO capture/playback - AFLATOON
//   bus 1 is treated as mic capture; bus 0 as playback. This is a best-effort AudioUnit path,
//   NOT Agora raw-frame delegate integration. Verify with two live peers before relying on it.
#include "Shared.h"
#include "DSP.h"
#include "VoiceTime.h"
#include <math.h>
#include <string.h>
#include <os/lock.h>

volatile int   ap_pitchOn = 0;
volatile float ap_pitch = 1.0f;
volatile int   ap_eqOn = 0;
volatile float ap_eqBass = 0.0f, ap_eqMid = 0.0f, ap_eqTreble = 0.0f;

volatile int   ap_micTimeOn = 0;
volatile float ap_micDelay = 0.0f, ap_micTempo = 1.0f;

volatile int   ap_roomOn = 0;
volatile float ap_roomSpeed = 1.0f;
volatile int   ap_roomTimeOn = 0;
volatile float ap_roomDelay = 0.0f, ap_roomTempo = 1.0f;

volatile unsigned long ap_micCalls = 0, ap_roomCalls = 0;

OSStatus (*ap_orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                    const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *) = 0;

// one slot per (AudioUnit, bus) pair - mic and room state never mix, even on the same unit.
// Slots are recycled (least-recently-used) so route changes / re-created AudioUnits never exhaust them.
#define AP_SLOTS 6
typedef struct {
    AudioUnit     unit;
    UInt32        bus;
    int           used;
    int           supported;
    int           isFloat;
    UInt32        bps;          // bytes per sample the slot was created for
    unsigned long lastUse;
    AP_Voice      v;
    AP_Time       t;
} Slot;
static Slot gSlots[AP_SLOTS];
static os_unfair_lock gSlotLock = OS_UNFAIR_LOCK_INIT;
static unsigned long gTick = 0;

static void slot_init(Slot *s, AudioUnit u, UInt32 bus, UInt32 bytesPerSample) {
    double fs = 48000.0;
    int supported = (bytesPerSample == 2 || bytesPerSample == 4);
    int isFloat = (bytesPerSample == 4);
    AudioStreamBasicDescription d;
    UInt32 sz = sizeof d;
    memset(&d, 0, sizeof d);
    // the buffer AudioUnitRender fills for a given bus always carries that bus's Output-scope format
    if (AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus, &d, &sz) == noErr) {
        if (d.mSampleRate > 0) fs = d.mSampleRate;
        if (d.mFormatID == kAudioFormatLinearPCM) {
            if ((d.mFormatFlags & kAudioFormatFlagIsFloat) && d.mBitsPerChannel == 32) { supported = 1; isFloat = 1; }
            else if (!(d.mFormatFlags & kAudioFormatFlagIsFloat) && (d.mFormatFlags & kAudioFormatFlagIsSignedInteger) && d.mBitsPerChannel == 16) { supported = 1; isFloat = 0; }
            else supported = 0;
        } else supported = 0;
    }
    __atomic_store_n(&s->used, 0, __ATOMIC_RELEASE);          // hide the slot while it is rewritten
    ap_voice_init(&s->v, fs);
    ap_time_init(&s->t, fs);
    s->supported = supported;
    s->isFloat = isFloat;
    s->bps = bytesPerSample;
    s->bus = bus;
    s->unit = u;
    s->lastUse = ++gTick;
    __atomic_store_n(&s->used, 1, __ATOMIC_RELEASE);          // publish last
}

static Slot *slot_for(AudioUnit u, UInt32 bus, UInt32 bytesPerSample) {
    // fast path: no lock when the slot already exists with the same sample size
    for (int i = 0; i < AP_SLOTS; i++) {
        Slot *s = &gSlots[i];
        if (__atomic_load_n(&s->used, __ATOMIC_ACQUIRE) && s->unit == u && s->bus == bus && s->bps == bytesPerSample) {
            s->lastUse = ++gTick;
            return s;
        }
    }
    os_unfair_lock_lock(&gSlotLock);
    Slot *pick = NULL;
    for (int i = 0; i < AP_SLOTS && !pick; i++) {       // same unit/bus but the format changed -> re-init it
        if (gSlots[i].used && gSlots[i].unit == u && gSlots[i].bus == bus) pick = &gSlots[i];
    }
    for (int i = 0; i < AP_SLOTS && !pick; i++)         // otherwise a free slot
        if (!gSlots[i].used) pick = &gSlots[i];
    if (!pick) {                                         // otherwise recycle the least recently used one
        pick = &gSlots[0];
        for (int i = 1; i < AP_SLOTS; i++) if (gSlots[i].lastUse < pick->lastUse) pick = &gSlots[i];
    }
    slot_init(pick, u, bus, bytesPerSample);
    os_unfair_lock_unlock(&gSlotLock);
    return pick;
}

// shared plumbing: validate the buffer, find/alloc its slot, run the DSP
static void process_bus(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                        UInt32 inNumberFrames, AudioBufferList *ioData, UInt32 bus,
                        int pitchOn, float pitch, int eqOn, float bassDB, float midDB, float trebleDB,
                        int timeOn, float tempo, float delayMs) {
    if (!pitchOn && !eqOn && !timeOn) return;
    if (ioActionFlags && (*ioActionFlags & kAudioUnitRenderAction_OutputIsSilence)) {
        if (!timeOn) return;
        // keep feeding the delay line with real silence so the delayed tail still plays out
        for (UInt32 b = 0; b < ioData->mNumberBuffers; b++)
            if (ioData->mBuffers[b].mData) memset(ioData->mBuffers[b].mData, 0, ioData->mBuffers[b].mDataByteSize);
        *ioActionFlags &= ~kAudioUnitRenderAction_OutputIsSilence;
    }

    UInt32 nb = ioData->mNumberBuffers;
    if (nb < 1 || nb > 2) return;
    int interleaved = (nb == 1);
    int ch = interleaved ? (int)ioData->mBuffers[0].mNumberChannels : (int)nb;
    if (ch < 1 || ch > 2 || !ioData->mBuffers[0].mData) return;
    if (!interleaved && (!ioData->mBuffers[1].mData ||
                         ioData->mBuffers[0].mNumberChannels != 1 ||
                         ioData->mBuffers[1].mNumberChannels != 1)) return;

    // Agora / RemoteIO can expose either interleaved or planar PCM. Validate EVERY
    // plane before touching it; using plane 0's byte count for plane 1 can overrun.
    UInt32 bytes = ioData->mBuffers[0].mDataByteSize;
    UInt32 div = inNumberFrames * (interleaved ? (UInt32)ch : 1u);
    if (div == 0 || bytes % div != 0) return;
    UInt32 bps = bytes / div;
    if (bps != 2 && bps != 4) return;
    if (!interleaved && ioData->mBuffers[1].mDataByteSize < inNumberFrames * bps) return;

    Slot *s = slot_for(inUnit, bus, bps);
    if (!s || !s->supported) return;
    if ((s->isFloat && bps != 4) || (!s->isFloat && bps != 2)) return;

    void *bufs[2] = { ioData->mBuffers[0].mData, nb > 1 ? ioData->mBuffers[1].mData : NULL };

    // 1) time: delay + tempo (what the other side hears / what you hear)
    int tempoOn = timeOn && fabsf(tempo - 1.0f) > 0.01f;
    if (timeOn) ap_time_process(&s->t, bufs, ch, interleaved, s->isFloat, (int)inNumberFrames, tempo, delayMs);
    else s->t.active = 0;

    // 2) pitch + EQ. Tempo moves the pitch too, so the pitch shifter cancels it (pitch / tempo).
    if (tempoOn) { pitch = (pitchOn ? pitch : 1.0f) / tempo; pitchOn = 1; }
    if (pitchOn || eqOn)
        ap_voice_process(&s->v, bufs, ch, interleaved, s->isFloat, (int)inNumberFrames,
                         pitchOn, pitch, eqOn, bassDB, midDB, trebleDB);
}

OSStatus ap_AudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber,
                            UInt32 inNumberFrames, AudioBufferList *ioData) {
    if (!ap_orig_AudioUnitRender) return kAudioUnitErr_Uninitialized;
    OSStatus st = ap_orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp,
                                          inOutputBusNumber, inNumberFrames, ioData);
    if (st != noErr || !ioData || inNumberFrames == 0) return st;

    if (inOutputBusNumber == 1) {
        // mic input: pitch + EQ, exactly as before
        __atomic_fetch_add(&ap_micCalls, 1, __ATOMIC_RELAXED);
        process_bus(inUnit, ioActionFlags, inNumberFrames, ioData, 1,
                   ap_pitchOn, ap_pitch, ap_eqOn, ap_eqBass, ap_eqMid, ap_eqTreble,
                   ap_micTimeOn, ap_micTempo, ap_micDelay);
    } else if (inOutputBusNumber == 0) {
        // room / playback bus: the mixed voices of everyone else, speed only, local ears only
        __atomic_fetch_add(&ap_roomCalls, 1, __ATOMIC_RELAXED);
        process_bus(inUnit, ioActionFlags, inNumberFrames, ioData, 0,
                   ap_roomOn, ap_roomSpeed, 0, 0, 0, 0,
                   ap_roomTimeOn, ap_roomTempo, ap_roomDelay);
    }
    return st;
}

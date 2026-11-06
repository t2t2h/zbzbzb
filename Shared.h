// Shared.h - AFLATOON
#ifndef AP_SHARED_H
#define AP_SHARED_H

#include <AudioToolbox/AudioToolbox.h>

#define AP_CREDIT_EN  "AFLATOON"
#define AP_CREDIT_AR  "أفلاطون"
#define AP_OWNER      "MUBDI"

// ---- DNS (Hook.m) ----
extern volatile int ap_dnsOn;
extern const char * volatile ap_dnsServer;
extern volatile unsigned long ap_dnsResolved;      // real counter of overrides done
extern char ap_dnsLastHost[64];
void ap_dns_clear_cache(void);

// ---- net.boost (Hook.m): socket tuning, NOT a VPN ----
extern volatile int ap_netBoostOn;
int ap_net_boosted_count(void);

// ---- MIC path = what the OTHER side hears (bus 1) ----
extern volatile int   ap_pitchOn;
extern volatile float ap_pitch;                    // 0.5 .. 3.0
extern volatile int   ap_eqOn;
extern volatile float ap_eqBass, ap_eqMid, ap_eqTreble;
extern volatile int   ap_micTimeOn;                // delay + tempo on the outgoing voice
extern volatile float ap_micDelay;                 // ms 0 .. 2000
extern volatile float ap_micTempo;                 // 0.5 .. 2.0

// ---- ROOM path = what YOU hear from the others (bus 0, local playback only) ----
extern volatile int   ap_roomOn;                   // pitch of incoming voices
extern volatile float ap_roomSpeed;                // pitch ratio 0.5 .. 3.0 (1.0 = normal)
extern volatile int   ap_roomTimeOn;               // delay + tempo on incoming voices
extern volatile float ap_roomDelay;                // ms 0 .. 2000
extern volatile float ap_roomTempo;                // 0.5 .. 2.0

// real counters: AudioUnitRender callbacks observed on the assumed capture/playback buses
extern volatile unsigned long ap_micCalls, ap_roomCalls;

extern OSStatus (*ap_orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                           const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);
OSStatus ap_AudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber,
                            UInt32 inNumberFrames, AudioBufferList *ioData);

// ---- entry points ----
void ap_install_hooks(void);   // Hook.m
void ap_ui_start(void);        // UI.m
void ap_settings_load(void);    // Main.m - restore persistent settings
void ap_settings_save(void);    // Main.m - persist all feature settings

#endif

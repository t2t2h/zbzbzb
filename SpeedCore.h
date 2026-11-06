#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif
void   MBSpeedInstall(void);
void   MBSpeedSetScale(double scale);
double MBSpeedGetScale(void);
void   MBSpeedSetEnabled(bool on);
bool   MBSpeedIsEnabled(void);
void   MBSpeedSetWallClock(bool on);   // also speed up CLOCK_REALTIME / gettimeofday
bool   MBSpeedGetWallClock(void);
void   MBSpeedStats(double *gameSeconds, double *realSeconds);
#ifdef __cplusplus
}
#endif

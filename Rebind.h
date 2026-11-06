// Rebind.h - one shared symbol-pointer rebinder (fishhook style), no Substrate / no jailbreak.
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif
// Register a replacement BEFORE calling ap_rebind_start().
//   name   : C symbol name without the leading underscore
//   system : 1 = also patch Apple system frameworks (used for getaddrinfo / socket)
//            0 = patch only the app + its own frameworks (used for AudioUnitRender and the clock
//                hooks: Agora/WebRTC live inside the app, and system code must not count fake time twice)
void ap_rebind_add(const char *name, void *replacement, int system);
// Patches every loaded image and every image loaded later.
void ap_rebind_start(void);
#ifdef __cplusplus
}
#endif

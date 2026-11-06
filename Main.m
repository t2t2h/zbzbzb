// Main.m - AFLATOON V2 persistent settings bootstrap
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <string.h>
#include "Shared.h"
#include "SpeedCore.h"

static const char *APDNSOptions[] = {
    "1.1.1.1", "8.8.8.8", "9.9.9.9",
    "208.67.222.222", "94.140.14.14", "185.228.168.9"
};

void ap_settings_save(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSInteger dnsIndex = 0;
    for (NSInteger i = 0; i < 6; i++) if (strcmp(ap_dnsServer, APDNSOptions[i]) == 0) { dnsIndex = i; break; }
    [d setBool:(ap_dnsOn != 0) forKey:@"apv2_dns_on"];
    [d setInteger:dnsIndex forKey:@"apv2_dns_index"];
    [d setBool:(ap_netBoostOn != 0) forKey:@"apv2_net_boost"];
    [d setBool:(ap_pitchOn != 0) forKey:@"apv2_pitch_on"];
    [d setDouble:ap_pitch forKey:@"apv2_pitch"];
    [d setBool:(ap_eqOn != 0) forKey:@"apv2_eq_on"];
    [d setDouble:ap_eqBass forKey:@"apv2_eq_bass"];
    [d setDouble:ap_eqMid forKey:@"apv2_eq_mid"];
    [d setDouble:ap_eqTreble forKey:@"apv2_eq_treble"];
    [d setBool:(ap_roomOn != 0) forKey:@"apv2_room_on"];
    [d setDouble:ap_roomSpeed forKey:@"apv2_room_pitch"];
    [d setBool:(ap_micTimeOn != 0) forKey:@"apv2_out_time_on"];
    [d setDouble:ap_micDelay forKey:@"apv2_out_delay"];
    [d setDouble:ap_micTempo forKey:@"apv2_out_tempo"];
    [d setBool:(ap_roomTimeOn != 0) forKey:@"apv2_in_time_on"];
    [d setDouble:ap_roomDelay forKey:@"apv2_in_delay"];
    [d setDouble:ap_roomTempo forKey:@"apv2_in_tempo"];
    [d setBool:MBSpeedIsEnabled() forKey:@"apv2_speed_on"];
    [d setDouble:MBSpeedGetScale() forKey:@"apv2_speed_scale"];
    [d setBool:MBSpeedGetWallClock() forKey:@"apv2_wall_clock"];
    [d synchronize];
}

void ap_settings_load(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([d objectForKey:@"apv2_dns_on"]) ap_dnsOn = [d boolForKey:@"apv2_dns_on"];
    NSInteger dns = [d objectForKey:@"apv2_dns_index"] ? [d integerForKey:@"apv2_dns_index"] : 0;
    if (dns < 0 || dns >= 6) dns = 0;
    ap_dnsServer = APDNSOptions[dns];
    if ([d objectForKey:@"apv2_net_boost"]) ap_netBoostOn = [d boolForKey:@"apv2_net_boost"];
    if ([d objectForKey:@"apv2_pitch_on"]) ap_pitchOn = [d boolForKey:@"apv2_pitch_on"];
    if ([d objectForKey:@"apv2_pitch"]) ap_pitch = (float)[d doubleForKey:@"apv2_pitch"];
    if ([d objectForKey:@"apv2_eq_on"]) ap_eqOn = [d boolForKey:@"apv2_eq_on"];
    if ([d objectForKey:@"apv2_eq_bass"]) ap_eqBass = (float)[d doubleForKey:@"apv2_eq_bass"];
    if ([d objectForKey:@"apv2_eq_mid"]) ap_eqMid = (float)[d doubleForKey:@"apv2_eq_mid"];
    if ([d objectForKey:@"apv2_eq_treble"]) ap_eqTreble = (float)[d doubleForKey:@"apv2_eq_treble"];
    if ([d objectForKey:@"apv2_room_on"]) ap_roomOn = [d boolForKey:@"apv2_room_on"];
    if ([d objectForKey:@"apv2_room_pitch"]) ap_roomSpeed = (float)[d doubleForKey:@"apv2_room_pitch"];
    if ([d objectForKey:@"apv2_out_time_on"]) ap_micTimeOn = [d boolForKey:@"apv2_out_time_on"];
    if ([d objectForKey:@"apv2_out_delay"]) ap_micDelay = (float)[d doubleForKey:@"apv2_out_delay"];
    if ([d objectForKey:@"apv2_out_tempo"]) ap_micTempo = (float)[d doubleForKey:@"apv2_out_tempo"];
    if ([d objectForKey:@"apv2_in_time_on"]) ap_roomTimeOn = [d boolForKey:@"apv2_in_time_on"];
    if ([d objectForKey:@"apv2_in_delay"]) ap_roomDelay = (float)[d doubleForKey:@"apv2_in_delay"];
    if ([d objectForKey:@"apv2_in_tempo"]) ap_roomTempo = (float)[d doubleForKey:@"apv2_in_tempo"];
    double scale = [d objectForKey:@"apv2_speed_scale"] ? [d doubleForKey:@"apv2_speed_scale"] :
                   ([d objectForKey:@"am_scale"] ? [d doubleForKey:@"am_scale"] : 1.0);
    MBSpeedSetScale(scale);
    MBSpeedSetEnabled([d objectForKey:@"apv2_speed_on"] ? [d boolForKey:@"apv2_speed_on"] : [d boolForKey:@"am_speed_on"]);
    MBSpeedSetWallClock([d objectForKey:@"apv2_wall_clock"] ? [d boolForKey:@"apv2_wall_clock"] : [d boolForKey:@"am_wall"]);
    ap_dns_clear_cache();
}

__attribute__((constructor)) static void ap_entry(void) {
    ap_install_hooks();
    ap_settings_load();
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ap_ui_start(); });
    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { ap_settings_save(); }];
    [center addObserverForName:UIApplicationWillTerminateNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { ap_settings_save(); }];
}

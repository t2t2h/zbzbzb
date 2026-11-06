// UI.m - cyber-security style menu (blue/black, photo background) - AFLATOON (أفلاطون) - exclusive to MUBDI
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Network/Network.h>
#include <stdlib.h>
#include "Shared.h"
#include "SpeedCore.h"

extern const unsigned char ap_bg_jpg[];
extern const size_t ap_bg_jpg_len;

#define AP_BLUE   [UIColor colorWithRed:0.00 green:0.67 blue:1.00 alpha:1.0]
#define AP_BLUE2  [UIColor colorWithRed:0.12 green:0.33 blue:0.95 alpha:1.0]
#define AP_CYAN   [UIColor colorWithRed:0.45 green:0.88 blue:1.00 alpha:1.0]
#define AP_DIM    [UIColor colorWithRed:0.45 green:0.60 blue:0.78 alpha:1.0]
#define AP_BLACK  [UIColor colorWithRed:0.02 green:0.03 blue:0.07 alpha:1.0]

#define PW 336.0
#define PH 534.0

static const char *kDNSIP[6]   = { "1.1.1.1", "8.8.8.8", "9.9.9.9", "208.67.222.222", "94.140.14.14", "185.228.168.9" };
static NSString   *kDNSChip[6] = { @"CF", @"GG", @"Q9", @"ODNS", @"AG", @"CB" };
static NSString   *kDNSName[6] = { @"Cloudflare", @"Google", @"Quad9", @"OpenDNS", @"AdGuard", @"CleanBrowsing" };

// slider tags (value label = tag + 100)
#define T_PITCH      1
#define T_BASS       2
#define T_MID        3
#define T_TREBLE     4
#define T_ROOMPITCH  5
#define T_OUT_DELAY  6
#define T_OUT_TEMPO  7
#define T_IN_DELAY   8
#define T_IN_TEMPO   9
#define T_SPEED      10
// switch tags
#define S_DNS        40
#define S_HUD        41
#define S_BOOST      42
#define S_PITCH      43
#define S_EQ         44
#define S_ROOMPITCH  45
#define S_OUTTIME    46
#define S_INTIME     47
#define S_LINK       48
#define S_SPEED      49
#define S_WALL       50
// button tags
#define B_RESET_PITCH 60
#define B_RESET_EQ    61
#define B_RESET_ROOM  62
#define B_RESET_TIME  63
#define B_PRESET      400
#define B_DNS         300
#define B_TAB         200
#define B_VPN_IMPORT  310
#define B_VPN_CONNECT 311
#define B_VPN_DISCONNECT 312
#define B_PROFILE_SAVE 500
#define B_PROFILE_LOAD 510

static UIFont *APFont(CGFloat size, BOOL bold) {
    UIFont *f = [UIFont fontWithName:(bold ? @"Menlo-Bold" : @"Menlo-Regular") size:size];
    if (f) return f;
    return [UIFont monospacedSystemFontOfSize:size weight:(bold ? UIFontWeightBold : UIFontWeightRegular)];
}

static UILabel *APLabel(NSString *text, CGRect frame, CGFloat size, UIColor *color, BOOL bold) {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.textColor = color;
    l.font = APFont(size, bold);
    return l;
}

#pragma mark - pass-through window

@interface APWindow : UIWindow
@end
@implementation APWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return (v == self || v == self.rootViewController.view) ? nil : v;
}
@end

#pragma mark - panel

@interface APPanel : UIView <UIDocumentPickerDelegate>
@property (nonatomic, strong) UILabel *titleLabel, *cursor, *status, *footer, *console, *speedStats;
@property (nonatomic, strong) NSArray<UIButton *> *tabs;
@property (nonatomic, strong) NSArray<UIScrollView *> *pages;
@property (nonatomic, strong) UIView *underline, *scan;
@property (nonatomic, strong) NSArray<UIButton *> *dnsChips;
@property (nonatomic, assign) NSInteger cur;
@property (nonatomic, assign) BOOL link;
@property (nonatomic, strong) NSTimer *typeTimer, *consoleTimer;
@property (nonatomic, copy) void (^onHUD)(BOOL on);
- (void)playIntro;
- (void)closeAnimated;
- (void)consoleTick;
@end

static NSString *gNetworkPathLabel = @"path: checking";
static nw_path_monitor_t gPathMonitor;   // Network.framework C API (NWPathMonitor is Swift-only)

@implementation APPanel {
    unsigned long _lastMic, _lastRoom;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, PW, PH)];
    if (!self) return nil;

    self.backgroundColor = AP_BLACK;
    self.link = [NSUserDefaults.standardUserDefaults boolForKey:@"apv2_link_both"];
    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1.2;
    self.layer.borderColor = AP_BLUE2.CGColor;
    self.layer.shadowColor = AP_BLUE.CGColor;
    self.layer.shadowRadius = 18;
    self.layer.shadowOpacity = 0.55;
    self.layer.shadowOffset = CGSizeZero;

    CABasicAnimation *bp = [CABasicAnimation animationWithKeyPath:@"borderColor"];
    bp.fromValue = (id)AP_BLUE2.CGColor; bp.toValue = (id)AP_BLUE.CGColor;
    bp.duration = 1.6; bp.autoreverses = YES; bp.repeatCount = HUGE_VALF;
    [self.layer addAnimation:bp forKey:@"borderPulse"];

    [self buildBackdrop];

    NSArray *dotColors = @[AP_BLUE2, AP_BLUE, AP_CYAN];
    for (int i = 0; i < 3; i++) {
        UIView *d = [[UIView alloc] initWithFrame:CGRectMake(12 + i * 14, 13, 8, 8)];
        d.backgroundColor = dotColors[i];
        d.layer.cornerRadius = 4;
        [self addSubview:d];
    }

    self.titleLabel = APLabel(@"", CGRectMake(58, 8, 230, 18), 11, AP_CYAN, YES);
    [self addSubview:self.titleLabel];
    self.cursor = APLabel(@"█", CGRectMake(58, 8, 10, 18), 11, AP_BLUE, NO);
    CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
    blink.fromValue = @1.0; blink.toValue = @0.0; blink.duration = 0.5;
    blink.autoreverses = YES; blink.repeatCount = HUGE_VALF;
    [self.cursor.layer addAnimation:blink forKey:@"blink"];
    [self addSubview:self.cursor];

    UIButton *x = [UIButton buttonWithType:UIButtonTypeCustom];
    x.frame = CGRectMake(PW - 40, 4, 34, 26);
    [x setTitle:@"[x]" forState:UIControlStateNormal];
    [x setTitleColor:AP_BLUE forState:UIControlStateNormal];
    x.titleLabel.font = APFont(12, YES);
    [x addTarget:self action:@selector(closeAnimated) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:x];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 34, PW, 1)];
    sep.backgroundColor = [AP_BLUE2 colorWithAlphaComponent:0.5];
    [self addSubview:sep];

    NSArray *names = @[@"net", @"mic", @"room", @"time", @"speed", @"info"];
    const CGFloat tw = PW / 6.0;
    NSMutableArray *tb = [NSMutableArray array];
    for (int i = 0; i < 6; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(i * tw, 38, tw, 28);
        [b setTitle:names[i] forState:UIControlStateNormal];
        b.titleLabel.font = APFont(11, YES);
        [b setTitleColor:(i == 0 ? AP_CYAN : AP_DIM) forState:UIControlStateNormal];
        b.tag = B_TAB + i;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [tb addObject:b];
    }
    self.tabs = tb;
    self.underline = [[UIView alloc] initWithFrame:CGRectMake(10, 65, tw - 20, 2)];
    self.underline.backgroundColor = AP_BLUE;
    self.underline.layer.shadowColor = AP_BLUE.CGColor;
    self.underline.layer.shadowRadius = 4;
    self.underline.layer.shadowOpacity = 1;
    self.underline.layer.shadowOffset = CGSizeZero;
    [self addSubview:self.underline];

    self.pages = @[[self buildNet], [self buildMic], [self buildRoom], [self buildTime], [self buildSpeed], [self buildInfo]];
    for (NSUInteger i = 0; i < self.pages.count; i++) {
        UIScrollView *p = self.pages[i];
        p.frame = CGRectMake(0, 70, PW, 338);
        p.hidden = (i != 0);
        [self addSubview:p];
    }
    self.cur = 0;

    // live console (real counters)
    UIView *sepC = [[UIView alloc] initWithFrame:CGRectMake(0, 410, PW, 1)];
    sepC.backgroundColor = [AP_BLUE2 colorWithAlphaComponent:0.5];
    [self addSubview:sepC];
    self.console = APLabel(@"", CGRectMake(12, 415, PW - 24, 64), 8.5, AP_CYAN, NO);
    self.console.numberOfLines = 6;
    [self addSubview:self.console];

    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(0, 484, PW, 1)];
    sep2.backgroundColor = [AP_BLUE2 colorWithAlphaComponent:0.5];
    [self addSubview:sep2];
    NSString *credit = [NSString stringWithFormat:@"© %s  |  %s", AP_CREDIT_EN, AP_CREDIT_AR];
    self.footer = APLabel(credit, CGRectMake(0, 490, PW, 20), 12, AP_CYAN, YES);
    self.footer.textAlignment = NSTextAlignmentCenter;
    CABasicAnimation *fp = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fp.fromValue = @0.55; fp.toValue = @1.0; fp.duration = 1.4; fp.autoreverses = YES; fp.repeatCount = HUGE_VALF;
    [self.footer.layer addAnimation:fp forKey:@"pulse"];
    [self addSubview:self.footer];
    UILabel *own = APLabel(@"[ EXCLUSIVE  ·  MUBDI ]", CGRectMake(0, 511, PW, 16), 10, AP_DIM, NO);
    own.textAlignment = NSTextAlignmentCenter;
    [self addSubview:own];

    self.scan = [[UIView alloc] initWithFrame:CGRectMake(1, 36, PW - 2, 2)];
    self.scan.backgroundColor = [AP_BLUE colorWithAlphaComponent:0.28];
    self.scan.layer.shadowColor = AP_BLUE.CGColor;
    self.scan.layer.shadowRadius = 5; self.scan.layer.shadowOpacity = 1; self.scan.layer.shadowOffset = CGSizeZero;
    self.scan.userInteractionEnabled = NO;
    [self addSubview:self.scan];
    CABasicAnimation *sc = [CABasicAnimation animationWithKeyPath:@"position.y"];
    sc.fromValue = @40; sc.toValue = @(PH - 4); sc.duration = 4.2; sc.repeatCount = HUGE_VALF;
    [self.scan.layer addAnimation:sc forKey:@"scan"];

    [self refreshStatus];
    return self;
}

#pragma mark backdrop (your photo + dark overlay + hex rain)

- (void)buildBackdrop {
    UIView *clip = [[UIView alloc] initWithFrame:self.bounds];
    clip.layer.cornerRadius = 12;
    clip.layer.masksToBounds = YES;
    clip.userInteractionEnabled = NO;
    [self addSubview:clip];

    NSData *d = [NSData dataWithBytesNoCopy:(void *)ap_bg_jpg length:ap_bg_jpg_len freeWhenDone:NO];
    UIImage *img = [UIImage imageWithData:d];
    if (img) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:clip.bounds];
        iv.image = img;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        [clip addSubview:iv];
    }
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = clip.bounds;
    g.colors = @[(id)[UIColor colorWithRed:0.01 green:0.03 blue:0.09 alpha:0.80].CGColor,
                 (id)[UIColor colorWithRed:0.01 green:0.02 blue:0.06 alpha:0.90].CGColor];
    [clip.layer addSublayer:g];

    for (int i = 0; i < 10; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(8 + i * 33.0, 0, 22, 170)];
        l.numberOfLines = 0;
        l.font = APFont(9, NO);
        l.textColor = AP_CYAN;
        l.alpha = 0.13;
        NSMutableString *s = [NSMutableString string];
        for (int k = 0; k < 12; k++) [s appendFormat:@"%X%X\n", arc4random_uniform(16), arc4random_uniform(16)];
        l.text = s;
        [clip addSubview:l];
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"position.y"];
        a.fromValue = @(-90); a.toValue = @(PH + 90);
        a.duration = 5.0 + arc4random_uniform(50) / 10.0;
        a.timeOffset = arc4random_uniform(50) / 10.0;
        a.repeatCount = HUGE_VALF;
        [l.layer addAnimation:a forKey:@"rain"];
    }
}

#pragma mark builders

- (UIScrollView *)newPage:(CGFloat)contentH {
    UIScrollView *p = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, PW, 338)];
    p.contentSize = CGSizeMake(PW, contentH);
    p.showsVerticalScrollIndicator = NO;
    p.alwaysBounceVertical = (contentH > 338);
    return p;
}

- (UISwitch *)addSwitchTo:(UIView *)page y:(CGFloat)y title:(NSString *)t tag:(NSInteger)tag on:(BOOL)on {
    [page addSubview:APLabel(t, CGRectMake(14, y + 5, 220, 20), 12, AP_BLUE, YES)];
    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(PW - 14 - 51, y, 51, 31)];
    s.onTintColor = AP_BLUE2;
    s.tag = tag;
    s.on = on;
    [s addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [page addSubview:s];
    return s;
}

- (void)addSliderTo:(UIView *)page y:(CGFloat)y title:(NSString *)t min:(float)mn max:(float)mx val:(float)v tag:(NSInteger)tag {
    [page addSubview:APLabel(t, CGRectMake(14, y, 170, 16), 11, AP_DIM, NO)];
    UILabel *val = APLabel(@"", CGRectMake(PW - 14 - 120, y, 120, 16), 11, AP_CYAN, YES);
    val.textAlignment = NSTextAlignmentRight;
    val.tag = tag + 100;
    [page addSubview:val];
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(14, y + 18, PW - 28, 28)];
    s.minimumValue = mn; s.maximumValue = mx; s.value = v; s.tag = tag;
    s.minimumTrackTintColor = AP_BLUE;
    s.maximumTrackTintColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    s.thumbTintColor = AP_CYAN;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [page addSubview:s];
    [self setValueLabel:val forTag:tag value:v];
}

- (void)setValueLabel:(UILabel *)l forTag:(NSInteger)tag value:(float)v {
    switch (tag) {
        case T_OUT_DELAY: case T_IN_DELAY: l.text = [NSString stringWithFormat:@"%.0f ms", v]; break;
        case T_BASS: case T_MID: case T_TREBLE: l.text = [NSString stringWithFormat:@"%+.1f dB", v]; break;
        default: l.text = [NSString stringWithFormat:@"%.2fx", v]; break;
    }
}

- (UIButton *)addButtonTo:(UIView *)page frame:(CGRect)f title:(NSString *)t tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:AP_CYAN forState:UIControlStateNormal];
    b.titleLabel.font = APFont(11, YES);
    b.layer.borderWidth = 1;
    b.layer.borderColor = AP_BLUE2.CGColor;
    b.layer.cornerRadius = 5;
    b.backgroundColor = [UIColor colorWithRed:0.03 green:0.06 blue:0.14 alpha:0.85];
    b.tag = tag;
    [b addTarget:self action:@selector(resetTapped:) forControlEvents:UIControlEventTouchUpInside];
    [page addSubview:b];
    return b;
}

- (UILabel *)note:(NSString *)t y:(CGFloat)y lines:(NSInteger)n page:(UIView *)p {
    UILabel *l = APLabel(t, CGRectMake(14, y, PW - 28, 13.0 * n + 4), 10, AP_DIM, NO);
    l.numberOfLines = n;
    [p addSubview:l];
    return l;
}

- (UIScrollView *)buildNet {
    UIScrollView *p = [self newPage:455];
    [p addSubview:APLabel(@"// dns.override  (this app only, 6 resolvers)", CGRectMake(14, 4, PW - 20, 16), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:20 title:@"if (dns.on)" tag:S_DNS on:ap_dnsOn != 0];

    CGFloat cw = ((PW - 28) - 2 * 6) / 3.0;
    NSMutableArray *chips = [NSMutableArray array];
    for (int i = 0; i < 6; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(14 + (i % 3) * (cw + 6), 56 + (i / 3) * 30, cw, 25);
        [b setTitle:kDNSChip[i] forState:UIControlStateNormal];
        b.titleLabel.font = APFont(11, YES);
        b.layer.borderWidth = 1; b.layer.cornerRadius = 5;
        b.tag = B_DNS + i;
        [b addTarget:self action:@selector(dnsChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [p addSubview:b];
        [chips addObject:b];
    }
    self.dnsChips = chips;

    self.status = APLabel(@"", CGRectMake(14, 122, PW - 28, 48), 11, AP_CYAN, NO);
    self.status.numberOfLines = 3;
    [p addSubview:self.status];

    [p addSubview:APLabel(@"// live.monitor (path + HTTPS RTT, not game-server ICMP)", CGRectMake(14, 178, PW - 20, 14), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:194 title:@"if (hud.show)" tag:S_HUD on:[NSUserDefaults.standardUserDefaults boolForKey:@"apv2_hud_on"]];
    [p addSubview:APLabel(@"// net.boost  (socket tuning - NOT a VPN)", CGRectMake(14, 236, PW - 20, 14), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:252 title:@"if (net.boost)" tag:S_BOOST on:ap_netBoostOn != 0];
    [self note:@"// DNS + socket tuning are not a VPN" y:292 lines:1 page:p];

    UIButton *vpnImport = [self addButtonTo:p frame:CGRectMake(14, 316, PW - 28, 30)
                                      title:@"[ IMPORT MARCO .CONF → WIREGUARD ]" tag:B_VPN_IMPORT];
    [vpnImport addTarget:self action:@selector(importWireGuardProfileTapped:) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:APLabel(@"// choose a .conf file; share to the companion host app",
                          CGRectMake(14, 352, PW - 28, 28), 9, AP_DIM, NO)];
    UIButton *connect = [self addButtonTo:p frame:CGRectMake(14, 386, PW - 28, 28) title:@"[ CONNECT SAVED WIREGUARD PROFILE ]" tag:B_VPN_CONNECT];
    [connect removeTarget:self action:@selector(resetTapped:) forControlEvents:UIControlEventTouchUpInside];
    [connect addTarget:self action:@selector(companionVPNTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *disconnect = [self addButtonTo:p frame:CGRectMake(14, 420, PW - 28, 28) title:@"[ DISCONNECT WIREGUARD ]" tag:B_VPN_DISCONNECT];
    [disconnect removeTarget:self action:@selector(resetTapped:) forControlEvents:UIControlEventTouchUpInside];
    [disconnect addTarget:self action:@selector(companionVPNTapped:) forControlEvents:UIControlEventTouchUpInside];

    [self refreshDNSChips];
    return p;
}

- (UIScrollView *)buildMic {
    UIScrollView *p = [self newPage:366];
    [p addSubview:APLabel(@"// mic.out  -> what the OTHER side hears", CGRectMake(14, 4, PW - 20, 16), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:20 title:@"if (pitch.on)" tag:S_PITCH on:ap_pitchOn != 0];
    [self addSliderTo:p y:58 title:@"voice.pitch" min:0.5f max:3.0f val:ap_pitch tag:T_PITCH];
    [self addButtonTo:p frame:CGRectMake(14, 108, 86, 24) title:@"[ reset ]" tag:B_RESET_PITCH];
    [p addSubview:APLabel(@"// eq.biquad  (mic)", CGRectMake(14, 142, PW - 20, 14), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:158 title:@"if (eq.on)" tag:S_EQ on:ap_eqOn != 0];
    [self addSliderTo:p y:196 title:@"eq.bass   120Hz" min:-12 max:12 val:ap_eqBass tag:T_BASS];
    [self addSliderTo:p y:240 title:@"eq.mid    1kHz" min:-12 max:12 val:ap_eqMid tag:T_MID];
    [self addSliderTo:p y:284 title:@"eq.treble 6kHz" min:-12 max:12 val:ap_eqTreble tag:T_TREBLE];
    [self addButtonTo:p frame:CGRectMake(14, 332, 86, 24) title:@"[ reset ]" tag:B_RESET_EQ];
    return p;
}

- (UIScrollView *)buildRoom {
    UIScrollView *p = [self newPage:338];
    [p addSubview:APLabel(@"// room.in  -> what YOU hear (local only)", CGRectMake(14, 4, PW - 20, 16), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:20 title:@"if (room.pitch)" tag:S_ROOMPITCH on:ap_roomOn != 0];
    [self addSliderTo:p y:58 title:@"room.pitch" min:0.5f max:3.0f val:ap_roomSpeed tag:T_ROOMPITCH];
    [self addButtonTo:p frame:CGRectMake(14, 108, 86, 24) title:@"[ reset ]" tag:B_RESET_ROOM];
    [self note:@"// changes the pitch of the voices you\n// hear, on this device only.\n// for delay / tempo of incoming voices\n// use the [time] tab (IN section).\n// needs an app that plays voice\n// through AudioUnitRender bus 0." y:150 lines:6 page:p];
    return p;
}

- (UIScrollView *)buildTime {
    UIScrollView *p = [self newPage:540];
    [p addSubview:APLabel(@"// time.shift  (delay + tempo)", CGRectMake(14, 4, PW - 20, 16), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:20 title:@"if (link.both)" tag:S_LINK on:self.link];

    [p addSubview:APLabel(@"[OUT] mic  -> the other side hears you", CGRectMake(14, 62, PW - 20, 14), 10, AP_CYAN, YES)];
    [self addSwitchTo:p y:78 title:@"if (out.time)" tag:S_OUTTIME on:ap_micTimeOn != 0];
    [self addSliderTo:p y:114 title:@"out.delay" min:0 max:2000 val:ap_micDelay tag:T_OUT_DELAY];
    [self addSliderTo:p y:160 title:@"out.tempo" min:0.5f max:2.0f val:ap_micTempo tag:T_OUT_TEMPO];

    [p addSubview:APLabel(@"[IN] room -> you hear the other side", CGRectMake(14, 218, PW - 20, 14), 10, AP_CYAN, YES)];
    [self addSwitchTo:p y:234 title:@"if (in.time)" tag:S_INTIME on:ap_roomTimeOn != 0];
    [self addSliderTo:p y:270 title:@"in.delay" min:0 max:2000 val:ap_roomDelay tag:T_IN_DELAY];
    [self addSliderTo:p y:316 title:@"in.tempo" min:0.5f max:2.0f val:ap_roomTempo tag:T_IN_TEMPO];

    [self addButtonTo:p frame:CGRectMake(14, 368, 86, 24) title:@"[ reset ]" tag:B_RESET_TIME];
    [self note:@"// link.both : one move changes OUT and IN\n// OUT can reach the peer only if Agora's mic\n// capture passes through AudioUnitRender bus 1.\n// IN changes this device's playback only.\n// BOTH peers need the tweak for symmetric OUT.\n// This is an AudioUnit fallback, not Agora's\n// raw-frame delegate. Verify on a live 2-peer call.\n// delay adds latency; it never lowers ping." y:400 lines:8 page:p];
    return p;
}

- (UIScrollView *)buildSpeed {
    UIScrollView *p = [self newPage:338];
    [p addSubview:APLabel(@"// speed.core  (game clocks of this app)", CGRectMake(14, 4, PW - 20, 16), 10, AP_DIM, NO)];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [self addSwitchTo:p y:20 title:@"if (speed.on)" tag:S_SPEED on:MBSpeedIsEnabled()];
    [self addSliderTo:p y:58 title:@"speed.scale" min:0.1f max:10.0f val:(float)MBSpeedGetScale() tag:T_SPEED];

    double pre[6] = {0.5, 1, 2, 3, 5, 10};
    CGFloat bw = ((PW - 28) - 5 * 6) / 6.0;
    for (int i = 0; i < 6; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(14 + i * (bw + 6), 110, bw, 28);
        b.tag = B_PRESET + i;
        b.layer.cornerRadius = 6; b.layer.borderWidth = 1; b.layer.borderColor = AP_BLUE2.CGColor;
        b.backgroundColor = [UIColor colorWithRed:0.03 green:0.06 blue:0.14 alpha:0.85];
        [b setTitle:[NSString stringWithFormat:@"x%g", pre[i]] forState:UIControlStateNormal];
        [b setTitleColor:AP_CYAN forState:UIControlStateNormal];
        b.titleLabel.font = APFont(10, YES);
        [b addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [p addSubview:b];
    }
    [self addSwitchTo:p y:150 title:@"if (wall.clock)" tag:S_WALL on:MBSpeedGetWallClock()];
    self.speedStats = APLabel(@"", CGRectMake(14, 192, PW - 28, 30), 11, AP_CYAN, YES);
    self.speedStats.numberOfLines = 2;
    [p addSubview:self.speedStats];
    [self note:@"// scales mach_absolute_time, clock_gettime,\n// gettimeofday as the app sees them.\n// works on games that run their logic\n// on the device. server-checked online\n// games ignore it and may flag it." y:232 lines:5 page:p];
    return p;
}

- (UIScrollView *)buildInfo {
    UIScrollView *p = [self newPage:430];
    NSString *txt = [NSString stringWithFormat:
        @"# about\n\n"
        @"author : %s / %s\n"
        @"owner  : exclusive to %s\n"
        @"build  : single standalone dylib\n"
        @"mode   : no jailbreak (ESign)\n"
        @"hooks  : getaddrinfo, socket,\n"
        @"         AudioUnitRender, clocks\n\n"
        @"// dns      : this app only\n"
        @"// Agora : best-effort AudioUnit path\n"
        @"// mic      : assumed capture (bus 1)\n"
        @"// room     : assumed playback (bus 0)\n"
        @"// time     : delay / tempo, both ways\n"
        @"// speed    : game clocks in-process\n"
        @"// net.boost: NOT a VPN\n"
        @"// console  : real counters, not fake",
        AP_CREDIT_EN, AP_CREDIT_AR, AP_OWNER];
    UILabel *l = APLabel(txt, CGRectMake(14, 6, PW - 28, 188), 10, AP_BLUE, NO);
    l.numberOfLines = 0;
    [p addSubview:l];
    [p addSubview:APLabel(@"// profiles.manager  (save / restore all controls)", CGRectMake(14, 204, PW - 28, 16), 9, AP_CYAN, YES)];
    NSArray *profileNames = @[@"GAMING", @"VOICE", @"NORMAL"];
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat y = 228 + i * 42;
        [p addSubview:APLabel(profileNames[i], CGRectMake(14, y + 5, 82, 20), 10, AP_BLUE, YES)];
        UIButton *save = [self addButtonTo:p frame:CGRectMake(105, y, 96, 28) title:@"[ SAVE ]" tag:B_PROFILE_SAVE + i];
        UIButton *load = [self addButtonTo:p frame:CGRectMake(208, y, 110, 28) title:@"[ LOAD ]" tag:B_PROFILE_LOAD + i];
        [save removeTarget:self action:@selector(resetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [load removeTarget:self action:@selector(resetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [save addTarget:self action:@selector(profileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [load addTarget:self action:@selector(profileTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    [self note:@"// Profiles persist locally in this app.\n// OUT affects remote listeners only when the target app captures mic audio through this hook.\n// IN is always local playback processing on this device." y:360 lines:3 page:p];
    return p;
}

#pragma mark apply values

- (void)applyTag:(NSInteger)tag value:(float)v {
    switch (tag) {
        case T_PITCH:     ap_pitch = v; break;
        case T_BASS:      ap_eqBass = v; break;
        case T_MID:       ap_eqMid = v; break;
        case T_TREBLE:    ap_eqTreble = v; break;
        case T_ROOMPITCH: ap_roomSpeed = v; break;
        case T_OUT_DELAY: ap_micDelay = v; break;
        case T_OUT_TEMPO: ap_micTempo = v; break;
        case T_IN_DELAY:  ap_roomDelay = v; break;
        case T_IN_TEMPO:  ap_roomTempo = v; break;
        case T_SPEED:
            MBSpeedSetScale(v);
            [NSUserDefaults.standardUserDefaults setDouble:v forKey:@"am_scale"];
            break;
        default: break;
    }
    ap_settings_save();
}

- (UISlider *)sliderForTag:(NSInteger)tag {
    UIView *v = [self viewWithTag:tag];
    for (UIScrollView *p in self.pages) {
        UIView *c = [p viewWithTag:tag];
        if ([c isKindOfClass:UISlider.class]) return (UISlider *)c;
    }
    return [v isKindOfClass:UISlider.class] ? (UISlider *)v : nil;
}

- (void)setSliderTag:(NSInteger)tag value:(float)v {
    UISlider *s = [self sliderForTag:tag];
    if (!s) return;
    [s setValue:v animated:YES];
    [self applyTag:tag value:s.value];
    UILabel *l = (UILabel *)[s.superview viewWithTag:tag + 100];
    if ([l isKindOfClass:UILabel.class]) [self setValueLabel:l forTag:tag value:s.value];
}

- (NSInteger)partnerOf:(NSInteger)tag {
    switch (tag) {
        case T_OUT_DELAY: return T_IN_DELAY;
        case T_IN_DELAY:  return T_OUT_DELAY;
        case T_OUT_TEMPO: return T_IN_TEMPO;
        case T_IN_TEMPO:  return T_OUT_TEMPO;
        default: return 0;
    }
}

- (void)sliderChanged:(UISlider *)s {
    float v = s.value;
    if (s.tag == T_SPEED) { v = roundf(v * 20.0f) / 20.0f; if (v < 0.1f) v = 0.1f; s.value = v; }
    [self applyTag:s.tag value:v];
    UILabel *l = (UILabel *)[s.superview viewWithTag:s.tag + 100];
    if ([l isKindOfClass:UILabel.class]) [self setValueLabel:l forTag:s.tag value:v];
    if (self.link) {
        NSInteger pt = [self partnerOf:s.tag];
        if (pt) {
            UISlider *ps = [self sliderForTag:pt];
            if (ps) {
                ps.value = v;
                [self applyTag:pt value:v];
                UILabel *pl = (UILabel *)[ps.superview viewWithTag:pt + 100];
                if ([pl isKindOfClass:UILabel.class]) [self setValueLabel:pl forTag:pt value:v];
            }
        }
    }
}

- (void)setSwitchTag:(NSInteger)tag on:(BOOL)on {
    for (UIScrollView *p in self.pages) {
        UIView *c = [p viewWithTag:tag];
        if ([c isKindOfClass:UISwitch.class]) { [(UISwitch *)c setOn:on animated:YES]; return; }
    }
}

- (void)switchChanged:(UISwitch *)s {
    switch (s.tag) {
        case S_DNS:   ap_dnsOn = s.on ? 1 : 0; ap_dns_clear_cache(); [self refreshStatus]; break;
        case S_HUD:   [NSUserDefaults.standardUserDefaults setBool:s.on forKey:@"apv2_hud_on"]; if (self.onHUD) self.onHUD(s.on); break;
        case S_BOOST: ap_netBoostOn = s.on ? 1 : 0; [self refreshStatus]; break;
        case S_PITCH: ap_pitchOn = s.on ? 1 : 0; break;
        case S_EQ:    ap_eqOn = s.on ? 1 : 0; break;
        case S_ROOMPITCH: ap_roomOn = s.on ? 1 : 0; break;
        case S_OUTTIME:
            ap_micTimeOn = s.on ? 1 : 0;
            if (self.link) { ap_roomTimeOn = ap_micTimeOn; [self setSwitchTag:S_INTIME on:s.on]; }
            break;
        case S_INTIME:
            ap_roomTimeOn = s.on ? 1 : 0;
            if (self.link) { ap_micTimeOn = ap_roomTimeOn; [self setSwitchTag:S_OUTTIME on:s.on]; }
            break;
        case S_LINK:
            self.link = s.on;
            [NSUserDefaults.standardUserDefaults setBool:s.on forKey:@"apv2_link_both"];
            if (s.on) {   // copy OUT -> IN so both directions start identical
                [self setSliderTag:T_IN_DELAY value:ap_micDelay];
                [self setSliderTag:T_IN_TEMPO value:ap_micTempo];
                ap_roomTimeOn = ap_micTimeOn;
                [self setSwitchTag:S_INTIME on:ap_micTimeOn != 0];
            }
            break;
        case S_SPEED:
            MBSpeedSetEnabled(s.on);
            [NSUserDefaults.standardUserDefaults setBool:s.on forKey:@"am_speed_on"];
            break;
        case S_WALL:
            MBSpeedSetWallClock(s.on);
            [NSUserDefaults.standardUserDefaults setBool:s.on forKey:@"am_wall"];
            break;
        default: break;
    }
    ap_settings_save();
}

- (void)presetTapped:(UIButton *)b {
    double vals[] = {0.5, 1, 2, 3, 5, 10};
    [self setSliderTag:T_SPEED value:(float)vals[b.tag - B_PRESET]];
    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [h impactOccurred];
}

- (void)resetTapped:(UIButton *)b {
    switch (b.tag) {
        case B_RESET_PITCH: [self setSliderTag:T_PITCH value:1.0f]; break;
        case B_RESET_ROOM:  [self setSliderTag:T_ROOMPITCH value:1.0f]; break;
        case B_RESET_EQ:
            [self setSliderTag:T_BASS value:0]; [self setSliderTag:T_MID value:0]; [self setSliderTag:T_TREBLE value:0];
            break;
        case B_RESET_TIME:
            [self setSliderTag:T_OUT_DELAY value:0]; [self setSliderTag:T_OUT_TEMPO value:1.0f];
            [self setSliderTag:T_IN_DELAY value:0];  [self setSliderTag:T_IN_TEMPO value:1.0f];
            break;
        default: break;
    }
    ap_settings_save();
}

- (void)profileTapped:(UIButton *)button {
    static NSString *names[] = {@"gaming", @"voice", @"normal"};
    NSInteger idx = (button.tag >= B_PROFILE_LOAD) ? button.tag - B_PROFILE_LOAD : button.tag - B_PROFILE_SAVE;
    if (idx < 0 || idx > 2) return;
    NSString *key = [NSString stringWithFormat:@"apv2_profile_%@", names[idx]];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[@"apv2_dns_on", @"apv2_dns_index", @"apv2_net_boost", @"apv2_hud_on", @"apv2_pitch_on", @"apv2_pitch", @"apv2_eq_on", @"apv2_eq_bass", @"apv2_eq_mid", @"apv2_eq_treble", @"apv2_room_on", @"apv2_room_pitch", @"apv2_out_time_on", @"apv2_out_delay", @"apv2_out_tempo", @"apv2_in_time_on", @"apv2_in_delay", @"apv2_in_tempo", @"apv2_speed_on", @"apv2_speed_scale", @"apv2_wall_clock", @"apv2_link_both"];
    if (button.tag < B_PROFILE_LOAD) {
        ap_settings_save();
        NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
        for (NSString *k in keys) { id v = [d objectForKey:k]; if (v) snapshot[k] = v; }
        [d setObject:snapshot forKey:key]; [d synchronize];
        self.status.text = [NSString stringWithFormat:@"> profile %@ saved", [names[idx] uppercaseString]];
    } else {
        NSDictionary *snapshot = [d dictionaryForKey:key];
        if (!snapshot) { self.status.text = @"> profile empty - save it first"; return; }
        [snapshot enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) { [d setObject:v forKey:k]; }];
        self.link = [d boolForKey:@"apv2_link_both"];
        ap_settings_load();
        [self refreshControlsFromState];
        if (self.onHUD) self.onHUD([d boolForKey:@"apv2_hud_on"]);
        [self refreshDNSChips]; [self refreshStatus];
        self.status.text = [NSString stringWithFormat:@"> profile %@ loaded", [names[idx] uppercaseString]];
    }
}

- (void)refreshControlsFromState {
    NSDictionary *switches = @{@(S_DNS):@(ap_dnsOn), @(S_HUD):@([NSUserDefaults.standardUserDefaults boolForKey:@"apv2_hud_on"]), @(S_BOOST):@(ap_netBoostOn), @(S_PITCH):@(ap_pitchOn), @(S_EQ):@(ap_eqOn), @(S_ROOMPITCH):@(ap_roomOn), @(S_OUTTIME):@(ap_micTimeOn), @(S_INTIME):@(ap_roomTimeOn), @(S_SPEED):@(MBSpeedIsEnabled()), @(S_WALL):@(MBSpeedGetWallClock()), @(S_LINK):(self.link ? @YES : @NO)};
    for (UIScrollView *page in self.pages) {
        for (NSNumber *tag in switches) { UISwitch *sw = (UISwitch *)[page viewWithTag:tag.integerValue]; if ([sw isKindOfClass:UISwitch.class]) sw.on = [switches[tag] boolValue]; }
    }
    [self setSliderTag:T_PITCH value:ap_pitch]; [self setSliderTag:T_BASS value:ap_eqBass]; [self setSliderTag:T_MID value:ap_eqMid]; [self setSliderTag:T_TREBLE value:ap_eqTreble];
    [self setSliderTag:T_ROOMPITCH value:ap_roomSpeed]; [self setSliderTag:T_OUT_DELAY value:ap_micDelay]; [self setSliderTag:T_OUT_TEMPO value:ap_micTempo];
    [self setSliderTag:T_IN_DELAY value:ap_roomDelay]; [self setSliderTag:T_IN_TEMPO value:ap_roomTempo]; [self setSliderTag:T_SPEED value:(float)MBSpeedGetScale()];
}

#pragma mark WireGuard profile import (delegates tunnel operation to the official WireGuard app)

- (void)companionVPNTapped:(UIButton *)button {
    NSString *action = (button.tag == B_VPN_CONNECT) ? @"connect" : @"disconnect";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"aflatoonvpn://%@", action]];
    if (!url) return;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.status.text = success ? [NSString stringWithFormat:@"> companion %@ request opened", action] : @"> companion app unavailable / URL scheme not registered";
        });
    }];
}

- (UIViewController *)ap_topViewController {
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

- (void)importWireGuardProfileTapped:(UIButton *)button {
    if (@available(iOS 14.0, *)) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTType.data] asCopy:YES];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        [[self ap_topViewController] presentViewController:picker animated:YES completion:nil];
    } else {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
        picker.delegate = self;
        [[self ap_topViewController] presentViewController:picker animated:YES completion:nil];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *profileURL = urls.firstObject;
    if (!profileURL) return;
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[profileURL] applicationActivities:nil];
    UIPopoverPresentationController *popover = share.popoverPresentationController;
    if (popover) {
        popover.sourceView = self;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 1, 1);
    }
    [[self ap_topViewController] presentViewController:share animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // User cancelled; no profile data was read or changed.
}

#pragma mark dns / status

- (NSInteger)currentDNSIndex {
    for (int i = 0; i < 6; i++) if (strcmp(ap_dnsServer, kDNSIP[i]) == 0) return i;
    return 0;
}

- (void)refreshDNSChips {
    NSInteger cur = [self currentDNSIndex];
    for (UIButton *b in self.dnsChips) {
        BOOL on = (b.tag - B_DNS) == cur;
        b.backgroundColor = on ? AP_BLUE2 : [UIColor colorWithRed:0.05 green:0.08 blue:0.15 alpha:0.9];
        b.layer.borderColor = (on ? AP_CYAN : AP_DIM).CGColor;
        [b setTitleColor:(on ? UIColor.whiteColor : AP_DIM) forState:UIControlStateNormal];
    }
}

- (void)refreshStatus {
    NSInteger cur = [self currentDNSIndex];
    self.status.text = [NSString stringWithFormat:
        @"> resolver : %@ (%s)\n> dns      : %@\n> net.boost: %@",
        kDNSName[cur], ap_dnsServer, ap_dnsOn ? @"ACTIVE" : @"IDLE", ap_netBoostOn ? @"ACTIVE" : @"IDLE"];
}

- (void)dnsChipTapped:(UIButton *)b {
    NSInteger i = b.tag - B_DNS;
    if (i < 0 || i >= 6) return;
    ap_dnsServer = kDNSIP[i];
    ap_dns_clear_cache();
    ap_settings_save();
    [self refreshDNSChips];
    [self refreshStatus];
    ap_settings_save();
}

// the console prints only REAL counters taken from the hooks
- (void)consoleTick {
    if (self.hidden) return;
    unsigned long m = ap_micCalls, r = ap_roomCalls;
    BOOL micLive = m != _lastMic, roomLive = r != _lastRoom;
    _lastMic = m; _lastRoom = r;
    double g = 0, rt = 0;
    MBSpeedStats(&g, &rt);
    self.console.text = [NSString stringWithFormat:
        @"[sys ] AudioUnit fallback | owner %s\n"
        @"[mic ] bus1 pulls %lu  %@ | out.time %@\n"
        @"[room] bus0 pulls %lu  %@ | in.time  %@\n"
        @"[dns ] %lu overrides | last: %s\n"
        @"[time] game %.1fs / real %.1fs | speed %@\n"
        @"[net ] %@",
        AP_OWNER,
        m, micLive ? @"LIVE" : @"idle", ap_micTimeOn ? @"ON" : @"off",
        r, roomLive ? @"LIVE" : @"idle", ap_roomTimeOn ? @"ON" : @"off",
        ap_dnsResolved, ap_dnsLastHost,
        g, rt, MBSpeedIsEnabled() ? [NSString stringWithFormat:@"x%.2f", MBSpeedGetScale()] : @"off", (gNetworkPathLabel ?: @"path: checking")];
    if (self.cur == 4) {
        self.speedStats.text = [NSString stringWithFormat:@"GAME TIME  %.1fs\nREAL TIME  %.1fs", g, rt];
    }
}

#pragma mark tabs

- (void)tabTapped:(UIButton *)b { [self selectTab:b.tag - B_TAB]; }

- (void)selectTab:(NSInteger)i {
    if (i == self.cur || i < 0 || i >= (NSInteger)self.pages.count) return;
    UIView *old = self.pages[self.cur];
    UIView *nu = self.pages[i];
    CGFloat dir = (i > self.cur) ? 26 : -26;
    nu.hidden = NO; nu.alpha = 0;
    nu.transform = CGAffineTransformMakeTranslation(dir, 0);
    NSInteger prev = self.cur;
    self.cur = i;
    const CGFloat tw = PW / 6.0;
    for (UIButton *t in self.tabs)
        [t setTitleColor:((t.tag - B_TAB) == i ? AP_CYAN : AP_DIM) forState:UIControlStateNormal];
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.4 options:0 animations:^{
        nu.alpha = 1;
        nu.transform = CGAffineTransformIdentity;
        old.alpha = 0;
        self.underline.frame = CGRectMake(i * tw + 10, 65, tw - 20, 2);
    } completion:^(BOOL f) {
        if (self.cur != prev) { old.hidden = YES; old.alpha = 1; }
    }];
}

#pragma mark intro / outro

- (void)typeHeader {
    NSString *full = @"aflatoon@secops:~# ./armed --run";
    [self.typeTimer invalidate];
    self.titleLabel.text = @"";
    self.cursor.frame = CGRectMake(58, 8, 10, 18);
    __block NSUInteger n = 0;
    __weak APPanel *ws = self;
    self.typeTimer = [NSTimer scheduledTimerWithTimeInterval:0.04 repeats:YES block:^(NSTimer *t) {
        APPanel *s = ws;
        if (!s) { [t invalidate]; return; }
        n++;
        if (n > full.length) { [t invalidate]; return; }
        s.titleLabel.text = [full substringToIndex:n];
        CGSize sz = [s.titleLabel.text sizeWithAttributes:@{NSFontAttributeName: s.titleLabel.font}];
        s.cursor.frame = CGRectMake(58 + sz.width + 1, 8, 10, 18);
    }];
}

- (void)playIntro {
    self.alpha = 0;
    self.transform = CGAffineTransformMakeScale(0.82, 0.82);
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.9 options:0 animations:^{
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
    [self typeHeader];
    [self.consoleTimer invalidate];
    self.consoleTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(consoleTick) userInfo:nil repeats:YES];
    [self consoleTick];
    UIView *page = self.pages[self.cur];
    page.alpha = 0;
    page.transform = CGAffineTransformMakeTranslation(0, 14);
    [UIView animateWithDuration:0.5 delay:0.12 options:UIViewAnimationOptionCurveEaseOut animations:^{
        page.alpha = 1;
        page.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)closeAnimated {
    [self.typeTimer invalidate];
    [self.consoleTimer invalidate];
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL f) {
        self.hidden = YES;
        self.transform = CGAffineTransformIdentity;
    }];
}

@end

#pragma mark - controller

@interface APController : NSObject
@property (nonatomic, strong) APWindow *win;
@property (nonatomic, strong) APPanel *panel;
@property (nonatomic, strong) UIButton *orb;
@property (nonatomic, strong) UILabel *hud;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSTimer *pingTimer;
+ (instancetype)shared;
- (void)setup;
@end

@implementation APController

+ (instancetype)shared {
    static APController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [APController new]; });
    return c;
}

- (void)setup {
    if (self.win) return;

    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (scene) self.win = [[APWindow alloc] initWithWindowScene:scene];
    else self.win = [[APWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.win.frame = UIScreen.mainScreen.bounds;
    self.win.windowLevel = UIWindowLevelAlert + 100;
    self.win.backgroundColor = UIColor.clearColor;
    self.win.rootViewController = [UIViewController new];
    self.win.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.win.hidden = NO;
    UIView *root = self.win.rootViewController.view;

    self.hud = APLabel(@"RTT --", CGRectMake(12, 56, 104, 22), 11, AP_CYAN, YES);
    self.hud.textAlignment = NSTextAlignmentCenter;
    self.hud.backgroundColor = [UIColor colorWithRed:0.02 green:0.03 blue:0.07 alpha:0.9];
    self.hud.layer.borderColor = AP_BLUE2.CGColor;
    self.hud.layer.borderWidth = 1;
    self.hud.layer.cornerRadius = 6;
    self.hud.layer.masksToBounds = YES;
    self.hud.hidden = ![NSUserDefaults.standardUserDefaults boolForKey:@"apv2_hud_on"];
    [root addSubview:self.hud];

    self.panel = [APPanel new];
    self.panel.hidden = YES;
    __weak APController *ws = self;
    self.panel.onHUD = ^(BOOL on) {
        APController *s = ws;
        if (!s) return;
        s.hud.hidden = !on;
        if (on) [s ping];
    };
    [root addSubview:self.panel];

    self.orb = [UIButton buttonWithType:UIButtonTypeCustom];
    self.orb.frame = CGRectMake(0, 0, 56, 56);
    self.orb.center = CGPointMake(36, 190);
    self.orb.backgroundColor = [UIColor colorWithRed:0.02 green:0.03 blue:0.07 alpha:0.92];
    self.orb.layer.cornerRadius = 28;
    self.orb.layer.borderWidth = 1.5;
    self.orb.layer.borderColor = AP_BLUE2.CGColor;
    self.orb.layer.shadowColor = AP_BLUE.CGColor;
    self.orb.layer.shadowRadius = 10;
    self.orb.layer.shadowOpacity = 0.9;
    self.orb.layer.shadowOffset = CGSizeZero;
    [self.orb setTitle:@"A" forState:UIControlStateNormal];
    [self.orb setTitleColor:AP_CYAN forState:UIControlStateNormal];
    self.orb.titleLabel.font = APFont(22, YES);

    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.frame = self.orb.bounds;
    ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.orb.bounds, 4, 4)].CGPath;
    ring.fillColor = UIColor.clearColor.CGColor;
    ring.strokeColor = AP_BLUE.CGColor;
    ring.lineWidth = 2;
    ring.lineDashPattern = @[@6, @4];
    [self.orb.layer addSublayer:ring];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @0; spin.toValue = @(2 * M_PI); spin.duration = 3.0; spin.repeatCount = HUGE_VALF;
    [ring addAnimation:spin forKey:@"spin"];
    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    glow.fromValue = @0.25; glow.toValue = @1.0; glow.duration = 1.2; glow.autoreverses = YES; glow.repeatCount = HUGE_VALF;
    [self.orb.layer addAnimation:glow forKey:@"glow"];

    [self.orb addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.orb addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(orbPan:)]];
    [root addSubview:self.orb];

    self.orb.alpha = 0;
    self.orb.transform = CGAffineTransformMakeScale(0.2, 0.2);
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:0 animations:^{
        self.orb.alpha = 1;
        self.orb.transform = CGAffineTransformIdentity;
    } completion:nil];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 4;
    self.session = [NSURLSession sessionWithConfiguration:cfg];
    __weak APController *weakSelf = self;
    gPathMonitor = nw_path_monitor_create();
    nw_path_monitor_set_update_handler(gPathMonitor, ^(nw_path_t path) {
        BOOL ok = (nw_path_get_status(path) == nw_path_status_satisfied);
        NSString *iface = nw_path_uses_interface_type(path, nw_interface_type_wifi) ? @"Wi-Fi" :
                          (nw_path_uses_interface_type(path, nw_interface_type_cellular) ? @"cellular" :
                          (nw_path_uses_interface_type(path, nw_interface_type_wired) ? @"ethernet" : @"other"));
        NSString *label = [NSString stringWithFormat:@"path: %@ / %@", ok ? @"online" : @"offline", iface];
        dispatch_async(dispatch_get_main_queue(), ^{      // write the shared string on the main thread only
            gNetworkPathLabel = label;
            [weakSelf.panel consoleTick];
        });
    });
    nw_path_monitor_set_queue(gPathMonitor, dispatch_queue_create("com.aflatoon.network-monitor", DISPATCH_QUEUE_SERIAL));
    nw_path_monitor_start(gPathMonitor);
    self.pingTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(ping) userInfo:nil repeats:YES];
}

- (void)togglePanel {
    if (self.panel.hidden) {
        UIView *root = self.win.rootViewController.view;
        self.panel.center = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
        self.panel.hidden = NO;
        [self.panel playIntro];
    } else {
        [self.panel closeAnimated];
    }
}

- (void)orbPan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    UIView *sv = v.superview;
    CGPoint t = [g translationInView:sv];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:sv];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGFloat w = sv.bounds.size.width, h = sv.bounds.size.height;
        CGFloat x = (v.center.x < w / 2) ? 36 : (w - 36);
        CGFloat y = MIN(MAX(v.center.y, 70), h - 70);
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8 options:0 animations:^{
            v.center = CGPointMake(x, y);
        } completion:nil];
    }
}

- (void)ping {
    if (self.hud.hidden) return;
    NSURL *u = [NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]; // HTTP round-trip, not ICMP/game-server ping
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u
                                                     cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                                 timeoutInterval:4];
    r.HTTPMethod = @"HEAD";
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    __weak APController *ws = self;
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        double ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            APController *s = ws;
            if (!s) return;
            if (e) { s.hud.text = @"PING --"; s.hud.textColor = AP_DIM; }
            else {
                s.hud.text = [NSString stringWithFormat:@"PING %.0fms", ms];
                s.hud.textColor = (ms < 80) ? AP_CYAN : (ms < 180 ? AP_BLUE : UIColor.whiteColor);
            }
        });
    }] resume];
}

@end

void ap_ui_start(void) {
    [[APController shared] setup];
}

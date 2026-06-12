#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

static float gBrightness = 0.08f;
static float gContrast = 1.10f;
static float gSaturation = 1.12f;
static float gGamma = 0.92f;
static float gLightIntensity = 0.18f;
static float gVignette = 0.0f;
static BOOL gEnabled = YES;
static BOOL gMirror = NO;
static BOOL gDidInstall = NO;
static CIContext *gCIContext;
static UIWindow *gOverlayWindow;

static NSString *kSuite = @"VCAMEnhancer";

static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

static void loadPrefs(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:@"vce_enabled"]) gEnabled = [ud boolForKey:@"vce_enabled"];
    if ([ud objectForKey:@"vce_mirror"]) gMirror = [ud boolForKey:@"vce_mirror"];
    if ([ud objectForKey:@"vce_brightness"]) gBrightness = [ud floatForKey:@"vce_brightness"];
    if ([ud objectForKey:@"vce_contrast"]) gContrast = [ud floatForKey:@"vce_contrast"];
    if ([ud objectForKey:@"vce_saturation"]) gSaturation = [ud floatForKey:@"vce_saturation"];
    if ([ud objectForKey:@"vce_gamma"]) gGamma = [ud floatForKey:@"vce_gamma"];
    if ([ud objectForKey:@"vce_light"]) gLightIntensity = [ud floatForKey:@"vce_light"];
    if ([ud objectForKey:@"vce_vignette"]) gVignette = [ud floatForKey:@"vce_vignette"];
}

static void savePref(NSString *key, float val) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setFloat:val forKey:key];
    [ud synchronize];
}
static void saveBool(NSString *key, BOOL val) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:val forKey:key];
    [ud synchronize];
}

static CVPixelBufferRef processPixelBuffer(CVPixelBufferRef src) {
    if (!src || !gEnabled) return src;
    if (!gCIContext) gCIContext = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace:[NSNull null]}];
    CIImage *img = [CIImage imageWithCVPixelBuffer:src];
    if (!img) return src;

    if (gMirror) {
        CGRect e = img.extent;
        img = [[img imageByApplyingTransform:CGAffineTransformMakeScale(-1, 1)] imageByApplyingTransform:CGAffineTransformMakeTranslation(e.size.width, 0)];
    }

    CIFilter *cc = [CIFilter filterWithName:@"CIColorControls"];
    [cc setValue:img forKey:kCIInputImageKey];
    [cc setValue:@(gBrightness) forKey:kCIInputBrightnessKey];
    [cc setValue:@(gContrast) forKey:kCIInputContrastKey];
    [cc setValue:@(gSaturation) forKey:kCIInputSaturationKey];
    img = cc.outputImage ?: img;

    CIFilter *gamma = [CIFilter filterWithName:@"CIGammaAdjust"];
    [gamma setValue:img forKey:kCIInputImageKey];
    [gamma setValue:@(clampf(gGamma, 0.2f, 3.0f)) forKey:@"inputPower"];
    img = gamma.outputImage ?: img;

    if (gLightIntensity > 0.001f) {
        CGRect e = img.extent;
        CIVector *center = [CIVector vectorWithX:CGRectGetMidX(e) Y:CGRectGetMidY(e)];
        CIFilter *grad = [CIFilter filterWithName:@"CIRadialGradient"];
        [grad setValue:center forKey:@"inputCenter"];
        [grad setValue:@(MIN(e.size.width, e.size.height) * 0.05) forKey:@"inputRadius0"];
        [grad setValue:@(MAX(e.size.width, e.size.height) * 0.62) forKey:@"inputRadius1"];
        [grad setValue:[CIColor colorWithRed:1 green:0.92 blue:0.82 alpha:clampf(gLightIntensity,0,1)] forKey:@"inputColor0"];
        [grad setValue:[CIColor colorWithRed:0 green:0 blue:0 alpha:0] forKey:@"inputColor1"];
        CIImage *light = [grad.outputImage imageByCroppingToRect:e];
        CIFilter *blend = [CIFilter filterWithName:@"CISoftLightBlendMode"];
        [blend setValue:light forKey:kCIInputImageKey];
        [blend setValue:img forKey:kCIInputBackgroundImageKey];
        img = blend.outputImage ?: img;
    }

    if (gVignette > 0.001f) {
        CIFilter *v = [CIFilter filterWithName:@"CIVignette"];
        [v setValue:img forKey:kCIInputImageKey];
        [v setValue:@(gVignette) forKey:@"inputIntensity"];
        [v setValue:@(1.2) forKey:@"inputRadius"];
        img = v.outputImage ?: img;
    }

    CVPixelBufferRef out = NULL;
    size_t w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src);
    OSType fmt = CVPixelBufferGetPixelFormatType(src);
    NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey:@{}};
    CVReturn r = CVPixelBufferCreate(kCFAllocatorDefault, w, h, fmt, (__bridge CFDictionaryRef)attrs, &out);
    if (r != kCVReturnSuccess || !out) return src;
    [gCIContext render:img toCVPixelBuffer:out bounds:CGRectMake(0,0,w,h) colorSpace:NULL];
    return out;
}

static CMSampleBufferRef copyProcessedSampleBuffer(CMSampleBufferRef sbuf) {
    if (!sbuf || !CMSampleBufferIsValid(sbuf)) return sbuf;
    CVImageBufferRef ibuf = CMSampleBufferGetImageBuffer(sbuf);
    if (!ibuf) return sbuf;
    CVPixelBufferRef p = processPixelBuffer((CVPixelBufferRef)ibuf);
    if (!p || p == ibuf) return sbuf;

    CMVideoFormatDescriptionRef fmt = NULL;
    CMSampleTimingInfo timing;
    CMSampleBufferGetSampleTimingInfo(sbuf, 0, &timing);
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, p, &fmt) != noErr || !fmt) {
        CVPixelBufferRelease(p);
        return sbuf;
    }
    CMSampleBufferRef out = NULL;
    OSStatus st = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, p, true, NULL, NULL, fmt, &timing, &out);
    CFRelease(fmt);
    CVPixelBufferRelease(p);
    return (st == noErr && out) ? out : sbuf;
}

static id callObjC(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(obj, sel);
}

// Hook common frame-returning methods in known VCAM packages.
typedef CMSampleBufferRef (*FrameImp)(id, SEL, CMSampleBufferRef);
static FrameImp orig_getVideoFrame, orig_getLiveStreamFrame, orig_getPhotoFrame, orig_getAudioFrame;
static CMSampleBufferRef hook_frame1(id self, SEL _cmd, CMSampleBufferRef arg) {
    FrameImp orig = NULL;
    const char *name = sel_getName(_cmd);
    if (strcmp(name,"getVideoFrame:")==0) orig = orig_getVideoFrame;
    else if (strcmp(name,"getLiveStreamFrame:")==0) orig = orig_getLiveStreamFrame;
    else if (strcmp(name,"getPhotoFrame:")==0) orig = orig_getPhotoFrame;
    else if (strcmp(name,"getAudioFrame:")==0) orig = orig_getAudioFrame;
    CMSampleBufferRef sb = orig ? orig(self,_cmd,arg) : arg;
    return copyProcessedSampleBuffer(sb);
}

typedef CMSampleBufferRef (*DecoderImp)(id,SEL,CMSampleBufferRef);
static DecoderImp orig_decodeNextFrame;
static CMSampleBufferRef hook_decodeNextFrame(id self, SEL _cmd, CMSampleBufferRef arg) {
    CMSampleBufferRef sb = orig_decodeNextFrame ? orig_decodeNextFrame(self,_cmd,arg) : arg;
    return copyProcessedSampleBuffer(sb);
}

typedef CMSampleBufferRef (*GetCurImp)(id,SEL,CMSampleBufferRef,BOOL);
static GetCurImp orig_getCurrentFrameForce;
static CMSampleBufferRef hook_getCurrentFrameForce(id self, SEL _cmd, CMSampleBufferRef arg, BOOL force) {
    CMSampleBufferRef sb = orig_getCurrentFrameForce ? orig_getCurrentFrameForce(self,_cmd,arg,force) : arg;
    return copyProcessedSampleBuffer(sb);
}

static void hookMethod(Class cls, SEL sel, IMP newImp, IMP *orig) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, newImp);
    NSLog(@"[VCAMEnhancer] hooked %@ %@", cls, NSStringFromSelector(sel));
}

static UISlider *slider(UIView *parent, NSString *title, float min, float max, float val, void(^change)(float)) {
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
    lab.text = [NSString stringWithFormat:@"%@ %.2f", title, val]; lab.textColor = UIColor.whiteColor; lab.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectZero]; s.minimumValue=min; s.maximumValue=max; s.value=val;
    [s addAction:[UIAction actionWithHandler:^(__kindof UIAction *a){ UISlider *sl=(UISlider*)a.sender; lab.text=[NSString stringWithFormat:@"%@ %.2f", title, sl.value]; change(sl.value); }] forControlEvents:UIControlEventValueChanged];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[lab,s]]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=8; [lab.widthAnchor constraintEqualToConstant:100].active=YES;
    [(UIStackView*)parent addArrangedSubview:row];
    return s;
}

static void showPanel(void) {
    loadPrefs();
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) { if (w != gOverlayWindow && !w.hidden) { win = w; break; } }
    if (!win) win = UIApplication.sharedApplication.windows.firstObject;
    if (!win) return;
    UIViewController *root = win.rootViewController;
    if (!root) { for (UIWindow *w in UIApplication.sharedApplication.windows) { if (w != gOverlayWindow && w.rootViewController) { root = w.rootViewController; break; } } }
    while (root.presentedViewController) root = root.presentedViewController;
    NSLog(@"[VCAMEnhancer] showPanel root=%@ win=%@", root, win);
    if (!root) return;
    UIViewController *vc = [UIViewController new]; vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    UIView *bg = [[UIView alloc] initWithFrame:CGRectZero]; bg.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.72]; bg.layer.cornerRadius=18; bg.translatesAutoresizingMaskIntoConstraints=NO; [vc.view addSubview:bg];
    UIStackView *st = [[UIStackView alloc] initWithFrame:CGRectZero]; st.axis=UILayoutConstraintAxisVertical; st.spacing=10; st.translatesAutoresizingMaskIntoConstraints=NO; [bg addSubview:st];
    UILabel *title=[UILabel new]; title.text=@"VCAM Enhancer"; title.textColor=UIColor.whiteColor; title.font=[UIFont boldSystemFontOfSize:20]; [st addArrangedSubview:title];
    UISwitch *en=[UISwitch new]; en.on=gEnabled; UILabel *enl=[UILabel new]; enl.text=@"启用处理"; enl.textColor=UIColor.whiteColor; UIStackView *er=[[UIStackView alloc] initWithArrangedSubviews:@[enl,en]]; er.axis=UILayoutConstraintAxisHorizontal; er.distribution=UIStackViewDistributionEqualSpacing; [st addArrangedSubview:er]; [en addAction:[UIAction actionWithHandler:^(__kindof UIAction *a){gEnabled=((UISwitch*)a.sender).on; saveBool(@"vce_enabled",gEnabled);} ] forControlEvents:UIControlEventValueChanged];
    UISwitch *mi=[UISwitch new]; mi.on=gMirror; UILabel *mil=[UILabel new]; mil.text=@"镜像"; mil.textColor=UIColor.whiteColor; UIStackView *mr=[[UIStackView alloc] initWithArrangedSubviews:@[mil,mi]]; mr.axis=UILayoutConstraintAxisHorizontal; mr.distribution=UIStackViewDistributionEqualSpacing; [st addArrangedSubview:mr]; [mi addAction:[UIAction actionWithHandler:^(__kindof UIAction *a){gMirror=((UISwitch*)a.sender).on; saveBool(@"vce_mirror",gMirror);} ] forControlEvents:UIControlEventValueChanged];
    slider(st,@"亮度",-0.5,0.5,gBrightness,^(float v){gBrightness=v;savePref(@"vce_brightness",v);});
    slider(st,@"对比",0.2,2.5,gContrast,^(float v){gContrast=v;savePref(@"vce_contrast",v);});
    slider(st,@"饱和",0.0,2.5,gSaturation,^(float v){gSaturation=v;savePref(@"vce_saturation",v);});
    slider(st,@"Gamma",0.3,2.5,gGamma,^(float v){gGamma=v;savePref(@"vce_gamma",v);});
    slider(st,@"打光",0.0,0.8,gLightIntensity,^(float v){gLightIntensity=v;savePref(@"vce_light",v);});
    slider(st,@"暗角",0.0,2.0,gVignette,^(float v){gVignette=v;savePref(@"vce_vignette",v);});
    UIButton *reset=[UIButton buttonWithType:UIButtonTypeSystem]; [reset setTitle:@"重置" forState:UIControlStateNormal]; [reset addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){gBrightness=0.08;gContrast=1.10;gSaturation=1.12;gGamma=0.92;gLightIntensity=0.18;gVignette=0; savePref(@"vce_brightness",gBrightness); savePref(@"vce_contrast",gContrast); savePref(@"vce_saturation",gSaturation); savePref(@"vce_gamma",gGamma); savePref(@"vce_light",gLightIntensity); savePref(@"vce_vignette",gVignette); [vc dismissViewControllerAnimated:YES completion:nil];}] forControlEvents:UIControlEventTouchUpInside]; [st addArrangedSubview:reset];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem]; [close setTitle:@"关闭" forState:UIControlStateNormal]; [close addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){[vc dismissViewControllerAnimated:YES completion:nil];}] forControlEvents:UIControlEventTouchUpInside]; [st addArrangedSubview:close];
    [NSLayoutConstraint activateConstraints:@[[bg.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],[bg.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],[bg.widthAnchor constraintEqualToConstant:330],[st.topAnchor constraintEqualToAnchor:bg.topAnchor constant:18],[st.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor constant:-18],[st.leftAnchor constraintEqualToAnchor:bg.leftAnchor constant:18],[st.rightAnchor constraintEqualToAnchor:bg.rightAnchor constant:-18]]];
    [root presentViewController:vc animated:YES completion:nil];
}

@interface VCEButtonHandler : NSObject
+ (instancetype)shared;
- (void)tap:(id)sender;
@end
@implementation VCEButtonHandler
+ (instancetype)shared { static VCEButtonHandler *h; static dispatch_once_t once; dispatch_once(&once, ^{ h=[VCEButtonHandler new]; }); return h; }
- (void)tap:(id)sender { NSLog(@"[VCAMEnhancer] button tapped"); showPanel(); }
@end

@interface VCEPanHandler : NSObject
+ (instancetype)shared;
- (void)handlePan:(UIPanGestureRecognizer *)p;
@end
@implementation VCEPanHandler
+ (instancetype)shared { static VCEPanHandler *h; static dispatch_once_t once; dispatch_once(&once, ^{ h=[VCEPanHandler new]; }); return h; }
- (void)handlePan:(UIPanGestureRecognizer *)p { UIWindow *w = gOverlayWindow; CGPoint t=[p translationInView:w.superview ?: w]; w.center=CGPointMake(w.center.x+t.x, w.center.y+t.y); [p setTranslation:CGPointZero inView:w.superview ?: w]; }
@end

static void installUIButton(void) {
    if (gOverlayWindow && !gOverlayWindow.hidden) return;
    CGRect frame = CGRectMake(60, 360, 62, 62);
    gOverlayWindow = [[UIWindow alloc] initWithFrame:frame];
    gOverlayWindow.windowLevel = UIWindowLevelAlert + 2000;
    gOverlayWindow.backgroundColor = UIColor.clearColor;
    gOverlayWindow.hidden = NO;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    gOverlayWindow.rootViewController = vc;

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 62, 62);
    b.layer.cornerRadius = 31;
    b.backgroundColor = [[UIColor purpleColor] colorWithAlphaComponent:0.85];
    [b setTitle:@"调" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:26];
    [b addTarget:[VCEButtonHandler shared] action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[VCEPanHandler shared] action:@selector(handlePan:)];
    [b addGestureRecognizer:pan];
    [vc.view addSubview:b];
    [gOverlayWindow makeKeyAndVisible];
    NSLog(@"[VCAMEnhancer] overlay button installed");
}

static void tryInstall(void) {
    if (gDidInstall) { installUIButton(); return; }
    loadPrefs();
    // Original 15MB VCAM
    Class media = NSClassFromString(@"MediaManager");
    hookMethod(media, NSSelectorFromString(@"getVideoFrame:"), (IMP)hook_frame1, (IMP*)&orig_getVideoFrame);
    hookMethod(media, NSSelectorFromString(@"getLiveStreamFrame:"), (IMP)hook_frame1, (IMP*)&orig_getLiveStreamFrame);
    hookMethod(media, NSSelectorFromString(@"getPhotoFrame:"), (IMP)hook_frame1, (IMP*)&orig_getPhotoFrame);
    // Jerryhook / push injection
    Class rtmp = NSClassFromString(@"RTMPDecoder");
    hookMethod(rtmp, NSSelectorFromString(@"decodeNextFrameWithOriginSampleBuffer:"), (IMP)hook_decodeNextFrame, (IMP*)&orig_decodeNextFrame);
    Class local = NSClassFromString(@"JRLocalDecoder");
    hookMethod(local, NSSelectorFromString(@"getCurrentFrame:forceReNew:"), (IMP)hook_getCurrentFrameForce, (IMP*)&orig_getCurrentFrameForce);
    gDidInstall = YES;
    installUIButton();
    NSLog(@"[VCAMEnhancer] installed enabled=%d", gEnabled);
}

__attribute__((constructor)) static void entry(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ tryInstall(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ tryInstall(); });
    }
}

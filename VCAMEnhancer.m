#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

static float gBrightness = 0.08f;
static float gContrast = 1.10f;
static float gSaturation = 1.12f;
static float gGamma = 0.92f;
static float gLightIntensity = 0.18f;
static float gLightFeather = 0.62f;
static float gLightX = 0.0f;
static float gLightY = 0.0f;
static float gLightR = 1.0f;
static float gLightG = 0.92f;
static float gLightB = 0.82f;
static float gColorTemp = 0.0f;
static float gVignette = 0.0f;
static float gSharpness = 0.25f;
static float gDenoise = 0.02f;
static float gScale = 1.0f;
static float gOffsetX = 0.0f;
static float gOffsetY = 0.0f;
static NSInteger gRotateMode = 0;
static BOOL gEnabled = YES;
static BOOL gMirror = NO;
static BOOL gLightEnabled = YES;
static BOOL gDisco = NO;
static NSInteger gLightEffect = 0; // 0 manual, 1 rainbow, 2 breathe, 3 flash
static float gDiscoSpeed = 0.08f;
static BOOL gDidInstall = NO;
static CIContext *gCIContext;
static UIWindow *gOverlayWindow;
static UIWindow *gPanelWindow;
static NSInteger gActiveTab = 3;

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
    if ([ud objectForKey:@"vce_light_enabled"]) gLightEnabled = [ud boolForKey:@"vce_light_enabled"];
    if ([ud objectForKey:@"vce_feather"]) gLightFeather = [ud floatForKey:@"vce_feather"];
    if ([ud objectForKey:@"vce_light_x"]) gLightX = [ud floatForKey:@"vce_light_x"];
    if ([ud objectForKey:@"vce_light_y"]) gLightY = [ud floatForKey:@"vce_light_y"];
    if ([ud objectForKey:@"vce_light_r"]) gLightR = [ud floatForKey:@"vce_light_r"];
    if ([ud objectForKey:@"vce_light_g"]) gLightG = [ud floatForKey:@"vce_light_g"];
    if ([ud objectForKey:@"vce_light_b"]) gLightB = [ud floatForKey:@"vce_light_b"];
    if ([ud objectForKey:@"vce_temp"]) gColorTemp = [ud floatForKey:@"vce_temp"];
    if ([ud objectForKey:@"vce_vignette"]) gVignette = [ud floatForKey:@"vce_vignette"];
    if ([ud objectForKey:@"vce_sharpness"]) gSharpness = [ud floatForKey:@"vce_sharpness"];
    if ([ud objectForKey:@"vce_denoise"]) gDenoise = [ud floatForKey:@"vce_denoise"];
    if ([ud objectForKey:@"vce_scale"]) gScale = [ud floatForKey:@"vce_scale"];
    if ([ud objectForKey:@"vce_offset_x"]) gOffsetX = [ud floatForKey:@"vce_offset_x"];
    if ([ud objectForKey:@"vce_offset_y"]) gOffsetY = [ud floatForKey:@"vce_offset_y"];
    if ([ud objectForKey:@"vce_rotate"]) gRotateMode = [ud integerForKey:@"vce_rotate"];
    if ([ud objectForKey:@"vce_disco"]) gDisco = [ud boolForKey:@"vce_disco"];
    if ([ud objectForKey:@"vce_effect"]) gLightEffect = [ud integerForKey:@"vce_effect"];
    if ([ud objectForKey:@"vce_disco_speed"]) gDiscoSpeed = [ud floatForKey:@"vce_disco_speed"];
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
static void savePanelFrame(CGRect frame) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setFloat:frame.origin.x forKey:@"vce_panel_x"];
    [ud setFloat:frame.origin.y forKey:@"vce_panel_y"];
    [ud synchronize];
}

static void hsvToRGB(float h, float s, float v, float *r, float *g, float *b) {
    float c = v * s;
    float x = c * (1 - fabsf(fmodf(h * 6.0f, 2.0f) - 1));
    float m = v - c;
    float rr=0,gg=0,bb=0;
    int i = (int)floorf(h * 6.0f) % 6;
    if (i==0) {rr=c;gg=x;bb=0;} else if(i==1){rr=x;gg=c;bb=0;} else if(i==2){rr=0;gg=c;bb=x;} else if(i==3){rr=0;gg=x;bb=c;} else if(i==4){rr=x;gg=0;bb=c;} else {rr=c;gg=0;bb=x;}
    *r=rr+m; *g=gg+m; *b=bb+m;
}

static CVPixelBufferRef processPixelBuffer(CVPixelBufferRef src) {
    if (!src || !gEnabled) return src;
    if (!gCIContext) gCIContext = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace:[NSNull null]}];
    CIImage *img = [CIImage imageWithCVPixelBuffer:src];
    if (!img) return src;

    CGRect baseExtent = img.extent;
    //画面：缩放/平移/镜像/旋转，模拟截图里的“画面”页
    CGAffineTransform t = CGAffineTransformIdentity;
    if (gMirror) t = CGAffineTransformScale(t, -1, 1);
    CGFloat sc = clampf(gScale, 0.5f, 2.0f);
    t = CGAffineTransformTranslate(t, baseExtent.size.width * 0.5 + gOffsetX * baseExtent.size.width, baseExtent.size.height * 0.5 + gOffsetY * baseExtent.size.height);
    t = CGAffineTransformScale(t, sc, sc);
    if (gRotateMode == 1) t = CGAffineTransformRotate(t, M_PI_2);
    else if (gRotateMode == 2) t = CGAffineTransformRotate(t, M_PI);
    else if (gRotateMode == 3) t = CGAffineTransformRotate(t, -M_PI_2);
    t = CGAffineTransformTranslate(t, -baseExtent.size.width * 0.5, -baseExtent.size.height * 0.5);
    img = [img imageByApplyingTransform:t];
    img = [img imageByCroppingToRect:baseExtent];

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

    if (fabs(gColorTemp) > 0.001f) {
        CIFilter *temp = [CIFilter filterWithName:@"CITemperatureAndTint"];
        [temp setValue:img forKey:kCIInputImageKey];
        CGFloat kelvin = 6500 + gColorTemp * 3500;
        [temp setValue:[CIVector vectorWithX:kelvin Y:0] forKey:@"inputNeutral"];
        [temp setValue:[CIVector vectorWithX:6500 Y:0] forKey:@"inputTargetNeutral"];
        img = temp.outputImage ?: img;
    }

    if (gLightEnabled && gLightIntensity > 0.001f) {
        CGRect e = img.extent;
        CIVector *center = [CIVector vectorWithX:CGRectGetMidX(e) + gLightX * e.size.width * 0.45 Y:CGRectGetMidY(e) - gLightY * e.size.height * 0.45];
        CIFilter *grad = [CIFilter filterWithName:@"CIRadialGradient"];
        [grad setValue:center forKey:@"inputCenter"];
        [grad setValue:@(MIN(e.size.width, e.size.height) * 0.03) forKey:@"inputRadius0"];
        [grad setValue:@(MAX(e.size.width, e.size.height) * clampf(gLightFeather,0.15f,1.2f)) forKey:@"inputRadius1"];
        float lr = gLightR, lg = gLightG, lb = gLightB;
        float alpha = clampf(gLightIntensity,0,1);
        if (gDisco || gLightEffect > 0) {
            NSTimeInterval tm = [NSDate.date timeIntervalSince1970];
            float speed = clampf(gDiscoSpeed,0.01f,2.0f);
            if (gLightEffect == 2) { // breathe
                alpha *= (0.35f + 0.65f * (0.5f + 0.5f * sinf((float)tm * speed * 6.28318f)));
            } else if (gLightEffect == 3) { // flash
                alpha *= (fmodf((float)tm * speed * 6.0f, 1.0f) > 0.5f) ? 1.0f : 0.15f;
            } else { // rainbow/manual disco
                float h = fmodf((float)tm * speed, 1.0f);
                hsvToRGB(h, 1.0f, 1.0f, &lr, &lg, &lb);
            }
        }
        [grad setValue:[CIColor colorWithRed:clampf(lr,0,1) green:clampf(lg,0,1) blue:clampf(lb,0,1) alpha:alpha] forKey:@"inputColor0"];
        [grad setValue:[CIColor colorWithRed:0 green:0 blue:0 alpha:0] forKey:@"inputColor1"];
        CIImage *light = [grad.outputImage imageByCroppingToRect:e];
        CIFilter *blend = [CIFilter filterWithName:@"CISoftLightBlendMode"];
        [blend setValue:light forKey:kCIInputImageKey];
        [blend setValue:img forKey:kCIInputBackgroundImageKey];
        img = blend.outputImage ?: img;
    }

    if (gDenoise > 0.001f) {
        CIFilter *noise = [CIFilter filterWithName:@"CINoiseReduction"];
        [noise setValue:img forKey:kCIInputImageKey];
        [noise setValue:@(clampf(gDenoise,0,0.2)) forKey:@"inputNoiseLevel"];
        [noise setValue:@(0.35) forKey:@"inputSharpness"];
        img = noise.outputImage ?: img;
    }

    if (gSharpness > 0.001f) {
        CIFilter *sharp = [CIFilter filterWithName:@"CISharpenLuminance"];
        [sharp setValue:img forKey:kCIInputImageKey];
        [sharp setValue:@(clampf(gSharpness,0,1.2)) forKey:@"inputSharpness"];
        img = sharp.outputImage ?: img;
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

// Generic AVCaptureVideoDataOutput delegate proxy: catches final camera sample buffers.
@interface VCEDelegateProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, weak) id target;
@end
@implementation VCEDelegateProxy
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CMSampleBufferRef processed = copyProcessedSampleBuffer(sampleBuffer);
    id t = self.target;
    SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
    if (t && [t respondsToSelector:sel]) {
        ((void(*)(id,SEL,id,CMSampleBufferRef,id))objc_msgSend)(t, sel, output, processed, connection);
    }
    if (processed && processed != sampleBuffer) CFRelease(processed);
}
- (BOOL)respondsToSelector:(SEL)aSelector {
    if (aSelector == @selector(captureOutput:didOutputSampleBuffer:fromConnection:)) return YES;
    return [self.target respondsToSelector:aSelector] || [super respondsToSelector:aSelector];
}
- (id)forwardingTargetForSelector:(SEL)aSelector { return self.target; }
@end

static NSMutableArray *gDelegateProxies;
static void (*orig_setSampleBufferDelegate)(id,SEL,id,dispatch_queue_t);
static void hook_setSampleBufferDelegate(id self, SEL _cmd, id delegate, dispatch_queue_t queue) {
    if (!gDelegateProxies) gDelegateProxies = [NSMutableArray new];
    if (delegate) {
        VCEDelegateProxy *proxy = [VCEDelegateProxy new];
        proxy.target = delegate;
        [gDelegateProxies addObject:proxy];
        NSLog(@"[VCAMEnhancer] delegate proxied %@ -> %@", delegate, proxy);
        orig_setSampleBufferDelegate(self,_cmd,proxy,queue);
    } else {
        orig_setSampleBufferDelegate(self,_cmd,nil,queue);
    }
}

static BOOL hookMethod(Class cls, SEL sel, IMP newImp, IMP *orig) {
    if (!cls) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, newImp);
    NSLog(@"[VCAMEnhancer] hooked -[%@ %@]", cls, NSStringFromSelector(sel));
    return YES;
}

static BOOL hookClassMethod(Class cls, SEL sel, IMP newImp, IMP *orig) {
    if (!cls) return NO;
    Method m = class_getClassMethod(cls, sel);
    if (!m) return NO;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, newImp);
    NSLog(@"[VCAMEnhancer] hooked +[%@ %@]", cls, NSStringFromSelector(sel));
    return YES;
}

static UISegmentedControl *segmented(UIView *parent, NSString *title, NSArray<NSString*> *items, NSInteger selected, void(^change)(NSInteger)) {
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
    lab.text = title; lab.textColor = UIColor.whiteColor; lab.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:items]; seg.selectedSegmentIndex = selected;
    [seg addAction:[UIAction actionWithHandler:^(__kindof UIAction *a){ change(((UISegmentedControl*)a.sender).selectedSegmentIndex); }] forControlEvents:UIControlEventValueChanged];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[lab,seg]]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=8; [lab.widthAnchor constraintEqualToConstant:80].active=YES;
    [(UIStackView*)parent addArrangedSubview:row]; return seg;
}

static UIButton *smallBtn(NSString *title, void(^tap)(void)) {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:title forState:UIControlStateNormal]; b.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.12]; b.layer.cornerRadius=8; [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a){ tap(); }] forControlEvents:UIControlEventTouchUpInside]; return b;
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

@interface VCEPanHandler : NSObject
+ (instancetype)shared;
- (void)handlePan:(UIPanGestureRecognizer *)p;
- (void)handlePanelPan:(UIPanGestureRecognizer *)p;
@end

@interface VCEBGTapHandler : NSObject
+ (instancetype)shared;
- (void)tapBG:(id)sender;
@end

static UIColor *vcePanelBG(void) { return [[UIColor blackColor] colorWithAlphaComponent:0.78]; }
static UILabel *miniLabel(NSString *text, CGFloat size, UIFontWeight weight) { UILabel *l=[UILabel new]; l.text=text; l.textColor=UIColor.whiteColor; l.font=[UIFont systemFontOfSize:size weight:weight]; return l; }
static UIButton *tabButton(NSString *title, NSInteger idx) { UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; b.tag=idx; [b setTitle:title forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; b.titleLabel.font=[UIFont boldSystemFontOfSize:15]; b.layer.cornerRadius=8; b.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.12]; return b; }
static UIButton *miniBtn(NSString *title, void(^tap)(void)) { UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:title forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; b.titleLabel.font=[UIFont boldSystemFontOfSize:14]; b.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.14]; b.layer.cornerRadius=8; [b.heightAnchor constraintEqualToConstant:34].active=YES; [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a){ tap(); }] forControlEvents:UIControlEventTouchUpInside]; return b; }
static UISlider *miniSlider(UIView *parent, NSString *title, float min, float max, float val, void(^change)(float)) {
    UILabel *lab=miniLabel(title,14,UIFontWeightSemibold); UILabel *valLab=miniLabel([NSString stringWithFormat:@"%.2f",val],12,UIFontWeightBold); valLab.textAlignment=NSTextAlignmentRight;
    UIButton *minus=miniBtn(@"-", ^{}); UIButton *plus=miniBtn(@"+", ^{});
    UISlider *s=[UISlider new]; s.minimumValue=min; s.maximumValue=max; s.value=val;
    void (^apply)(float)=^(float v){ v=clampf(v,min,max); s.value=v; valLab.text=[NSString stringWithFormat:@"%.2f",v]; change(v); };
    [minus removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents]; [plus removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [minus addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){ apply(s.value-(max-min)/20.0); }] forControlEvents:UIControlEventTouchUpInside];
    [plus addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){ apply(s.value+(max-min)/20.0); }] forControlEvents:UIControlEventTouchUpInside];
    [s addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){ UISlider *sl=(UISlider*)a.sender; valLab.text=[NSString stringWithFormat:@"%.2f",sl.value]; change(sl.value); }] forControlEvents:UIControlEventValueChanged];
    UIStackView *row=[UIStackView new]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=6; row.alignment=UIStackViewAlignmentCenter;
    [lab.widthAnchor constraintEqualToConstant:52].active=YES; [minus.widthAnchor constraintEqualToConstant:30].active=YES; [plus.widthAnchor constraintEqualToConstant:30].active=YES; [valLab.widthAnchor constraintEqualToConstant:38].active=YES;
    [row addArrangedSubview:lab]; [row addArrangedSubview:minus]; [row addArrangedSubview:s]; [row addArrangedSubview:plus]; [row addArrangedSubview:valLab];
    [(UIStackView*)parent addArrangedSubview:row]; return s;
}
static UIStackView *basePage(UIView *page) { UIScrollView *sc=[UIScrollView new]; sc.translatesAutoresizingMaskIntoConstraints=NO; sc.showsVerticalScrollIndicator=NO; sc.alwaysBounceVertical=YES; [page addSubview:sc]; [NSLayoutConstraint activateConstraints:@[[sc.topAnchor constraintEqualToAnchor:page.topAnchor],[sc.leftAnchor constraintEqualToAnchor:page.leftAnchor],[sc.rightAnchor constraintEqualToAnchor:page.rightAnchor],[sc.bottomAnchor constraintEqualToAnchor:page.bottomAnchor]]]; UIStackView *st=[UIStackView new]; st.translatesAutoresizingMaskIntoConstraints=NO; st.axis=UILayoutConstraintAxisVertical; st.spacing=8; [sc addSubview:st]; [NSLayoutConstraint activateConstraints:@[[st.topAnchor constraintEqualToAnchor:sc.contentLayoutGuide.topAnchor],[st.leadingAnchor constraintEqualToAnchor:sc.frameLayoutGuide.leadingAnchor],[st.trailingAnchor constraintEqualToAnchor:sc.frameLayoutGuide.trailingAnchor],[st.bottomAnchor constraintEqualToAnchor:sc.contentLayoutGuide.bottomAnchor],[st.widthAnchor constraintEqualToAnchor:sc.frameLayoutGuide.widthAnchor]]]; return st; }

static void showPanel(void) {
    loadPrefs();
    if (gPanelWindow && !gPanelWindow.hidden) { gPanelWindow.hidden=YES; gPanelWindow=nil; return; }
    CGRect screen = UIScreen.mainScreen.bounds;
    CGFloat pw=316; CGFloat ph=MIN(screen.size.height - 60.0, 520.0);
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat savedX = [ud objectForKey:@"vce_panel_x"] ? [ud floatForKey:@"vce_panel_x"] : (screen.size.width-pw)/2.0;
    CGFloat savedY = [ud objectForKey:@"vce_panel_y"] ? [ud floatForKey:@"vce_panel_y"] : (screen.size.height-ph)*0.58;
    savedX = MAX(4, MIN(savedX, screen.size.width - pw - 4));
    savedY = MAX(20, MIN(savedY, screen.size.height - ph - 20));
    gPanelWindow = [[UIWindow alloc] initWithFrame:CGRectMake(savedX, savedY, pw, ph)];
    gPanelWindow.windowLevel = UIWindowLevelAlert + 1999;
    gPanelWindow.backgroundColor = UIColor.clearColor;
    UIViewController *vc=[UIViewController new]; vc.view.backgroundColor=UIColor.clearColor; gPanelWindow.rootViewController=vc;

    UIView *panel=[UIView new]; panel.frame=CGRectMake(0,0,pw,ph); panel.backgroundColor=vcePanelBG(); panel.layer.cornerRadius=18; panel.layer.masksToBounds=YES; [vc.view addSubview:panel];
    UILabel *title=miniLabel(@"✏️ 编辑",20,UIFontWeightBold); title.frame=CGRectMake(14,12,180,30); title.userInteractionEnabled=YES; [panel addSubview:title];
    UIPanGestureRecognizer *panelPan=[[UIPanGestureRecognizer alloc] initWithTarget:[VCEPanHandler shared] action:@selector(handlePanelPan:)];
    [panel addGestureRecognizer:panelPan];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeCustom]; close.frame=CGRectMake(pw-56,8,46,46); close.layer.cornerRadius=23; close.backgroundColor=[UIColor colorWithRed:0.86 green:0.12 blue:0.12 alpha:0.95]; [close setTitle:@"×" forState:UIControlStateNormal]; close.titleLabel.font=[UIFont systemFontOfSize:30 weight:UIFontWeightLight]; [close addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){gPanelWindow.hidden=YES; gPanelWindow=nil;}] forControlEvents:UIControlEventTouchUpInside]; [panel addSubview:close];

    UIStackView *tabs=[UIStackView new]; tabs.frame=CGRectMake(12,64,pw-24,42); tabs.axis=UILayoutConstraintAxisHorizontal; tabs.spacing=6; tabs.distribution=UIStackViewDistributionFillEqually; [panel addSubview:tabs];
    NSArray *names=@[@"媒体",@"画面",@"色彩",@"打光"]; NSMutableArray *btns=[NSMutableArray new]; NSMutableArray *pages=[NSMutableArray new];
    UIView *content=[[UIView alloc] initWithFrame:CGRectMake(14,118,pw-28,ph-132)]; [panel addSubview:content];
    void (^selectTab)(NSInteger)=^(NSInteger idx){ gActiveTab=idx; for(int i=0;i<pages.count;i++){((UIView*)pages[i]).hidden=(i!=idx);} for(int i=0;i<btns.count;i++){UIButton*b=btns[i]; b.backgroundColor=(i==idx)?[UIColor colorWithRed:0.06 green:0.38 blue:0.88 alpha:1]:[[UIColor whiteColor] colorWithAlphaComponent:0.12];} };
    for(int i=0;i<4;i++){ UIButton *b=tabButton(names[i],i); [b addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){selectTab(((UIButton*)a.sender).tag);}] forControlEvents:UIControlEventTouchUpInside]; [tabs addArrangedSubview:b]; [btns addObject:b]; UIView *pg=[[UIView alloc] initWithFrame:content.bounds]; pg.hidden=YES; [content addSubview:pg]; [pages addObject:pg]; }

    UILabel *media=miniLabel(@"媒体用原版 VCAM：\n选择图片 / 选择视频 / 删除 / 暂停 / 循环 / 直播流。",15,UIFontWeightSemibold); media.numberOfLines=0; media.frame=CGRectMake(8,10,content.bounds.size.width-16,100); [pages[0] addSubview:media];

    UIStackView *screenSt=basePage(pages[1]);
    miniSlider(screenSt,@"缩放",0.5,2.0,gScale,^(float v){gScale=v;savePref(@"vce_scale",v);});
    miniSlider(screenSt,@"水平",-1.0,1.0,gOffsetX,^(float v){gOffsetX=v;savePref(@"vce_offset_x",v);});
    miniSlider(screenSt,@"垂直",-1.0,1.0,gOffsetY,^(float v){gOffsetY=v;savePref(@"vce_offset_y",v);});
    UIStackView *rot=[UIStackView new]; rot.axis=UILayoutConstraintAxisHorizontal; rot.spacing=6; rot.distribution=UIStackViewDistributionFillEqually; [rot addArrangedSubview:miniBtn(@"左转",^{gRotateMode=3;[[NSUserDefaults standardUserDefaults] setInteger:gRotateMode forKey:@"vce_rotate"];})]; [rot addArrangedSubview:miniBtn(@"右转",^{gRotateMode=1;[[NSUserDefaults standardUserDefaults] setInteger:gRotateMode forKey:@"vce_rotate"];})]; [rot addArrangedSubview:miniBtn(@"镜像",^{gMirror=!gMirror;saveBool(@"vce_mirror",gMirror);})]; [rot addArrangedSubview:miniBtn(@"重置",^{gScale=1;gOffsetX=0;gOffsetY=0;gRotateMode=0;savePref(@"vce_scale",1);savePref(@"vce_offset_x",0);savePref(@"vce_offset_y",0);[[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"vce_rotate"];})]; [screenSt addArrangedSubview:rot];
    UILabel *fill=miniLabel(@"背景填充色",13,UIFontWeightSemibold); [screenSt addArrangedSubview:fill]; UIStackView *colors=[UIStackView new]; colors.axis=UILayoutConstraintAxisHorizontal; colors.spacing=5; colors.distribution=UIStackViewDistributionFillEqually; NSArray *cs=@[UIColor.blackColor,UIColor.whiteColor,UIColor.darkGrayColor,UIColor.lightGrayColor,UIColor.blueColor,UIColor.greenColor,UIColor.redColor,[UIColor colorWithRed:0.12 green:0.08 blue:0.05 alpha:1]]; for(UIColor*c in cs){UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; b.backgroundColor=c; b.layer.cornerRadius=5; [b.heightAnchor constraintEqualToConstant:28].active=YES; [colors addArrangedSubview:b];} [screenSt addArrangedSubview:colors];

    UIStackView *colorSt=basePage(pages[2]);
    miniSlider(colorSt,@"亮度",-0.5,0.5,gBrightness,^(float v){gBrightness=v;savePref(@"vce_brightness",v);});
    miniSlider(colorSt,@"对比",0.2,2.5,gContrast,^(float v){gContrast=v;savePref(@"vce_contrast",v);});
    miniSlider(colorSt,@"饱和",0.0,2.5,gSaturation,^(float v){gSaturation=v;savePref(@"vce_saturation",v);});
    miniSlider(colorSt,@"Gamma",0.3,2.5,gGamma,^(float v){gGamma=v;savePref(@"vce_gamma",v);});
    miniSlider(colorSt,@"色温",-1.0,1.0,gColorTemp,^(float v){gColorTemp=v;savePref(@"vce_temp",v);});
    miniSlider(colorSt,@"锐化",0.0,1.2,gSharpness,^(float v){gSharpness=v;savePref(@"vce_sharpness",v);});
    miniSlider(colorSt,@"降噪",0.0,0.2,gDenoise,^(float v){gDenoise=v;savePref(@"vce_denoise",v);});
    UIButton *resetColor=miniBtn(@"↻ 重置色彩",^{gBrightness=0.08;gContrast=1.10;gSaturation=1.12;gGamma=0.92;gColorTemp=0;gSharpness=0.25;gDenoise=0.02;savePref(@"vce_brightness",gBrightness);savePref(@"vce_contrast",gContrast);savePref(@"vce_saturation",gSaturation);savePref(@"vce_gamma",gGamma);savePref(@"vce_temp",0);savePref(@"vce_sharpness",gSharpness);savePref(@"vce_denoise",gDenoise);}); [colorSt addArrangedSubview:resetColor];

    UIStackView *lightSt=basePage(pages[3]);
    UISwitch *le=[UISwitch new]; le.on=gLightEnabled; UILabel*lel=miniLabel(@"💡 启用脸部打光",15,UIFontWeightBold); UIStackView*lr=[[UIStackView alloc]initWithArrangedSubviews:@[lel,le]]; lr.axis=UILayoutConstraintAxisHorizontal; lr.distribution=UIStackViewDistributionEqualSpacing; [lightSt addArrangedSubview:lr]; [le addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){gLightEnabled=((UISwitch*)a.sender).on;saveBool(@"vce_light_enabled",gLightEnabled);}] forControlEvents:UIControlEventValueChanged];
    UISwitch *di=[UISwitch new]; di.on=gDisco; UILabel*dil=miniLabel(@"🌈 彩虹循环",15,UIFontWeightBold); UIStackView*dr=[[UIStackView alloc]initWithArrangedSubviews:@[dil,di]]; dr.axis=UILayoutConstraintAxisHorizontal; dr.distribution=UIStackViewDistributionEqualSpacing; [lightSt addArrangedSubview:dr]; [di addAction:[UIAction actionWithHandler:^(__kindof UIAction*a){gDisco=((UISwitch*)a.sender).on;gLightEffect=gDisco?1:0;saveBool(@"vce_disco",gDisco);[[NSUserDefaults standardUserDefaults] setInteger:gLightEffect forKey:@"vce_effect"];}] forControlEvents:UIControlEventValueChanged];
    UIButton *resetLight=miniBtn(@"↻ 重置灯光",^{
        gLightEnabled = YES;
        gDisco = NO;
        gLightEffect = 0;
        gLightIntensity = 0.18f;
        gLightFeather = 0.62f;
        gLightX = 0.0f;
        gLightY = 0.0f;
        gLightR = 1.0f;
        gLightG = 0.92f;
        gLightB = 0.82f;
        gDiscoSpeed = 0.08f;
        le.on = gLightEnabled;
        di.on = gDisco;
        saveBool(@"vce_light_enabled",gLightEnabled);
        saveBool(@"vce_disco",gDisco);
        [[NSUserDefaults standardUserDefaults] setInteger:gLightEffect forKey:@"vce_effect"];
        savePref(@"vce_light",gLightIntensity);
        savePref(@"vce_feather",gLightFeather);
        savePref(@"vce_light_x",gLightX);
        savePref(@"vce_light_y",gLightY);
        savePref(@"vce_light_r",gLightR);
        savePref(@"vce_light_g",gLightG);
        savePref(@"vce_light_b",gLightB);
        savePref(@"vce_disco_speed",gDiscoSpeed);
    });
    [lightSt addArrangedSubview:resetLight];
    UIStackView *preset=[UIStackView new]; preset.axis=UILayoutConstraintAxisHorizontal; preset.spacing=5; preset.distribution=UIStackViewDistributionFillEqually;
    NSArray *presetData=@[@[@"白",@1,@1,@1],@[@"暖",@1,@0.75,@0.45],@[@"冷",@0.55,@0.75,@1],@[@"红",@1,@0.05,@0.05],@[@"绿",@0.05,@1,@0.1],@[@"蓝",@0.05,@0.2,@1],@[@"紫",@0.75,@0.05,@1]];
    for(NSArray *pd in presetData){ NSString *tt=pd[0]; float rr=[pd[1] floatValue],gg=[pd[2] floatValue],bb=[pd[3] floatValue]; [preset addArrangedSubview:miniBtn(tt,^{gLightR=rr;gLightG=gg;gLightB=bb;gDisco=NO;gLightEffect=0;savePref(@"vce_light_r",rr);savePref(@"vce_light_g",gg);savePref(@"vce_light_b",bb);saveBool(@"vce_disco",NO);[[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"vce_effect"] ;})]; } [lightSt addArrangedSubview:preset];
    UIStackView *effects=[UIStackView new]; effects.axis=UILayoutConstraintAxisHorizontal; effects.spacing=5; effects.distribution=UIStackViewDistributionFillEqually;
    [effects addArrangedSubview:miniBtn(@"手动",^{gDisco=NO;gLightEffect=0;saveBool(@"vce_disco",NO);[[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"vce_effect"] ;})];
    [effects addArrangedSubview:miniBtn(@"彩虹",^{gDisco=YES;gLightEffect=1;saveBool(@"vce_disco",YES);[[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"vce_effect"] ;})];
    [effects addArrangedSubview:miniBtn(@"呼吸",^{gDisco=NO;gLightEffect=2;saveBool(@"vce_disco",NO);[[NSUserDefaults standardUserDefaults] setInteger:2 forKey:@"vce_effect"] ;})];
    [effects addArrangedSubview:miniBtn(@"闪烁",^{gDisco=NO;gLightEffect=3;saveBool(@"vce_disco",NO);[[NSUserDefaults standardUserDefaults] setInteger:3 forKey:@"vce_effect"] ;})];
    [lightSt addArrangedSubview:effects];
    miniSlider(lightSt,@"强度",0.0,1.0,gLightIntensity,^(float v){gLightIntensity=v;savePref(@"vce_light",v);});
    miniSlider(lightSt,@"羽化",0.15,1.2,gLightFeather,^(float v){gLightFeather=v;savePref(@"vce_feather",v);});
    miniSlider(lightSt,@"速度",0.01,2.0,gDiscoSpeed,^(float v){gDiscoSpeed=v;savePref(@"vce_disco_speed",v);});
    UIStackView *dir=[UIStackView new]; dir.axis=UILayoutConstraintAxisHorizontal; dir.spacing=5; dir.distribution=UIStackViewDistributionFillEqually; NSArray *dn=@[@"前",@"顶",@"底",@"左",@"右"]; for(int i=0;i<dn.count;i++){ NSInteger idx=i; [dir addArrangedSubview:miniBtn(dn[i],^{ if(idx==0){gLightX=0;gLightY=0;} if(idx==1){gLightX=0;gLightY=-1;} if(idx==2){gLightX=0;gLightY=1;} if(idx==3){gLightX=-1;gLightY=0;} if(idx==4){gLightX=1;gLightY=0;} savePref(@"vce_light_x",gLightX);savePref(@"vce_light_y",gLightY);})]; } [lightSt addArrangedSubview:dir];

    selectTab(gActiveTab);
    [gPanelWindow makeKeyAndVisible];
}
@implementation VCEBGTapHandler
+ (instancetype)shared { static VCEBGTapHandler *h; static dispatch_once_t once; dispatch_once(&once, ^{ h=[VCEBGTapHandler new]; }); return h; }
- (void)tapBG:(id)sender { UIResponder *r = [sender view].nextResponder; while (r && ![r isKindOfClass:UIViewController.class]) r = [r nextResponder]; UIViewController *vc = (UIViewController *)r; if (vc) [vc dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface VCEButtonHandler : NSObject
+ (instancetype)shared;
- (void)tap:(id)sender;
@end
@implementation VCEButtonHandler
+ (instancetype)shared { static VCEButtonHandler *h; static dispatch_once_t once; dispatch_once(&once, ^{ h=[VCEButtonHandler new]; }); return h; }
- (void)tap:(id)sender { NSLog(@"[VCAMEnhancer] button tapped"); showPanel(); }
@end

@implementation VCEPanHandler
+ (instancetype)shared { static VCEPanHandler *h; static dispatch_once_t once; dispatch_once(&once, ^{ h=[VCEPanHandler new]; }); return h; }
- (void)handlePan:(UIPanGestureRecognizer *)p { UIWindow *w = gOverlayWindow; CGPoint t=[p translationInView:w.superview ?: w]; w.center=CGPointMake(w.center.x+t.x, w.center.y+t.y); [p setTranslation:CGPointZero inView:w.superview ?: w]; }
- (void)handlePanelPan:(UIPanGestureRecognizer *)p { UIWindow *w = gPanelWindow; if(!w) return; CGPoint t=[p translationInView:w.superview ?: w]; CGRect f=w.frame; f.origin.x += t.x; f.origin.y += t.y; CGRect s=UIScreen.mainScreen.bounds; f.origin.x=MAX(4,MIN(f.origin.x,s.size.width-f.size.width-4)); f.origin.y=MAX(20,MIN(f.origin.y,s.size.height-f.size.height-20)); w.frame=f; [p setTranslation:CGPointZero inView:w.superview ?: w]; if(p.state==UIGestureRecognizerStateEnded||p.state==UIGestureRecognizerStateCancelled) savePanelFrame(f); }
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
    // Global camera sample-buffer delegate hook: catches most AVCapture outputs.
    hookMethod(NSClassFromString(@"AVCaptureVideoDataOutput"), NSSelectorFromString(@"setSampleBufferDelegate:queue:"), (IMP)hook_setSampleBufferDelegate, (IMP*)&orig_setSampleBufferDelegate);

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

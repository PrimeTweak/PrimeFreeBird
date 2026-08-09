//
//  WebReply.x
//  PrimeFreeBird
//
//  Opens replies in an authenticated web composer instead of the native one and
//  captures the posted reply's ID from the webview. Gated on `reply_in_webview`.
//

#import "HookHelpers.h"
#import <QuartzCore/QuartzCore.h>

// MARK: - Reply webview helpers

static TFNTwitterStatus* statusFromObject(id object) {
    if (!object) {
        return nil;
    }

    if ([object isKindOfClass:%c(TFNTwitterStatus)]) {
        return (TFNTwitterStatus*)object;
    }

    @try {
        id tweet = [object valueForKey:@"tweet"];
        if ([tweet isKindOfClass:%c(TFNTwitterStatus)]) {
            return (TFNTwitterStatus*)tweet;
        }
    } @catch (__unused NSException* exception) {
    }

    @
    try {
        id status = [object valueForKey:@"status"];
        if ([status isKindOfClass:%c(TFNTwitterStatus)]) {
            return (TFNTwitterStatus*)status;
        }
    } @catch (__unused NSException* exception) {
    }

    return nil;
}

// Injected into the reply webview: hooks fetch/XHR to capture the new post's ID from
// the web CreateTweet response, since there's no native completion callback to read.
static NSString* const ReplyCaptureScript =
    @"(function(){"
     "if(window.__bhtReplyHook)return;window.__bhtReplyHook=true;"
     "var save=function(j){try{if(j&&j.data){"
     "var "
     "r=(j.data.create_tweet&&j.data.create_tweet.tweet_results&&j.data.create_tweet.tweet_results."
     "result)||"
     "(j.data.notetweet_create&&j.data.notetweet_create.tweet_results&&j.data.notetweet_create."
     "tweet_results.result);"
     "if(r&&r.rest_id)sessionStorage.setItem('__bhtNewReply',String(r.rest_id));}}catch(e){}};"
     "var isCreate=function(u){return typeof u==='string'&&u.indexOf('CreateTweet')!==-1;};"
     "var of=window.fetch;"
     "if(of){window.fetch=function(){var a=arguments;var u=(a[0]&&a[0].url)||a[0];"
     "return "
     "of.apply(this,a).then(function(res){try{if(isCreate(u))res.clone().json().then(save).catch("
     "function(){});}catch(e){}return res;});};}"
     "var oo=XMLHttpRequest.prototype.open;var os=XMLHttpRequest.prototype.send;"
     "XMLHttpRequest.prototype.open=function(m,u){this.__bhtURL=u;return "
     "oo.apply(this,arguments);};"
     "XMLHttpRequest.prototype.send=function(){var x=this;try{if(isCreate(x.__bhtURL)){"
     "x.addEventListener('load',function(){try{save(JSON.parse(x.responseText));}catch(e){}});}}"
     "catch(e){}return os.apply(this,arguments);};"
     "})();";

// Reads and clears the reply ID stashed by the capture script.
static NSString* const ReplyReadScript =
    @"(function(){var "
    @"v=sessionStorage.getItem('__bhtNewReply')||'';sessionStorage.removeItem('__bhtNewReply');"
    @"return v;})();";

// Injected on the reply page: hide only x.com's app-install / sign-in promo banners and the web
// back arrow. We deliberately do NOT touch x.com's compose toolbar or layout anymore — x.com
// keeps its toolbar above the keyboard by itself (exactly like the real x.com mobile web), and
// fighting it with our own CSS is what caused every positioning bug.
static NSString* const ReplyStyleScript =
    @"(function(){var css='"
    @"[data-testid=\"app-promo-banner\"],div[role=\"dialog\"] a[href*=\"apple.com\"],"
    @"div[role=\"dialog\"] a[href*=\"google.com\"],iframe[src*=\"google\"],.twitter-app-banner"
    @"{display:none !important;}"
    @"[data-testid=\"app-bar-back\"],[aria-label=\"Back\"]{display:none !important;}"
    @"';"
    @"var s=document.getElementById('nfb-reply-style')||document.createElement('style');"
    @"s.id='nfb-reply-style';s.innerHTML=css;"
    @"if(!s.parentNode){(document.head||document.documentElement).appendChild(s);}})();";

// Injected on the reply page: poll for the compose box (it renders async) and report it ready
// (nfbReady → reveal). It does NOT focus anymore: focus is issued natively AFTER the icon bar is
// built, so the keyboard's very first presentation already includes the bar — one keyboard event,
// one layout, no late bounce.
static NSString* const ReplyFocusScript =
    @"(function(){var n=0;"
    @"function box(){return document.querySelector('div[role=\"textbox\"]')"
    @"||document.querySelector('textarea');}"
    @"function go(){var b=box();if(b){"
    @"try{window.webkit.messageHandlers.nfbReady.postMessage(1);}catch(e){}"
    @"return;}"
    @"if(n++<40){setTimeout(go,150);}}go();})();";

// Injected on the reply page: a real TAP outside the compose box or toolbar blurs the
// field (dismisses the keyboard). We track finger movement so a scroll/drag does NOT
// dismiss — otherwise starting a scroll would close the keyboard and make things jump.
static NSString* const ReplyTapDismissScript =
    @"(function(){if(window.__nfbTapBlur)return;window.__nfbTapBlur=1;"
    @"var sx=0,sy=0,mv=false;"
    @"document.addEventListener('pointerdown',function(e){sx=e.clientX;sy=e.clientY;mv=false;},true);"
    @"document.addEventListener('pointermove',function(e){"
    @"if(Math.abs(e.clientX-sx)>10||Math.abs(e.clientY-sy)>10){mv=true;}},true);"
    @"document.addEventListener('pointerup',function(e){if(mv)return;"
    @"var b=document.querySelector('div[role=\"textbox\"]');"
    @"var t=document.querySelector('[data-testid=\"toolBar\"]');"
    @"if(b&&!b.contains(e.target)&&!(t&&t.contains(e.target))){"
    @"var a=document.activeElement;if(a&&a.blur){a.blur();}}},true);})();";

// Injected on the reply page. The web view is FULL HEIGHT and never resized, with NO manual
// insets — WKWebView's own keyboard inset and focused-field reveal do the heavy lifting. Native
// code only forwards keyboard events: window.__nfbKb(up, keyboardOverlap). THE SIMPLE CONTRACT
// (François's spec): the reply box stays IN FLOW with the tweet — never docked, never restyled.
// Keyboard UP → clear any Show-more pin, then vfix(): a WIDTH-SAFE vertical collapse of the field
// (min-height:0 + height:auto everywhere; flex-grow:0 ONLY on column-direction parents so a row's
// width flex is never touched (killing a row's flex blanks the field); plus a
// max-height cap on the field if still tall). This removes the ~700px x.com reserves under the
// focused field, which was pushing the tweet far above the composer. Then place() runs
// IMMEDIATELY — trim + geometry report + scroll aligning the field's bottom just above the
// keyboard — and re-asserts at +60/+250ms. The re-asserts are idempotent no-ops once geometry is
// settled (trim: trail already <=24; nfbGeo: excess already <=8; scrollTo: same target), so they
// can never fight or vibrate. place() runs immediately, not deferred: a deferred-only pass
// leaves WebKit's instant, un-animated placement (see CALayer hook) visible until it runs.
// Keyboard DOWN (Show more) →
// unchanged, confirmed-good: content fits → composer in flow under the tweet; overflows → pinned
// to the screen bottom.
static NSString* const ReplyBarPinScript =
    @"(function(){if(window.__nfbKbInit)return;window.__nfbKbInit=1;window.__nfbColl=[];"
    @"function findBox(){"
    @"var c=document.querySelector('div[role=\"textbox\"]')||document.querySelector('textarea');"
    @"var t=document.querySelector('[data-testid=\"toolBar\"]');if(!t||!c)return null;"
    @"var box=t,s=0;while(box&&!box.contains(c)&&s<6){box=box.parentElement;s++;}"
    @"if(!box||!box.contains(c)||box===document.body)return null;return box;}"
    @"function clr(box){box.style.position='';box.style.left='';box.style.right='';"
    @"box.style.bottom='';box.style.zIndex='';box.style.background='';box.style.paddingBottom='';"
    @"document.body.style.paddingBottom='';document.body.style.paddingTop='';"
    @"document.body.style.marginBottom='';"
    @"for(var i=0;i<window.__nfbColl.length;i++){var e=window.__nfbColl[i];"
    @"e.style.removeProperty('min-height');e.style.removeProperty('height');"
    @"e.style.removeProperty('flex-grow');e.style.removeProperty('max-height');"
    @"e.style.removeProperty('overflow-y');e.style.removeProperty('overflow');"
    @"e.style.removeProperty('padding-bottom');}"
    @"window.__nfbColl=[];}"
    @"function vfix(box){"
    @"var c=document.querySelector('div[role=\"textbox\"]')||document.querySelector('textarea');"
    @"if(!c)return;var list=[c];"
    @"var ds=c.querySelectorAll('*');for(var i=0;i<ds.length;i++){list.push(ds[i]);}"
    @"var e=c.parentElement,k=0;while(e&&k<10){list.push(e);if(e===box)break;e=e.parentElement;k++;}"
    @"var lim=Math.max(96,Math.round(window.innerHeight*0.14));"
    @"for(var j=0;j<list.length;j++){var el=list[j];"
    @"el.style.setProperty('min-height','0','important');"
    @"el.style.setProperty('height','auto','important');"
    @"try{var pc=getComputedStyle(el.parentElement);"
    @"if(pc.display.indexOf('flex')>=0&&pc.flexDirection.indexOf('column')>=0){"
    @"if((parseFloat(getComputedStyle(el).flexGrow)||0)>0){"
    @"el.style.setProperty('flex-grow','0','important');}}}catch(x){}"
    @"window.__nfbColl.push(el);}}"
    @"function killspacers(){"
    @"var tb=document.querySelector('div[role=\"textbox\"]')||document.querySelector('textarea');"
    @"var all=document.body.getElementsByTagName('div');"
    @"for(var i=0;i<all.length;i++){var el=all[i];"
    @"if(tb&&el.contains(tb))continue;"
    @"if(el.offsetHeight<120)continue;"
    @"if((el.textContent||'').trim().length>0)continue;"
    @"if(el.querySelector('img,svg,video,canvas'))continue;"
    @"el.style.setProperty('min-height','0','important');"
    @"el.style.setProperty('max-height','0','important');"
    @"el.style.setProperty('height','0','important');"
    @"el.style.setProperty('flex-grow','0','important');"
    @"window.__nfbColl.push(el);}}"
    @"function apply(up,kb){var box=findBox();if(!box)return;"
    @"if(up){clr(box);vfix(box);killspacers();"
    @"var place=function(){"
    @"var c=document.querySelector('div[role=\"textbox\"]')||document.querySelector('textarea');"
    @"if(!c)return;var bx=findBox()||c;"
    @"var bb=bx.getBoundingClientRect().bottom+(window.pageYOffset||0);"
    @"var sh=Math.max(document.body.scrollHeight,document.documentElement.scrollHeight);"
    @"var trail=sh-bb;"
    @"if(trail>24){document.body.style.marginBottom=(-(trail-16))+'px';}"
    @"try{window.webkit.messageHandlers.nfbGeo.postMessage(bb);}catch(e){}"
    @"var r=c.getBoundingClientRect();var vis=window.innerHeight-kb;"
    @"var ny=(window.pageYOffset||0)+(r.bottom-(vis-6));if(ny<0){ny=0;}"
    @"try{window.scrollTo(0,ny);}catch(e){}"
    @"};place();setTimeout(place,60);setTimeout(place,250);}"
    @"else{clr(box);var H=window.innerHeight;"
    @"var sh=Math.max(document.body.scrollHeight,document.documentElement.scrollHeight);"
    @"if(sh>H+4){box.style.position='fixed';box.style.left='0';box.style.right='0';"
    @"box.style.bottom='0';box.style.background='Canvas';box.style.zIndex='2147483647';"
    @"box.style.paddingBottom='env(safe-area-inset-bottom, 0px)';"
    @"document.body.style.paddingBottom='calc('+box.offsetHeight+'px + env(safe-area-inset-bottom, 0px))';}}}"
    @"window.__nfbKb=function(up,kb){"
    @"if(up){apply(1,kb||0);}"
    @"else{var b=findBox();"
    @"if(b&&b.style.position==='fixed'){b.style.bottom='0';}"
    @"setTimeout(function(){apply(0,0);},120);setTimeout(function(){apply(0,0);},450);}};})();";

// YES only while our reply web view is on screen, so the keyboard swizzle below never forces
// the keyboard for any other web view in the app.
static BOOL gBHTReplyWebViewActive = NO;

// One-shot: set right before we issue the programmatic focus() (after the icon bar is built),
// consumed by the WKContentView swizzle to raise the keyboard for that focus only. Any later
// focus (e.g. x.com re-focusing after a dismiss) is NOT forced, so a user dismiss sticks.
static BOOL gNFBForceNextFocus = NO;
// Guards the focus request so the icons path and the fallback timer can't both fire it.
static BOOL gNFBDidRequestFocus = NO;
// Last keyboard overlap seen, to drop duplicate keyboard notifications.
static CGFloat gNFBLastKbOverlap = 0;

static __weak UIScrollView* gNFBReplyScroller = nil;   // identity for the CALayer hook
// The reveal is a CABasicAnimation on the scroll view layer's bounds.origin
// (from {0,-173} to {0,0}, 0.25s). During the keyboard-up window we drop exactly
// that animation when WebKit tries to add it; the counter records that it fired.
static int gNFBAnimsKilled = 0;
static CFTimeInterval gNFBSquelchUntil = 0;   // drop bounds.origin animations before this time

// ---------------------------------------------------------------------------
// NATIVE compose icon bar. x.com's real WEB toolbar can't be glued to the
// keyboard (whole saga above). Instead we extract x.com's REAL toolbar SVG icons
// and show them in a small WKWebView that IS the keyboard's inputAccessoryView —
// WebKit renders the SVGs live (no snapshot), and taps relay to x.com's hidden
// real buttons. Auto-shown when the keyboard is up, gone on "Show more".
static WKWebView* gNFBIconBar = nil;           // the icon-bar web view = the accessory
static __weak WKWebView* gNFBRelayWebView = nil;

// Extract each toolbar button's SVG + colour + its index, post to native, then
// hide x.com's own toolbar (display:none — no layout space, so the composer stays
// compact; a dispatched click still fires x.com's React handlers even hidden).
static NSString* const ReplyIconExtractScript =
    @"(function(){var tries=0;function go(){"
    @"var tb=document.querySelector('[data-testid=\"toolBar\"]');"
    @"if(!tb){if(tries++<15){setTimeout(go,300);}return;}"
    @"var bs=tb.querySelectorAll('button,[role=\"button\"]');var out=[];"
    @"for(var i=0;i<bs.length;i++){var s=bs[i].querySelector('svg');if(!s)continue;"
    @"var col='rgb(29,155,240)';try{col=getComputedStyle(s).color||col;}catch(e){}"
    @"out.push({h:s.outerHTML,c:col,oi:i});}"
    @"if(!out.length){if(tries++<15){setTimeout(go,300);}return;}"
    @"try{window.webkit.messageHandlers.nfbIcons.postMessage(JSON.stringify(out));}catch(e){}"
    @"tb.style.setProperty('display','none','important');}go();})();";

// The icon bar posts the tapped toolbar index; we relay a bubbling click onto
// x.com's hidden toolbar button (React catches it even when display:none).
@interface NFBIconRelay : NSObject <WKScriptMessageHandler>
+ (instancetype)shared;
@end
@implementation NFBIconRelay
+ (instancetype)shared {
    static NFBIconRelay* s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NFBIconRelay new]; });
    return s;
}
- (void)userContentController:(WKUserContentController*)ucc
      didReceiveScriptMessage:(WKScriptMessage*)msg {
    if (![msg.name isEqualToString:@"nfbTap"]) { return; }
    NSInteger oi = [msg.body integerValue];
    NSString* js = [NSString stringWithFormat:
        @"(function(){var tb=document.querySelector('[data-testid=\"toolBar\"]');if(!tb)return;"
        @"var bs=tb.querySelectorAll('button,[role=\"button\"]');if(bs[%ld]){"
        @"bs[%ld].dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,view:window}));"
        @"}})();", (long)oi, (long)oi];
    [gNFBRelayWebView evaluateJavaScript:js completionHandler:nil];
}
@end

// Find the current first responder so we can reload its input accessory.
static UIView* NFBFindFirstResponder(UIView* v) {
    if (v.isFirstResponder) { return v; }
    for (UIView* sub in v.subviews) {
        UIView* r = NFBFindFirstResponder(sub);
        if (r) { return r; }
    }
    return nil;
}

// Build the icon-bar web view (which becomes the keyboard accessory) from the icons.
static void NFBBuildIconBar(NSArray<NSDictionary*>* icons, WKWebView* replyWebView) {
    if (icons.count == 0) { return; }
    NSMutableString* cells = [NSMutableString string];
    for (NSDictionary* ic in icons) {
        NSString* svg = [ic[@"h"] isKindOfClass:[NSString class]] ? ic[@"h"] : @"";
        NSInteger oi = [ic[@"oi"] integerValue];
        [cells appendFormat:@"<div class='c' onclick='t(%ld)'>%@</div>", (long)oi, svg];
    }
    NSString* html = [NSString stringWithFormat:
        @"<html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
        @"<meta name='color-scheme' content='light dark'>"
        @"<style>*{margin:0;padding:0;box-sizing:border-box;-webkit-tap-highlight-color:transparent;"
        @"-webkit-user-select:none}html,body{height:100%%;background:transparent}"
        @"body{display:flex;align-items:center;padding:0 6px;"
        @"border-top:0.5px solid rgba(128,128,128,0.28)}"
        @".c{width:44px;height:44px;display:flex;align-items:center;justify-content:center;"
        @"cursor:pointer;color:#6E6E73}.c svg{width:23px;height:23px}"
        @".c svg *:not([fill=\"none\"]){fill:#6E6E73!important}"
        @"@media (prefers-color-scheme:dark){.c{color:#AEAEB2}"
        @".c svg *:not([fill=\"none\"]){fill:#AEAEB2!important}}</style>"
        @"<script>function t(i){try{window.webkit.messageHandlers.nfbTap.postMessage(i);}catch(e){}}</script>"
        @"</head><body>%@</body></html>", cells];

    WKWebViewConfiguration* cfg = [[WKWebViewConfiguration alloc] init];
    [cfg.userContentController addScriptMessageHandler:[NFBIconRelay shared] name:@"nfbTap"];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    WKWebView* bar = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, screenW, 46)
                                        configuration:cfg];
    bar.opaque = NO;
    bar.backgroundColor = [UIColor systemBackgroundColor];
    bar.scrollView.backgroundColor = [UIColor clearColor];
    bar.scrollView.scrollEnabled = NO;
    if (@available(iOS 11.0, *)) {
        bar.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [bar loadHTMLString:html baseURL:nil];

    gNFBRelayWebView = replyWebView;
    gNFBIconBar = bar;
    UIView* fr = NFBFindFirstResponder(replyWebView);
    [fr reloadInputViews];  // nil-safe; the bar is picked up on focus if the keyboard isn't up yet
}
// ---------------------------------------------------------------------------

static void openStatusNatively(NSString* statusID) {
    if (statusID.length == 0) {
        return;
    }

    NSURL* url =
        [NSURL URLWithString:[NSString stringWithFormat:@"twitter://status?id=%@", statusID]];
    if (!url) {
        return;
    }

    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(openURL:options:)]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, @selector(openURL:options:), url, @{});
    }
}

static void showPostSentAlert(NSString* statusID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* top = topMostController();
        if (!top) {
            return;
        }
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:
                [[BHTBundle sharedBundle]
                    localizedTwitterStringForKey:
                        @"COMPOSITION_COMPLETE_SENDING_TWEET_TOAST_NOTIFICATION_MESSAGE"]
                             message:nil
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                            localizedTwitterStringForKey:
                                                                @"DM_MESSAGE_ACTION_OPEN_GENERIC_TITLE"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction* action) {
                                                    openStatusNatively(statusID);
                                                }]];
        [alert
            addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                         localizedTwitterStringForKey:@"DISMISS_LABEL"]
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

// Weak proxy so the user-content-controller doesn't retain the view controller (which would
// leak it). The controller stays the real handler; this just forwards without a strong ref.
@interface NFBWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) id<WKScriptMessageHandler> target;
@end
@implementation NFBWeakScriptMessageHandler
- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
    [self.target userContentController:userContentController didReceiveScriptMessage:message];
}
@end

// Custom reply web view. Instead of leaning on T1WebViewController's shouldAuthenticate
// path (which doesn't surface the web session on a sideloaded build → black screen), this
// seeds the harvested session cookies straight into its own cookie store, then loads. It
// also owns its spinner/background and the capture/read scripts. The web view stays hidden
// (alpha 0, spinner over a plain background) until the composer is actually ready, so the
// user never sees x.com's loading splash / flicker — then it fades in.
@interface BHTReplyWebViewController : UIViewController <WKNavigationDelegate, WKScriptMessageHandler>
@property(nonatomic, copy) NSString* statusID;
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, strong) UIActivityIndicatorView* spinner;
@property(nonatomic, assign) BOOL sentHandled;
@property(nonatomic, assign) BOOL revealed;
@end

@implementation BHTReplyWebViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [[BHTBundle sharedBundle] localizedStringForKey:@"REPLY_WEBVIEW_TITLE"];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancelTapped)];

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    // Let the page tell us (from ReplyFocusScript) the moment the composer is ready, so we
    // can fade the web view in only then — hiding x.com's loading splash. A weak proxy avoids
    // retaining self.
    NFBWeakScriptMessageHandler* readyProxy = [[NFBWeakScriptMessageHandler alloc] init];
    readyProxy.target = self;
    [configuration.userContentController addScriptMessageHandler:readyProxy name:@"nfbReady"];
    // Injected BEFORE x.com's code runs: replace visualViewport with a static fake. x.com's own
    // keyboard handlers subscribe to an object that never changes, so the page never fights our
    // scroll when the keyboard moves (its visualViewport listener was one of the three competing
    // scrollers in the recordings). All fields present so their reads never throw.
    WKUserScript* vvFreeze = [[WKUserScript alloc]
        initWithSource:
            @"(function(){try{"
            @"var f={width:window.innerWidth,height:window.innerHeight,"
            @"offsetLeft:0,offsetTop:0,pageLeft:0,pageTop:0,scale:1,"
            @"onresize:null,onscroll:null,"
            @"addEventListener:function(){},removeEventListener:function(){},"
            @"dispatchEvent:function(){return true;}};"
            @"Object.defineProperty(window,'visualViewport',"
            @"{get:function(){return f;},configurable:false});"
            @"}catch(e){}})();"
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:YES];
    [configuration.userContentController addUserScript:vvFreeze];
    [configuration.userContentController addScriptMessageHandler:readyProxy name:@"nfbIcons"];
    [configuration.userContentController addScriptMessageHandler:readyProxy name:@"nfbGeo"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.alpha = 0.0;  // hidden until the composer is ready (revealWebView)
    self.webView.backgroundColor = [UIColor systemBackgroundColor];
    self.webView.scrollView.backgroundColor = [UIColor systemBackgroundColor];
    self.webView.scrollView.contentInsetAdjustmentBehavior =
        UIScrollViewContentInsetAdjustmentNever;
    self.webView.customUserAgent =
        @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like "
        @"Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
    [self.view addSubview:self.webView];

    // FULL-HEIGHT web view, never resized: keyboard geometry goes through contentInset (see
    // nfbKeyboardWillChangeFrame) so the web layout viewport stays constant — no reflow, no flash.
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask =
        UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.spinner.hidesWhenStopped = YES;
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];

    NSString* urlString =
        [NSString stringWithFormat:@"https://x.com/intent/tweet?in_reply_to=%@", self.statusID];
    NSURL* url = [NSURL URLWithString:urlString];
    __weak typeof(self) weakSelf = self;
    // Seed the session into this webview's cookie store, THEN load — so the compose page
    // opens authenticated and never shows the login wall / black screen.
    seedReplyWebViewCookies(self.webView, ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && url) {
            [strongSelf.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    });

    // Safety net: if the composer-ready message never arrives, reveal anyway so we never
    // leave the user staring at a spinner.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [weakSelf revealWebView];
                   });
}

// Fade the web view in and drop the spinner — called once the composer is ready (or on the
// safety timeout). Idempotent.
- (void)revealWebView {
    if (self.revealed) {
        return;
    }
    self.revealed = YES;
    [UIView animateWithDuration:0.2
                     animations:^{
                         self.webView.alpha = 1.0;
                     }];
    [self.spinner stopAnimating];
    [self.spinner removeFromSuperview];
}

// ReplyFocusScript posts "nfbReady" the instant it finds the compose box.
- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
    if ([message.name isEqualToString:@"nfbReady"]) {
        [self revealWebView];
        // Fallback: if the icon extraction never delivers (x.com DOM change), still open the
        // keyboard after 2.5s — without the bar — rather than leaving the user with no keyboard.
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf nfbFocusComposeIfNeeded];
        });
    } else if ([message.name isEqualToString:@"nfbIcons"]) {
        if (gNFBIconBar) { return; }  // build once
        NSData* data = [[message.body description] dataUsingEncoding:NSUTF8StringEncoding];
        NSArray* icons = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([icons isKindOfClass:[NSArray class]]) {
            NFBBuildIconBar(icons, self.webView);
        }
        // Focus AFTER the bar exists: the keyboard's first presentation then already includes it
        // (one keyboard event, one layout — the late bar attach was the post-open bounce).
        [self nfbFocusComposeIfNeeded];
    } else if ([message.name isEqualToString:@"nfbGeo"]) {
        // Native scroll-range clamp (measured, not guessed). The page reports where the composer
        // actually ends (document points); we compare the scroll view's REAL max offset against
        // "composer bottom at the keyboard top" and subtract the exact excess from the inset —
        // negative insets are valid and only trim range. Idempotent (excess≈0 → no-op) and reset
        // when the keyboard hides, so Show more never sees it.
        if (gNFBLastKbOverlap <= 60) { return; }  // only meaningful with the keyboard up
        CGFloat bb = [message.body doubleValue] * self.webView.scrollView.zoomScale;
        if (bb <= 0) { return; }
        UIScrollView* sv = self.webView.scrollView;
        CGFloat H = CGRectGetHeight(sv.bounds);
        CGFloat currentMax = sv.contentSize.height - H + sv.adjustedContentInset.bottom;
        CGFloat desiredMax = bb - (H - gNFBLastKbOverlap) + 6.0;
        if (desiredMax < 0) { desiredMax = 0; }
        CGFloat excess = currentMax - desiredMax;
        if (excess > 8.0) {
            UIEdgeInsets inset = sv.contentInset;
            inset.bottom -= excess;
            sv.contentInset = inset;
        }
    }
}

// Issues the single programmatic focus that opens the keyboard, at most once per reply.
- (void)nfbFocusComposeIfNeeded {
    if (gNFBDidRequestFocus || !gBHTReplyWebViewActive) { return; }
    gNFBDidRequestFocus = YES;
    gNFBForceNextFocus = YES;  // consumed by the WKContentView swizzle for THIS focus only
    [self.webView evaluateJavaScript:
        @"(function(){var c=document.querySelector('div[role=\"textbox\"]')"
        @"||document.querySelector('textarea');if(c){c.focus();}})();"
                   completionHandler:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    gBHTReplyWebViewActive = YES;
    gNFBReplyScroller = self.webView.scrollView;  // DIAG: identity for the counting hook
    gNFBDidRequestFocus = NO;
    gNFBLastKbOverlap = 0;
    gNFBForceNextFocus = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(nfbKeyboardWillChangeFrame:)
        name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(nfbKeyboardWillChangeFrame:)
        name:UIKeyboardWillHideNotification object:nil];
}

// The web view stays FULL HEIGHT, never resized. NO manual contentInset either: WKWebView applies
// its OWN keyboard inset + focused-field reveal internally, so setting ours on top DOUBLED the
// bottom inset — that was the too-long scroll range / wrong scrollbar zone on keyboard-up (Show
// more was clean because both insets are zero with the keyboard down), and the double adjustment
// was the small return bounce. This handler now only forwards keyboard events to the page script.
- (void)nfbKeyboardWillChangeFrame:(NSNotification*)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    BOOL hiding = [note.name isEqualToString:UIKeyboardWillHideNotification];
    CGFloat overlap = 0.0;
    if (!hiding && self.view.window) {
        CGRect kbInView = [self.view convertRect:endFrame fromView:nil];
        overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(kbInView);
        if (overlap < 0) { overlap = 0; }
    }
    if (fabs(gNFBLastKbOverlap - overlap) < 0.5) { return; }  // duplicate notification
    gNFBLastKbOverlap = overlap;
    if (overlap <= 60) {
        // Keyboard going down: drop any scroll-range trim so Show more sees pristine geometry.
        UIEdgeInsets inset = self.webView.scrollView.contentInset;
        if (inset.bottom != 0) {
            inset.bottom = 0;
            self.webView.scrollView.contentInset = inset;
        }
    }
    BOOL kbUp = (overlap > 60);
    if (kbUp) {
        // FIX: arm the window that drops WebKit's bounds.origin reveal animation on our scroller.
        gNFBSquelchUntil = CACurrentMediaTime() + 0.60;
        gNFBAnimsKilled = 0;
    } else {
        gNFBSquelchUntil = 0;  // keyboard down (Show more): never drop anything
    }
    NSString* js = [NSString stringWithFormat:@"window.__nfbKb&&window.__nfbKb(%d,%.0f)",
                    kbUp ? 1 : 0, overlap];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    gNFBReplyScroller = nil;
    gNFBSquelchUntil = 0;
    [super viewWillDisappear:animated];
    gBHTReplyWebViewActive = NO;
    gNFBIconBar = nil;          // rebuilt fresh for the next reply
    gNFBRelayWebView = nil;
    gNFBForceNextFocus = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UIKeyboardWillHideNotification object:nil];
    gNFBLastKbOverlap = 0;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(__unused WKNavigation*)navigation {
    // Hook fetch/XHR so the sent reply's id is captured into sessionStorage.
    [webView evaluateJavaScript:ReplyCaptureScript completionHandler:nil];

    // Navigating to /home means the reply posted: read the id, close, confirm.
    if ([webView.URL.path isEqualToString:@"/home"]) {
        if (self.sentHandled) {
            return;
        }
        self.sentHandled = YES;
        __weak typeof(self) weakSelf = self;
        [webView evaluateJavaScript:ReplyReadScript
                  completionHandler:^(id result, __unused NSError* jsError) {
                      NSString* newReplyID =
                          [result isKindOfClass:[NSString class]] ? (NSString*)result : nil;
                      [weakSelf dismissViewControllerAnimated:YES
                                                   completion:^{
                                                       if (newReplyID.length > 0) {
                                                           showPostSentAlert(newReplyID);
                                                       }
                                                   }];
                  }];
        return;
    }

    // Compose page: hide promo banners, pin the toolbar above the keyboard, then focus the box.
    // Compose page: hide promo banners, then drop the cursor into the box. The compose box is
    // pinned to the bottom ONLY when the keyboard is down ("Show more"); while typing it scrolls
    // naturally with the tweet (pinning a focused field floats it and flickered).
    [webView evaluateJavaScript:ReplyStyleScript completionHandler:nil];
    [webView evaluateJavaScript:ReplyTapDismissScript completionHandler:nil];
    [webView evaluateJavaScript:ReplyBarPinScript completionHandler:nil];
    [webView evaluateJavaScript:ReplyFocusScript completionHandler:nil];
    [webView evaluateJavaScript:ReplyIconExtractScript completionHandler:nil];
    [webView evaluateJavaScript:
        @"(function(){if(document.getElementById('__nfbV'))return;"
        @"var b=document.createElement('div');b.id='__nfbV';b.textContent='NFB v2.2';"
        @"b.style.cssText='position:fixed;bottom:6px;right:6px;z-index:2147483647;"
        @"background:rgba(0,0,0,.6);color:#7CFC00;font:10px Menlo,monospace;"
        @"padding:2px 6px;border-radius:6px;pointer-events:none;';"
        @"document.documentElement.appendChild(b);"
        @"setTimeout(function(){try{b.remove();}catch(e){}},1500);})();"
                 completionHandler:nil];
}

- (void)webView:(__unused WKWebView*)webView
    didFailProvisionalNavigation:(__unused WKNavigation*)navigation
                       withError:(__unused NSError*)error {
    [self revealWebView];
}

@end

static BOOL openAuthenticatedTweetWebView(NSString* statusID) {
    if (statusID.length == 0) {
        return NO;
    }

    UIViewController* presentingController = topMostController();
    if (!presentingController) {
        return NO;
    }

    BHTReplyWebViewController* replyController = [[BHTReplyWebViewController alloc] init];
    replyController.statusID = statusID;

    UINavigationController* modalNavigationController =
        [[UINavigationController alloc] initWithRootViewController:replyController];
    modalNavigationController.modalPresentationStyle = UIModalPresentationFullScreen;

    [presentingController presentViewController:modalNavigationController animated:YES completion:nil];
    return YES;
}

// No web session yet: present the interactive login once, then open the reply once
// cookies have been harvested. We deliberately don't fall back to a native reply here
// (that's the attestation path the user turned reply_in_webview on to avoid).
static void ensureSessionThenOpenReply(NSString* statusID) {
    presentWebSessionLogin(^(BOOL success) {
        if (success && hasUsableWebCredentials()) {
            openAuthenticatedTweetWebView(statusID);
        }
    });
}

// MARK: - Hooks

// The inline reply button has no dedicated ObjC subclass in 12.3; every inline
// reply tap funnels through this handler with the status being replied to.
// WebKit reveals the reply field with a PAIR of CABasicAnimations on the scroll
// view LAYER — bounds.origin (the -173 pan) and its twin bounds.size. During the
// keyboard-up window, on OUR scroller's layer only, those two are dropped so they
// are never installed. Every other layer / keyPath, and (window zeroed) Show
// more, are untouched.
%hook CALayer
- (void)addAnimation:(CAAnimation*)anim forKey:(NSString*)key {
    if (gBHTReplyWebViewActive && gNFBReplyScroller
        && self == gNFBReplyScroller.layer
        && CACurrentMediaTime() < gNFBSquelchUntil
        && [anim isKindOfClass:[CABasicAnimation class]]) {
        NSString* kp = [(CABasicAnimation*)anim keyPath];
        if ([kp isEqualToString:@"bounds.origin"] || [kp isEqualToString:@"bounds.size"]
            || [kp isEqualToString:@"bounds"]) {
            gNFBAnimsKilled++;
            return;  // never install WebKit's mis-targeted reveal animation
        }
    }
    %orig(anim, key);
}
%end

%hook T1StatusViewInlineActionTapEventHandler
- (void)performReplyActionWithAccount:(__unsafe_unretained id)account
                                event:(__unsafe_unretained id)event
                           controller:(__unsafe_unretained id)controller
                        scribeContext:(__unsafe_unretained id)scribeContext
                        scribeElement:(__unsafe_unretained id)scribeElement
                           parameters:(__unsafe_unretained id)parameters
                       originalStatus:(__unsafe_unretained TFNTwitterStatus*)originalStatus {
    if (![BHTSettings boolForKey:@"reply_in_webview"]) {
        return %orig;
    }

    if (![originalStatus respondsToSelector:@selector(statusID)]) {
        return %orig;
    }

    NSInteger statusID = originalStatus.statusID;
    if (statusID <= 0) {
        return %orig;
    }

    NSString* statusIDString = @(statusID).stringValue;
    if (hasUsableWebCredentials()) {
        if (!openAuthenticatedTweetWebView(statusIDString)) {
            return %orig;
        }
    } else {
        ensureSessionThenOpenReply(statusIDString);
    }
}
%end

%hook T1PersistentComposeViewController
- (void)persistentComposeViewDidTap:(id)composeView {
    if (![BHTSettings boolForKey:@"reply_in_webview"]) {
        return %orig;
    }

    TFNTwitterStatus* status = statusFromObject(self.statusViewModel);
    NSInteger statusID = status.statusID;
    if (statusID <= 0) {
        return %orig;
    }

    NSString* statusIDString = @(statusID).stringValue;
    if (hasUsableWebCredentials()) {
        if (!openAuthenticatedTweetWebView(statusIDString)) {
            return %orig;
        }
    } else {
        ensureSessionThenOpenReply(statusIDString);
    }
}
%end

%hook T1WebViewController
- (void)didFinishLoadingWithError:(id)error {
    %orig;
    // Still needed: the offscreen bootstrap harvest webview (WebCreateTweet.x) is a
    // T1WebViewController and relies on this hook to harvest its cookies. The reply itself
    // no longer uses T1WebViewController — it's the custom BHTReplyWebViewController above.
    maybeHandleHarvestWebView(self);
}
%end

// Let the injected focus() raise the keyboard without a user tap. We swizzle the private
// WKContentView focus callback and force userIsInteracting:YES — but only while our reply
// web view is on screen (gBHTReplyWebViewActive), so nothing else in the app is affected.
//
// This is done with method_setImplementation (not %hook) on purpose: the first parameter is
// a C++ reference, not an Objective-C object, so it MUST be typed void* — otherwise ARC
// tries to retain/release it and crashes. The selector has been
// stable since iOS 13; if it's ever missing we simply don't swizzle and focus still works
// (keyboard then needs one tap).
%ctor {
    @autoreleasepool {
        Class contentViewClass = NSClassFromString(@"WKContentView");
        if (!contentViewClass) {
            return;
        }
        SEL focusSel = sel_getUid(
            "_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:");
        Method focusMethod = class_getInstanceMethod(contentViewClass, focusSel);
        if (!focusMethod) {
            return;
        }
        __block IMP originalFocusIMP = method_getImplementation(focusMethod);
        IMP overrideIMP = imp_implementationWithBlock(^void(id self_, void* information,
                                                            BOOL userIsInteracting, BOOL blurPreviousNode,
                                                            unsigned long long activityStateChanges,
                                                            id userObject) {
            if (gBHTReplyWebViewActive && gNFBForceNextFocus) {
                gNFBForceNextFocus = NO;  // force only OUR programmatic focus; dismiss sticks
                userIsInteracting = YES;
            }
            ((void (*)(id, SEL, void*, BOOL, BOOL, unsigned long long, id))originalFocusIMP)(
                self_, focusSel, information, userIsInteracting, blurPreviousNode, activityStateChanges,
                userObject);
        });
        method_setImplementation(focusMethod, overrideIMP);

        // Remove the form-assistant bar (the translucent "^ v Done" pill above the keyboard)
        // while our reply web view is on screen: return nil from WKContentView's
        // inputAccessoryView. Dismissing the keyboard still works — tap anywhere outside the
        // compose box (handled by ReplyTapDismissScript). Only swizzle if WKContentView
        // implements it itself, so we never touch UIResponder's inputAccessoryView app-wide.
        SEL accessorySel = @selector(inputAccessoryView);
        unsigned int methodCount = 0;
        Method* methods = class_copyMethodList(contentViewClass, &methodCount);
        Method accessoryMethod = NULL;
        for (unsigned int i = 0; i < methodCount; i++) {
            if (method_getName(methods[i]) == accessorySel) {
                accessoryMethod = methods[i];
                break;
            }
        }
        free(methods);
        if (accessoryMethod) {
            __block IMP originalAccessoryIMP = method_getImplementation(accessoryMethod);
            IMP accessoryOverride = imp_implementationWithBlock(^id(id self_) {
                if (gBHTReplyWebViewActive) {
                    return gNFBIconBar;  // our native icon bar (nil until built -> no form bar)
                }
                return ((id (*)(id, SEL))originalAccessoryIMP)(self_, accessorySel);
            });
            method_setImplementation(accessoryMethod, accessoryOverride);
        }
    }
}

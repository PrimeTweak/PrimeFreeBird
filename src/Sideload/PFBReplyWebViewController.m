#import "Support/HookHelpers.h"
#import <QuartzCore/QuartzCore.h>
#import "Sideload/PFBReplyWebViewState.h"
#import "Sideload/PFBReplyWebViewController.h"
#import "Sideload/PFBWeakScriptMessageHandler.h"
#import "Sideload/PFBIconRelay.h"

// Injected into the reply webview: hooks fetch/XHR to capture the new post's ID from
// the web CreateTweet response, since there's no native completion callback to read.
static NSString* const ReplyCaptureScript =
    @"(function(){"
     "if(window.__pfbReplyHook)return;window.__pfbReplyHook=true;"
     "var save=function(j){try{if(j&&j.data){"
     "var "
     "r=(j.data.create_tweet&&j.data.create_tweet.tweet_results&&j.data.create_tweet.tweet_results."
     "result)||"
     "(j.data.notetweet_create&&j.data.notetweet_create.tweet_results&&j.data.notetweet_create."
     "tweet_results.result);"
     "if(r&&r.rest_id)sessionStorage.setItem('__pfbNewReply',String(r.rest_id));}}catch(e){}};"
     "var isCreate=function(u){return typeof u==='string'&&u.indexOf('CreateTweet')!==-1;};"
     "var of=window.fetch;"
     "if(of){window.fetch=function(){var a=arguments;var u=(a[0]&&a[0].url)||a[0];"
     "return "
     "of.apply(this,a).then(function(res){try{if(isCreate(u))res.clone().json().then(save).catch("
     "function(){});}catch(e){}return res;});};}"
     "var oo=XMLHttpRequest.prototype.open;var os=XMLHttpRequest.prototype.send;"
     "XMLHttpRequest.prototype.open=function(m,u){this.__pfbURL=u;return "
     "oo.apply(this,arguments);};"
     "XMLHttpRequest.prototype.send=function(){var x=this;try{if(isCreate(x.__pfbURL)){"
     "x.addEventListener('load',function(){try{save(JSON.parse(x.responseText));}catch(e){}});}}"
     "catch(e){}return os.apply(this,arguments);};"
     "})();";
// Reads and clears the reply ID stashed by the capture script.
static NSString* const ReplyReadScript =
    @"(function(){var "
    @"v=sessionStorage.getItem('__pfbNewReply')||'';sessionStorage.removeItem('__pfbNewReply');"
    @"return v;})();";
// Injected on the reply page: hides only the promo banners and the web back arrow.
// The compose toolbar and layout are left untouched, since x.com keeps its toolbar
// above the keyboard by itself.
static NSString* const ReplyStyleScript =
    @"(function(){var css='"
    @"[data-testid=\"app-promo-banner\"],div[role=\"dialog\"] a[href*=\"apple.com\"],"
    @"div[role=\"dialog\"] a[href*=\"google.com\"],iframe[src*=\"google\"],.twitter-app-banner"
    @"{display:none !important;}"
    @"[data-testid=\"app-bar-back\"],[aria-label=\"Back\"]{display:none !important;}"
    @"';"
    @"var s=document.getElementById('pfb-reply-style')||document.createElement('style');"
    @"s.id='pfb-reply-style';s.innerHTML=css;"
    @"if(!s.parentNode){(document.head||document.documentElement).appendChild(s);}})();";
// Injected on the reply page: polls for the compose box, which renders async, and
// reports it ready. Focus is issued natively after the icon bar is built, so the
// keyboard's first presentation already includes it.
static NSString* const ReplyFocusScript =
    @"(function(){var n=0;"
    @"function box(){return document.querySelector('div[role=\"textbox\"]')"
    @"||document.querySelector('textarea');}"
    @"function go(){var b=box();if(b){"
    @"try{window.webkit.messageHandlers.pfbReady.postMessage(1);}catch(e){}"
    @"return;}"
    @"if(n++<40){setTimeout(go,150);}}go();})();";
// Injected on the reply page: a real tap outside the compose box or toolbar blurs the
// field. Finger movement is tracked so a scroll or drag does not dismiss the keyboard
// and make the page jump.
static NSString* const ReplyTapDismissScript =
    @"(function(){if(window.__pfbTapBlur)return;window.__pfbTapBlur=1;"
    @"var sx=0,sy=0,mv=false;"
    @"document.addEventListener('pointerdown',function(e){sx=e.clientX;sy=e.clientY;mv=false;},true);"
    @"document.addEventListener('pointermove',function(e){"
    @"if(Math.abs(e.clientX-sx)>10||Math.abs(e.clientY-sy)>10){mv=true;}},true);"
    @"document.addEventListener('pointerup',function(e){if(mv)return;"
    @"var b=document.querySelector('div[role=\"textbox\"]');"
    @"var t=document.querySelector('[data-testid=\"toolBar\"]');"
    @"if(b&&!b.contains(e.target)&&!(t&&t.contains(e.target))){"
    @"var a=document.activeElement;if(a&&a.blur){a.blur();}}},true);})();";
// The web view is full height and never resized, with no manual insets: WKWebView's
// own keyboard inset and focused-field reveal do the work, and native code only
// forwards keyboard events. The reply box stays in flow with the tweet.
static NSString* const ReplyBarPinScript =
    @"(function(){if(window.__pfbKbInit)return;window.__pfbKbInit=1;window.__pfbColl=[];"
    @"function findBox(){"
    @"var c=document.querySelector('div[role=\"textbox\"]')||document.querySelector('textarea');"
    @"var t=document.querySelector('[data-testid=\"toolBar\"]');if(!t||!c)return null;"
    @"var box=t,s=0;while(box&&!box.contains(c)&&s<6){box=box.parentElement;s++;}"
    @"if(!box||!box.contains(c)||box===document.body)return null;return box;}"
    @"function clr(box){box.style.position='';box.style.left='';box.style.right='';"
    @"box.style.bottom='';box.style.zIndex='';box.style.background='';box.style.paddingBottom='';"
    @"document.body.style.paddingBottom='';document.body.style.paddingTop='';"
    @"document.body.style.marginBottom='';"
    @"for(var i=0;i<window.__pfbColl.length;i++){var e=window.__pfbColl[i];"
    @"e.style.removeProperty('min-height');e.style.removeProperty('height');"
    @"e.style.removeProperty('flex-grow');e.style.removeProperty('max-height');"
    @"e.style.removeProperty('overflow-y');e.style.removeProperty('overflow');"
    @"e.style.removeProperty('padding-bottom');}"
    @"window.__pfbColl=[];}"
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
    @"window.__pfbColl.push(el);}}"
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
    @"window.__pfbColl.push(el);}}"
    @"function apply(up,kb){var box=findBox();if(!box)return;"
    @"if(up){clr(box);vfix(box);killspacers();"
    @"var place=function(){"
    @"var c=document.querySelector('div[role=\"textbox\"]')||document.querySelector('textarea');"
    @"if(!c)return;var bx=findBox()||c;"
    @"var bb=bx.getBoundingClientRect().bottom+(window.pageYOffset||0);"
    @"var sh=Math.max(document.body.scrollHeight,document.documentElement.scrollHeight);"
    @"var trail=sh-bb;"
    @"if(trail>24){document.body.style.marginBottom=(-(trail-16))+'px';}"
    @"try{window.webkit.messageHandlers.pfbGeo.postMessage(bb);}catch(e){}"
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
    @"window.__pfbKb=function(up,kb){"
    @"if(up){apply(1,kb||0);}"
    @"else{var b=findBox();"
    @"if(b&&b.style.position==='fixed'){b.style.bottom='0';}"
    @"setTimeout(function(){apply(0,0);},120);setTimeout(function(){apply(0,0);},450);}};})();";
// Guards the focus request so the icons path and the fallback timer can't both fire it.
static BOOL gPFBDidRequestFocus = NO;
// Last keyboard overlap seen, to drop duplicate keyboard notifications.
static CGFloat gPFBLastKbOverlap = 0;
// Extract each toolbar button's SVG and its index, post to native, then
// hide x.com's own toolbar (display:none — no layout space, so the composer stays
// compact; a dispatched click still fires x.com's React handlers even hidden).
static NSString* const ReplyIconExtractScript =
    @"(function(){var tries=0;function go(){"
    @"var tb=document.querySelector('[data-testid=\"toolBar\"]');"
    @"if(!tb){if(tries++<15){setTimeout(go,300);}return;}"
    @"var bs=tb.querySelectorAll('button,[role=\"button\"]');var out=[];"
    @"for(var i=0;i<bs.length;i++){var s=bs[i].querySelector('svg');if(!s)continue;"
    @"out.push({h:s.outerHTML,oi:i});}"
    @"if(!out.length){if(tries++<15){setTimeout(go,300);}return;}"
    @"try{window.webkit.messageHandlers.pfbIcons.postMessage(JSON.stringify(out));}catch(e){}"
    @"tb.style.setProperty('display','none','important');}go();})();";
// Build the icon-bar web view (which becomes the keyboard accessory) from the icons.
static void PFBBuildIconBar(NSArray<NSDictionary*>* icons, WKWebView* replyWebView) {
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
        @"<script>function t(i){try{window.webkit.messageHandlers.pfbTap.postMessage(i);}catch(e){}}</script>"
        @"</head><body>%@</body></html>", cells];

    WKWebViewConfiguration* cfg = [[WKWebViewConfiguration alloc] init];
    [cfg.userContentController addScriptMessageHandler:[PFBIconRelay shared] name:@"pfbTap"];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    WKWebView* bar = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, screenW, 46)
                                        configuration:cfg];
    bar.opaque = NO;
    bar.backgroundColor = [UIColor systemBackgroundColor];
    bar.scrollView.backgroundColor = [UIColor clearColor];
    bar.scrollView.scrollEnabled = NO;
    bar.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [bar loadHTMLString:html baseURL:nil];

    gPFBRelayWebView = replyWebView;
    gPFBIconBar = bar;
    UIView* fr = PFBFindFirstResponder(replyWebView);
    [fr reloadInputViews];  // nil-safe; the bar is picked up on focus if the keyboard isn't up yet
}
static void showPostSentAlert(NSString* statusID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* top = topMostController();
        if (!top) {
            return;
        }
        // Twitter files this text as a plural; formatting it for one Tweet picks the singular.
        NSString* sent = PFBTwitterTerminology([NSString
            localizedStringWithFormat:[[PFBBundle sharedBundle]
                                          localizedTwitterStringForKey:
                                              @"COMPOSITION_COMPLETE_SENDING_TWEET_TOAST_NOTIFICATION_MESSAGE"],
                                      1LL]);
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:sent
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[[PFBBundle sharedBundle]
                                                            localizedTwitterStringForKey:
                                                                @"DM_MESSAGE_ACTION_OPEN_GENERIC_TITLE"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction* action) {
                                                    PFBOpenStatusNatively(statusID);
                                                }]];
        [alert
            addAction:[UIAlertAction actionWithTitle:[[PFBBundle sharedBundle]
                                                         localizedTwitterStringForKey:@"DISMISS_LABEL"]
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}
@implementation PFBReplyWebViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [[PFBBundle sharedBundle] localizedStringForKey:@"REPLY_WEBVIEW_TITLE"];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancelTapped)];

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    // The page signals (from ReplyFocusScript) the moment the composer is ready, so the web
    // view fades in only then, hiding x.com's loading splash. A weak proxy avoids retaining
    // self.
    PFBWeakScriptMessageHandler* readyProxy = [[PFBWeakScriptMessageHandler alloc] init];
    readyProxy.target = self;
    [configuration.userContentController addScriptMessageHandler:readyProxy name:@"pfbReady"];
    // Injected before the page's own code runs: visualViewport is replaced with a
    // static stand-in, so the page's keyboard handlers subscribe to an object that
    // never changes. All fields are present so their reads never throw.
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
    [configuration.userContentController addScriptMessageHandler:readyProxy name:@"pfbIcons"];
    [configuration.userContentController addScriptMessageHandler:readyProxy name:@"pfbGeo"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.alpha = 0.0;  // hidden until the composer is ready (revealWebView)
    self.webView.backgroundColor = [UIColor systemBackgroundColor];
    self.webView.scrollView.backgroundColor = [UIColor systemBackgroundColor];
    self.webView.scrollView.contentInsetAdjustmentBehavior =
        UIScrollViewContentInsetAdjustmentNever;
    self.webView.customUserAgent = PFBMobileSafariUserAgent;
    [self.view addSubview:self.webView];

    // FULL-HEIGHT web view, never resized: keyboard geometry goes through contentInset (see
    // pfbKeyboardWillChangeFrame) so the web layout viewport stays constant — no reflow, no flash.
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
    PFBSeedReplyWebViewCookies(self.webView, ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && url) {
            [strongSelf.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    });

    // Safety net: if the composer-ready message never arrives, the web view is revealed anyway
    // so the user is never left staring at a spinner.
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

// ReplyFocusScript posts "pfbReady" the instant it finds the compose box.
- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
    if ([message.name isEqualToString:@"pfbReady"]) {
        [self revealWebView];
        // Fallback: if the icon extraction never delivers (x.com DOM change), still open the
        // keyboard after 2.5s — without the bar — rather than leaving the user with no keyboard.
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf pfbFocusComposeIfNeeded];
        });
    } else if ([message.name isEqualToString:@"pfbIcons"]) {
        if (gPFBIconBar) { return; }  // build once
        NSData* data = [[message.body description] dataUsingEncoding:NSUTF8StringEncoding];
        NSArray* icons = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([icons isKindOfClass:[NSArray class]]) {
            PFBBuildIconBar(icons, self.webView);
        }
        // Focus AFTER the bar exists: the keyboard's first presentation then already includes it
        // (one keyboard event, one layout).
        [self pfbFocusComposeIfNeeded];
    } else if ([message.name isEqualToString:@"pfbGeo"]) {
        // Native scroll-range clamp: the page reports where the composer ends, and
        // the excess over "composer bottom at the keyboard top" is subtracted from
        // the inset. Idempotent, and reset when the keyboard hides.
        if (gPFBLastKbOverlap <= 60) { return; }  // only meaningful with the keyboard up
        CGFloat bb = [message.body doubleValue] * self.webView.scrollView.zoomScale;
        if (bb <= 0) { return; }
        UIScrollView* sv = self.webView.scrollView;
        CGFloat H = CGRectGetHeight(sv.bounds);
        CGFloat currentMax = sv.contentSize.height - H + sv.adjustedContentInset.bottom;
        CGFloat desiredMax = bb - (H - gPFBLastKbOverlap) + 6.0;
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
- (void)pfbFocusComposeIfNeeded {
    if (gPFBDidRequestFocus || !gPFBReplyWebViewActive) { return; }
    gPFBDidRequestFocus = YES;
    gPFBForceNextFocus = YES;  // consumed by the WKContentView swizzle for THIS focus only
    [self.webView evaluateJavaScript:
        @"(function(){var c=document.querySelector('div[role=\"textbox\"]')"
        @"||document.querySelector('textarea');if(c){c.focus();}})();"
                   completionHandler:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    gPFBReplyWebViewActive = YES;
    gPFBReplyScroller = self.webView.scrollView;  // identity for the CALayer hook
    gPFBDidRequestFocus = NO;
    gPFBLastKbOverlap = 0;
    gPFBForceNextFocus = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(pfbKeyboardWillChangeFrame:)
        name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(pfbKeyboardWillChangeFrame:)
        name:UIKeyboardWillHideNotification object:nil];
}

// The web view stays full height with no manual contentInset: WKWebView applies its
// own keyboard inset and focused-field reveal, and adding another doubles it. This
// handler only forwards keyboard events to the page script.
- (void)pfbKeyboardWillChangeFrame:(NSNotification*)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    BOOL hiding = [note.name isEqualToString:UIKeyboardWillHideNotification];
    CGFloat overlap = 0.0;
    if (!hiding && self.view.window) {
        CGRect kbInView = [self.view convertRect:endFrame fromView:nil];
        overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(kbInView);
        if (overlap < 0) { overlap = 0; }
    }
    if (fabs(gPFBLastKbOverlap - overlap) < 0.5) { return; }  // duplicate notification
    gPFBLastKbOverlap = overlap;
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
        // Arms the window that drops WebKit's bounds.origin reveal animation on the reply scroller.
        gPFBSquelchUntil = CACurrentMediaTime() + 0.60;
    } else {
        gPFBSquelchUntil = 0;  // keyboard down (Show more): never drop anything
    }
    NSString* js = [NSString stringWithFormat:@"window.__pfbKb&&window.__pfbKb(%d,%.0f)",
                    kbUp ? 1 : 0, overlap];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    gPFBReplyScroller = nil;
    gPFBSquelchUntil = 0;
    [super viewWillDisappear:animated];
    gPFBReplyWebViewActive = NO;
    gPFBIconBar = nil;          // rebuilt fresh for the next reply
    gPFBRelayWebView = nil;
    gPFBForceNextFocus = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UIKeyboardWillHideNotification object:nil];
    gPFBLastKbOverlap = 0;
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

    // Compose page: hide the promo banners, then drop the cursor into the box. The
    // box is pinned to the bottom only with the keyboard down; while typing it
    // scrolls with the tweet, since pinning a focused field floats it.
    [webView evaluateJavaScript:ReplyStyleScript completionHandler:nil];
    [webView evaluateJavaScript:ReplyTapDismissScript completionHandler:nil];
    [webView evaluateJavaScript:ReplyBarPinScript completionHandler:nil];
    [webView evaluateJavaScript:ReplyFocusScript completionHandler:nil];
    [webView evaluateJavaScript:ReplyIconExtractScript completionHandler:nil];
}

- (void)webView:(__unused WKWebView*)webView
    didFailProvisionalNavigation:(__unused WKNavigation*)navigation
                       withError:(__unused NSError*)error {
    [self revealWebView];
}

@end

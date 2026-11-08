#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#include <atomic>
#include <string.h>
extern "C" int DobbyHook(void *address, void *fake_func, void **out_origin_func);
typedef void *(*InvokeFn)(const void *,void *,void **,void **);
typedef const char *(*NameFn)(const void *);
typedef const void *(*ClassFn)(const void *);
typedef const char *(*NamespaceFn)(const void *);
static InvokeFn originalInvoke = nullptr;
static NameFn methodName = nullptr, className = nullptr, classNamespace = nullptr;
static ClassFn methodClass = nullptr;
static std::atomic<bool> ready(false);
static NSMutableString *traceBuffer;
static dispatch_queue_t traceQueue;
static bool interesting(const char *name) {
 if (!name) return false;
 const char *words[]={"Merge","Producer","Spawner","Hint","Bet","Power","Energy","CreateItem","SpawnItem","IndexInChain","ChainId"};
 for (const char *w:words) if (strstr(name,w)) return true;
 return false;
}
static void recordLine(NSString *line) {
 if (!traceQueue || !line) return;
 dispatch_async(traceQueue, ^{
  if (!traceBuffer) traceBuffer=[NSMutableString new];
  [traceBuffer appendFormat:@"%@\n",line];
  if (traceBuffer.length>180000) [traceBuffer deleteCharactersInRange:NSMakeRange(0,traceBuffer.length-130000)];
 });
}
static thread_local int depth=0;
static void *tracedInvoke(const void *method,void *obj,void **args,void **exception) {
 if (!originalInvoke) return nullptr;
 if (depth++) { void *result=originalInvoke(method,obj,args,exception); --depth; return result; }
 const char *name=methodName?methodName(method):nullptr;
 bool watch=interesting(name);
 NSString *label=nil;
 if (watch) {
  const void *klass=methodClass?methodClass(method):nullptr;
  const char *cn=(klass&&className)?className(klass):"?";
  const char *ns=(klass&&classNamespace)?classNamespace(klass):"?";
  label=[NSString stringWithFormat:@"%s.%s.%s",ns?ns:"?",cn?cn:"?",name?name:"?"];
 }
 void *result=originalInvoke(method,obj,args,exception);
 if (watch) recordLine([NSString stringWithFormat:@"%.3f INVOKE %@ obj=%p ret=%p exception=%d",CFAbsoluteTimeGetCurrent(),label,obj,result,(exception&&*exception)?1:0]);
 --depth;
 return result;
}
@interface VTTraceButton : UIButton
@end
@implementation VTTraceButton
- (void)copyTrace {
 dispatch_async(traceQueue, ^{
  NSString *content=[traceBuffer copy]?:@"VTTRACE EMPTY";
  dispatch_async(dispatch_get_main_queue(), ^{ [UIPasteboard generalPasteboard].string=content; [self setTitle:@"COPIED" forState:UIControlStateNormal]; });
 });
}
@end
static void installButton(void) {
 dispatch_async(dispatch_get_main_queue(), ^{
  UIApplication *app=UIApplication.sharedApplication;
  UIWindow *window=nil;
  if (@available(iOS 13.0,*)) {
   for (UIScene *scene in app.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class]) continue;
    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
     if (w.isKeyWindow && !w.hidden) { window=w; break; }
     if (!window && !w.hidden && w.bounds.size.width>0) window=w;
    }
    if (window && scene.activationState==UISceneActivationStateForegroundActive) break;
   }
  }
  if (!window) window=app.keyWindow;
  if (!window) for (UIWindow *w in app.windows) if (!w.hidden && w.bounds.size.width>0) { window=w; break; }
  if (!window || [window viewWithTag:992076]) return;
  VTTraceButton *b=[VTTraceButton buttonWithType:UIButtonTypeSystem];
  b.tag=992076;
  b.frame=CGRectMake(12,window.bounds.size.height*0.48,120,40);
  b.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
  b.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.8];
  b.layer.cornerRadius=9;
  [b setTitle:@"COPY VT TRACE" forState:UIControlStateNormal];
  [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  b.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightBold];
  [b addTarget:b action:@selector(copyTrace) forControlEvents:UIControlEventTouchUpInside];
  [window addSubview:b];
  [window bringSubviewToFront:b];
  recordLine(@"VTTRACE BUTTON_VISIBLE");
 });
}
static void startButtonRetry(void) {
 dispatch_async(dispatch_get_main_queue(), ^{
  installButton();
  [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
   installButton();
  }];
 });
}
static void attemptInstall(void) {
 if (ready.load()) return;
 void *handle=dlopen("@rpath/UnityFramework.framework/UnityFramework",RTLD_NOW|RTLD_NOLOAD);
 if (!handle) handle=dlopen(nullptr,RTLD_NOW);
 if (!handle) return;
 void *invoke=dlsym(handle,"il2cpp_runtime_invoke");
 if (!invoke) invoke=dlsym(RTLD_DEFAULT,"il2cpp_runtime_invoke");
 if (!invoke) return;
 methodName=(NameFn)dlsym(handle,"il2cpp_method_get_name");
 methodClass=(ClassFn)dlsym(handle,"il2cpp_method_get_class");
 className=(NameFn)dlsym(handle,"il2cpp_class_get_name");
 classNamespace=(NamespaceFn)dlsym(handle,"il2cpp_class_get_namespace");
 if (!methodName || !methodClass || !className || !classNamespace) return;
 if (DobbyHook(invoke,(void *)tracedInvoke,(void **)&originalInvoke)==0) {
  ready.store(true); recordLine(@"VTTRACE HOOK_READY");
 }
}
__attribute__((constructor)) static void initializeTrace(void) {
 traceQueue=dispatch_queue_create("vt.trace.queue",DISPATCH_QUEUE_SERIAL);
 recordLine(@"VTTRACE INIT");
 startButtonRetry();
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
  for (int i=0;i<90 && !ready.load();i++) { attemptInstall(); [NSThread sleepForTimeInterval:1.0]; }
  if (!ready.load()) recordLine(@"VTTRACE HOOK_UNAVAILABLE");
 });
}

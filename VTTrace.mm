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
static std::atomic<unsigned long long> invokeCount(0), filteredCount(0);
static std::atomic<unsigned> sampleCount(0);
static std::atomic<unsigned long long> directCount(0);
static std::atomic<int> directHooks(0);
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
 const unsigned long long count=++invokeCount;
 const char *name=methodName?methodName(method):nullptr;
 bool watch=interesting(name);
 if (watch) ++filteredCount;
 unsigned sample=sampleCount.load();
 if (!watch && name && sample<30 && sampleCount.compare_exchange_strong(sample,sample+1)) recordLine([NSString stringWithFormat:@"VTTRACE SAMPLE #%u method=%s",sample+1,name]);
 if (count==1 || count==100 || count==1000 || count==10000) recordLine([NSString stringWithFormat:@"VTTRACE INVOKE_COUNT=%llu",count]);
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
  NSString *content=[NSString stringWithFormat:@"VTTRACE V4 invoke=%llu filtered=%llu hook=%d direct=%llu directHooks=%d\n%@",invokeCount.load(),filteredCount.load(),ready.load()?1:0,directCount.load(),directHooks.load(),[traceBuffer copy]?:@"VTTRACE EMPTY"];
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
  [NSTimer scheduledTimerWithTimeInterval:15.0 repeats:YES block:^(NSTimer *timer) {
   recordLine([NSString stringWithFormat:@"VTTRACE HEARTBEAT invoke=%llu filtered=%llu hook=%d direct=%llu directHooks=%d",invokeCount.load(),filteredCount.load(),ready.load()?1:0,directCount.load(),directHooks.load()]);
  }];
 });
}

typedef void *(*DomainGetFn)(void);
typedef const void **(*DomainAssembliesFn)(void *,size_t *);
typedef void *(*AssemblyImageFn)(const void *);
typedef const char *(*ImageNameFn)(const void *);
typedef void *(*ClassFromNameFn)(const void *,const char *,const char *);
typedef const void *(*ClassMethodFn)(void *,const char *,int);
static void *origHint=nullptr,*origFind=nullptr,*origPerform=nullptr,*origProducer=nullptr,*origSpawner=nullptr,*origBet=nullptr;
static thread_local bool directBusy=false;
static void directLog(NSString *s) {
 if (directBusy) return;
 directBusy=true;
 ++directCount;
 recordLine(s);
 directBusy=false;
}
static void *hookHint(void *self,const void *method) {
 void *r=((void *(*)(void *,const void *))origHint)(self,method);
 directLog([NSString stringWithFormat:@"VT4 HINT result=%p",r]);
 return r;
}
static void *hookFind(void *self,void *list,const void *method) {
 void *r=((void *(*)(void *,void *,const void *))origFind)(self,list,method);
 directLog([NSString stringWithFormat:@"VT4 FIND_PAIR list=%p result=%p",list,r]);
 return r;
}
static void hookPerform(void *self,void *a,void *b,void *c,void *d,const void *method) {
 directLog([NSString stringWithFormat:@"VT4 PERFORM_BEGIN self=%p a=%p b=%p c=%p d=%p",self,a,b,c,d]);
 ((void (*)(void *,void *,void *,void *,void *,const void *))origPerform)(self,a,b,c,d,method);
 directLog(@"VT4 PERFORM_RETURN");
}
static bool hookProducer(void *self,const void *method) {
 bool r=((bool (*)(void *,const void *))origProducer)(self,method);
 directLog([NSString stringWithFormat:@"VT4 PRODUCER result=%d tile=%p",(int)r,self]);
 return r;
}
static bool hookSpawner(void *self,const void *method) {
 bool r=((bool (*)(void *,const void *))origSpawner)(self,method);
 directLog([NSString stringWithFormat:@"VT4 SPAWNER result=%d tile=%p",(int)r,self]);
 return r;
}
static int hookBet(void *self,const void *method) {
 int r=((int (*)(void *,const void *))origBet)(self,method);
 static std::atomic<int> last(-9999);
 if (last.exchange(r)!=r) directLog([NSString stringWithFormat:@"VT4 SELECTED_BET=%d",r]);
 return r;
}
static void *resolveSymbol(void *handle,const char *name) {
 void *p=handle?dlsym(handle,name):nullptr;
 return p?p:dlsym(RTLD_DEFAULT,name);
}
static bool installDirect(void *handle) {
 DomainGetFn domain=(DomainGetFn)resolveSymbol(handle,"il2cpp_domain_get");
 DomainAssembliesFn assemblies=(DomainAssembliesFn)resolveSymbol(handle,"il2cpp_domain_get_assemblies");
 AssemblyImageFn image=(AssemblyImageFn)resolveSymbol(handle,"il2cpp_assembly_get_image");
 ImageNameFn imageName=(ImageNameFn)resolveSymbol(handle,"il2cpp_image_get_name");
 ClassFromNameFn klass=(ClassFromNameFn)resolveSymbol(handle,"il2cpp_class_from_name");
 ClassMethodFn method=(ClassMethodFn)resolveSymbol(handle,"il2cpp_class_get_method_from_name");
 if (!domain||!assemblies||!image||!imageName||!klass||!method) {
  recordLine(@"VT4 RESOLVE_API_MISSING"); return false;
 }
 void *d=domain(); if (!d) return false;
 size_t count=0;const void **arr=assemblies(d,&count);
 if (!arr||!count||count>4096) return false;
 struct Target {const char *ns,*cl,*name;int argc;void *replacement;void **original;};
 Target targets[]={
  {"MoonActive.Minigame.Merge.Hint","MergeMinigameHintHandler","GetHintSuggestion",0,(void *)hookHint,&origHint},
  {"MoonActive.Minigame.Merge.Hint","MergeMinigameHintHandler","FindFirstValidMergeSuggestion",1,(void *)hookFind,&origFind},
  {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameBoardOperationsHandler","PerformMerge",4,(void *)hookPerform,&origPerform},
  {"MoonActive.Minigame.Merge.UI.Board","MergeMinigameBoardTileView","TryTriggerProducerTap",0,(void *)hookProducer,&origProducer},
  {"MoonActive.Minigame.Merge.UI.Board","MergeMinigameBoardTileView","TryTriggerClickSpawnerTap",0,(void *)hookSpawner,&origSpawner},
  {"MoonActive.Minigame.Merge.Common.Data","MergeMinigameBetDataModel","get_SelectedBet",0,(void *)hookBet,&origBet}
 };
 int found=0;
 for (Target &t:targets) {
  if (*t.original) continue;
  for(size_t i=0;i<count;i++) {
   void *img=image(arr[i]); if(!img) continue;
   void *cl=klass(img,t.ns,t.cl); if(!cl) continue;
   const void *mi=method(cl,t.name,t.argc); if(!mi) continue;
   void *address=*(void *const *)mi;
   if (!address) continue;
   recordLine([NSString stringWithFormat:@"VT4 FOUND %s address=%p",t.name,address]);
   if (DobbyHook(address,t.replacement,t.original)==0 && *t.original) {
    directHooks.fetch_add(1);
    recordLine([NSString stringWithFormat:@"VT4 HOOK_OK %s",t.name]);
   } else recordLine([NSString stringWithFormat:@"VT4 HOOK_FAIL %s",t.name]);
   found++;break;
  }
 }
 return found>0;
}
static void attemptInstall(void) {
 if (directHooks.load()>=6 && ready.load()) return;
 void *handle=dlopen("@rpath/UnityFramework.framework/UnityFramework",RTLD_NOW|RTLD_NOLOAD);
 if (!handle) handle=dlopen(nullptr,RTLD_NOW);
 if (!handle) return;
 installDirect(handle);
 void *invoke=dlsym(handle,"il2cpp_runtime_invoke");
 if (!invoke) invoke=dlsym(RTLD_DEFAULT,"il2cpp_runtime_invoke");
 if (!invoke || ready.load()) return;
 methodName=(NameFn)dlsym(handle,"il2cpp_method_get_name");
 methodClass=(ClassFn)dlsym(handle,"il2cpp_method_get_class");
 className=(NameFn)dlsym(handle,"il2cpp_class_get_name");
 classNamespace=(NamespaceFn)dlsym(handle,"il2cpp_class_get_namespace");
 if (!methodName || !methodClass || !className || !classNamespace) return;
 if (DobbyHook(invoke,(void *)tracedInvoke,(void **)&originalInvoke)==0) {
  ready.store(true); recordLine([NSString stringWithFormat:@"VTTRACE HOOK_READY target=%p",invoke]);
 }
}
__attribute__((constructor)) static void initializeTrace(void) {
 traceQueue=dispatch_queue_create("vt.trace.queue",DISPATCH_QUEUE_SERIAL);
 recordLine(@"VTTRACE INIT");
 startButtonRetry();
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
  for (int i=0;i<90 && directHooks.load()<6;i++) { attemptInstall(); [NSThread sleepForTimeInterval:1.0]; }
  recordLine([NSString stringWithFormat:@"VT4 INSTALL_DONE directHooks=%d",directHooks.load()]);
 });
}

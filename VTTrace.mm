#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
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
static std::atomic<unsigned long long> vtTapSequence(0);
static std::atomic<unsigned long long> vtObservedLevel5(0),vtTileTransitions(0);
static std::atomic<int> vtLastBet(-1);
static std::atomic<unsigned long long> vtProductionInvokeCount(0);
static std::atomic<double> vtProductionWindowUntil(0);
static std::atomic<int> directHooks(0);
static std::atomic<int> pointerHooks(0);
static std::atomic<unsigned long long> vtSequence(0), vtFindCalls(0), vtFindHits(0), vtMergeCalls(0), vtProducerCalls(0), vtSpawnerCalls(0);
static std::atomic<unsigned long long> vtLastPairSeq(0);
static std::atomic<unsigned long long> vtProducerSuccess(0),vtSpawnerSuccess(0),vtProducerRejected(0),vtSpawnerRejected(0),vtHintHits(0);
static std::atomic<unsigned long long> vtLastPairId(0);
static std::atomic<double> vtLastPairTime(0);
static std::atomic<unsigned long long> vtSetItemCalls(0),vtLevelCalls(0);
static std::atomic<unsigned long long> vtCurrentItemCalls(0),vtSelectCalls(0),vtBoardMergeCalls(0);
static std::atomic<unsigned long long> vtBoardSpawnCalls(0);
static NSMutableString *traceBuffer;
static dispatch_queue_t traceQueue;
static bool interesting(const char *name) {
 if (!name) return false;
 const char *words[]={"Merge","Producer","Spawner","Hint","Bet","Power","Energy","CreateItem","SpawnItem","IndexInChain","ChainId","Generate","Probability","Random","Cost","Consume","Reward","Output","Select","ItemLevel","ChainItem","Spend","Currency"};
 for (const char *w:words) if (strstr(name,w)) return true;
 return false;
}
static void recordLine(NSString *line) {
 if (!traceQueue || !line) return;
 dispatch_async(traceQueue, ^{
  if (!traceBuffer) traceBuffer=[NSMutableString new];
  [traceBuffer appendFormat:@"%@\n",line];
  if (traceBuffer.length>420000) [traceBuffer deleteCharactersInRange:NSMakeRange(0,traceBuffer.length-340000)];
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
 if (watch) { ++vtProductionInvokeCount; recordLine([NSString stringWithFormat:@"VT16 INVOKE time=%.3f method=%@ obj=%p ret=%p exception=%d tapId=%llu bet=%d",CFAbsoluteTimeGetCurrent(),label,obj,result,(exception&&*exception)?1:0,vtTapSequence.load(),vtLastBet.load()]); }
 --depth;
 return result;
}
@interface VTTraceButton : UIButton
@end
@implementation VTTraceButton
- (void)copyTrace {
 dispatch_async(traceQueue, ^{
  NSString *content=[NSString stringWithFormat:@"VTTRACE V21 invoke=%llu filtered=%llu hook=%d direct=%llu directHooks=%d pointerHooks=%d find=%llu hits=%llu merge=%llu producer=%llu spawner=%llu producerOk=%llu producerZero=%llu spawnerOk=%llu spawnerZero=%llu hintHits=%llu setItem=%llu itemLevel=%llu currentItem=%llu spawnSelect=%llu boardMerge=%llu boardSpawn=%llu level5Observed=%llu tileTransitions=%llu energy=UNVERIFIED fieldWrites=%llu fieldReads=%llu\n%@",invokeCount.load(),filteredCount.load(),ready.load()?1:0,directCount.load(),directHooks.load(),pointerHooks.load(),vtFindCalls.load(),vtFindHits.load(),vtMergeCalls.load(),vtProducerCalls.load(),vtSpawnerCalls.load(),vtProducerSuccess.load(),vtProducerRejected.load(),vtSpawnerSuccess.load(),vtSpawnerRejected.load(),vtHintHits.load(),vtSetItemCalls.load(),vtLevelCalls.load(),vtCurrentItemCalls.load(),vtSelectCalls.load(),vtBoardMergeCalls.load(),vtBoardSpawnCalls.load(),vtObservedLevel5.load(),vtTileTransitions.load(),vtFieldWrites.load(),vtFieldReads.load(),[traceBuffer copy]?:@"VTTRACE EMPTY"];
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
   recordLine([NSString stringWithFormat:@"VTTRACE HEARTBEAT invoke=%llu filtered=%llu hook=%d direct=%llu directHooks=%d pointerHooks=%d find=%llu hits=%llu merge=%llu producer=%llu spawner=%llu",invokeCount.load(),filteredCount.load(),ready.load()?1:0,directCount.load(),directHooks.load(),pointerHooks.load(),vtFindCalls.load(),vtFindHits.load(),vtMergeCalls.load(),vtProducerCalls.load(),vtSpawnerCalls.load()]);
  }];
 });
}

typedef void *(*DomainGetFn)(void);
typedef const void **(*DomainAssembliesFn)(void *,size_t *);
typedef void *(*AssemblyImageFn)(const void *);
typedef const char *(*ImageNameFn)(const void *);
typedef void *(*ClassFromNameFn)(const void *,const char *,const char *);
typedef const void *(*ClassMethodFn)(void *,const char *,int);
typedef void *(*ObjectClassFn)(const void *);
typedef const void *(*FieldFromNameFn)(void *,const char *);
typedef size_t (*FieldOffsetFn)(const void *);
static ObjectClassFn vtObjectClass=nullptr;
static FieldFromNameFn vtFieldFromName=nullptr;
static FieldOffsetFn vtFieldOffset=nullptr;
static void *vtItemClass=nullptr;
static size_t vtChainOffset=SIZE_MAX,vtIndexOffset=SIZE_MAX;
static void recordLine(NSString *line);
static double vtTime(void) { return CFAbsoluteTimeGetCurrent(); }
static void vtEvent(NSString *name, NSString *details) {
 unsigned long long seq=++vtSequence;
 recordLine([NSString stringWithFormat:@"VT15 EVENT seq=%llu time=%.3f name=%@ %@",seq,vtTime(),name,details?:@""]);
}

static bool vtReadable(const void *ptr,size_t length) {
 if (!ptr || length==0) return false;
 vm_address_t address=(vm_address_t)ptr;
 vm_address_t region=address;
 vm_size_t size=0;
 vm_region_basic_info_data_64_t info={};
 mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;
 mach_port_t object=0;
 if (vm_region_64(mach_task_self(),&region,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object)!=KERN_SUCCESS) return false;
 return region<=address && size>=length && address-region<=size-length && (info.protection&VM_PROT_READ);
}
static NSString *vtDescribeObject(const char *label,void *ptr) {
 if (!vtReadable(ptr,sizeof(void *)) || !vtItemClass) return [NSString stringWithFormat:@"%s=%p(unclassified)",label,ptr];
 void *cl=nullptr;
 memcpy(&cl,ptr,sizeof(cl));
 if (cl!=vtItemClass) return [NSString stringWithFormat:@"%s=%p(not_item)",label,ptr];
 if (vtChainOffset==SIZE_MAX || vtIndexOffset==SIZE_MAX || vtChainOffset>4096 || vtIndexOffset>4096) return [NSString stringWithFormat:@"%s=%p(item_fields_missing)",label,ptr];
 if (!vtReadable((char *)ptr+vtChainOffset,sizeof(int32_t)) || !vtReadable((char *)ptr+vtIndexOffset,sizeof(int32_t))) return [NSString stringWithFormat:@"%s=%p(item_unreadable)",label,ptr];
 int32_t chain=0,index=0;
 memcpy(&chain,(char *)ptr+vtChainOffset,sizeof(chain));
 memcpy(&index,(char *)ptr+vtIndexOffset,sizeof(index));
 return [NSString stringWithFormat:@"%s=%p itemChain=%d itemIndex=%d nextIndexIfMerged=%d",label,ptr,chain,index,index+1];
}
static void vtDescribeMergeArgs(const char *stage,void *a,void *b,void *c,void *d) {
 recordLine([NSString stringWithFormat:@"VT15 %s bet=%d %@ | %@ | %@ | %@",stage,vtLastBet.load(),vtDescribeObject("a",a),vtDescribeObject("b",b),vtDescribeObject("c",c),vtDescribeObject("d",d)]);
}
static std::atomic<double> vtLastTapTime(0);
static std::atomic<int> vtLastTapBet(-1);
static NSMutableDictionary *vtTileStates;
static dispatch_queue_t vtTileQueue;
static void *origHint=nullptr,*origFind=nullptr,*origPerform=nullptr,*origProducer=nullptr,*origSpawner=nullptr,*origBet=nullptr;
static void *hookHint(void *self,const void *method) {
 ++directCount;
 void *r=((void *(*)(void *,const void *))origHint)(self,method);
 if (r) { ++vtHintHits; if (vtHintHits.load()<=5 || vtHintHits.load()%50==0) vtEvent(@"HINT_FOUND_SAMPLE",[NSString stringWithFormat:@"result=%p",r]);
 } return r;
}
static void *hookFind(void *self,void *list,const void *method) {
 ++directCount;
 void *r=((void *(*)(void *,void *,const void *))origFind)(self,list,method);
 unsigned long long n=++vtFindCalls;
 if (r) { ++vtFindHits; vtLastPairSeq.store(vtSequence.load()); vtLastPairId.store(n); vtLastPairTime.store(vtTime()); vtEvent(@"PAIR_FOUND",[NSString stringWithFormat:@"list=%p result=%p bet=%d",list,r,vtLastBet.load()]); }
 else if (n==1 || n%30==0) vtEvent(@"SCAN_NO_PAIR_SAMPLE",[NSString stringWithFormat:@"findCalls=%llu found=%llu list=%p",n,vtFindHits.load(),list]);
 return r;
}
static void hookPerform(void *self,void *a,void *b,void *c,void *d,const void *method) {
 ++directCount;
 unsigned long long mergeId=++vtMergeCalls;
 vtEvent(@"MERGE_REQUEST",[NSString stringWithFormat:@"id=%llu pairFind=%llu pairAgeMs=%.1f bet=%d self=%p a=%p b=%p c=%p d=%p",mergeId,vtLastPairId.load(),(vtLastPairId.load()? (vtTime()-vtLastPairTime.load())*1000.0 : -1.0),vtLastBet.load(),self,a,b,c,d]);
 vtDescribeMergeArgs("MERGE_ARGS_BEFORE",a,b,c,d);
 ((void (*)(void *,void *,void *,void *,void *,const void *))origPerform)(self,a,b,c,d,method);
 vtDescribeMergeArgs("MERGE_ARGS_AFTER",a,b,c,d);
 vtEvent(@"MERGE_RETURN_UNCONFIRMED",[NSString stringWithFormat:@"id=%llu bet=%d",mergeId,vtLastBet.load()]);
}
static bool hookProducer(void *self,const void *method) {
 ++directCount;
unsigned long long tapId=++vtTapSequence;
 vtLastTapTime.store(vtTime());
 vtLastTapBet.store(vtLastBet.load());
 vtProductionWindowUntil.store(vtTime()+2.0);
 vtEvent(@"PRODUCER_TAP_BEFORE",[NSString stringWithFormat:@"tapId=%llu tile=%p selectedBet=%d",tapId,self,vtLastBet.load()]);
 bool r=((bool (*)(void *,const void *))origProducer)(self,method);
 vtEvent(@"PRODUCER_TAP_AFTER",[NSString stringWithFormat:@"tapId=%llu tile=%p betBefore=%d betAfter=%d return=%d returnMeaningUnconfirmed=1 energyUnverified=1 level5Observed=%llu tileTransitions=%llu",tapId,self,vtLastTapBet.load(),vtLastBet.load(),(int)r,vtObservedLevel5.load(),vtTileTransitions.load()]);
 unsigned long long n=++vtProducerCalls;
 if (r) { ++vtProducerSuccess; vtEvent(@"PRODUCER_ACCEPTED_UNCONFIRMED",[NSString stringWithFormat:@"tile=%p bet=%d call=%llu",self,vtLastBet.load(),n]); }
 else { unsigned long long zero=++vtProducerRejected; if (zero==1 || zero%500==0) vtEvent(@"PRODUCER_ZERO_SUMMARY",[NSString stringWithFormat:@"zero=%llu calls=%llu accepted=%llu bet=%d",zero,n,vtProducerSuccess.load(),vtLastBet.load()]); }
 return r;
}
static bool hookSpawner(void *self,const void *method) {
 ++directCount;
 bool r=((bool (*)(void *,const void *))origSpawner)(self,method);
 unsigned long long n=++vtSpawnerCalls;
 if (r) { ++vtSpawnerSuccess; vtEvent(@"SPAWNER_ACCEPTED_UNCONFIRMED",[NSString stringWithFormat:@"tile=%p bet=%d call=%llu",self,vtLastBet.load(),n]); }
 else { unsigned long long zero=++vtSpawnerRejected; if (zero==1 || zero%100==0) vtEvent(@"SPAWNER_ZERO_SUMMARY",[NSString stringWithFormat:@"zero=%llu calls=%llu accepted=%llu bet=%d",zero,n,vtSpawnerSuccess.load(),vtLastBet.load()]); }
 return r;
}
static int hookBet(void *self,const void *method) {
 ++directCount;
 int r=((int (*)(void *,const void *))origBet)(self,method);
 static std::atomic<int> last(-9999);
 vtLastBet.store(r);
 if (last.exchange(r)!=r) vtEvent(@"BET_OBSERVED",[NSString stringWithFormat:@"bet=%d",r]);
 return r;
}
static void *origItemLevel=nullptr,*origSetItem=nullptr;
static int hookItemLevel(void *self,const void *method) {
 ++directCount;
 int level=((int (*)(void *,const void *))origItemLevel)(self,method);
 unsigned long long n=++vtLevelCalls;
 static std::atomic<int> lastLevel(-99999),lastBet(-99999);
 int bet=vtLastBet.load();
 if (lastLevel.exchange(level)!=level || lastBet.exchange(bet)!=bet || n%200==0)
  vtEvent(@"ITEM_LEVEL_OBSERVED",[NSString stringWithFormat:@"level=%d bet=%d model=%p calls=%llu",level,bet,self,n]);
 return level;
}
static bool vtHasIndexFive(void *p) {
 if (!p || !vtItemClass || vtChainOffset==SIZE_MAX || vtIndexOffset==SIZE_MAX || vtIndexOffset>4096 || vtChainOffset>4096) return false;
 if (!vtReadable(p,sizeof(void *)) || !vtReadable((char *)p+vtIndexOffset,sizeof(int32_t))) return false;
 void *cl=nullptr; memcpy(&cl,p,sizeof(cl)); if (cl!=vtItemClass) return false;
 int32_t index=0; memcpy(&index,(char *)p+vtIndexOffset,sizeof(index)); return index==5;
}
static void hookSetItem(void *self,void *a,void *b,void *c,void *d,const void *method) {
 ++directCount;
 unsigned long long n=++vtSetItemCalls;
 bool targetLevel5=vtHasIndexFive(a)||vtHasIndexFive(b)||vtHasIndexFive(c)||vtHasIndexFive(d);
 if(targetLevel5) { ++vtObservedLevel5; vtEvent(@"LEVEL5_SETITEM_ENTRY",[NSString stringWithFormat:@"tile=%p bet=%d tapId=%llu tapAgeMs=%.1f a=%@ b=%@ c=%@ d=%@",self,vtLastBet.load(),vtTapSequence.load(),(vtTime()-vtLastTapTime.load())*1000.0,vtDescribeObject("a",a),vtDescribeObject("b",b),vtDescribeObject("c",c),vtDescribeObject("d",d)]); }
 if(n<=200 || n%100==0)
  vtEvent(@"SET_ITEM_BEFORE",[NSString stringWithFormat:@"id=%llu tile=%p bet=%d a=%@ b=%@ c=%@ d=%@",n,self,vtLastBet.load(),vtDescribeObject("a",a),vtDescribeObject("b",b),vtDescribeObject("c",c),vtDescribeObject("d",d)]);
 ((void (*)(void *,void *,void *,void *,void *,const void *))origSetItem)(self,a,b,c,d,method);
 if(n<=200 || n%100==0)
  vtEvent(@"SET_ITEM_AFTER",[NSString stringWithFormat:@"id=%llu tile=%p bet=%d a=%@ b=%@ c=%@ d=%@",n,self,vtLastBet.load(),vtDescribeObject("a",a),vtDescribeObject("b",b),vtDescribeObject("c",c),vtDescribeObject("d",d)]);
}
static void *origCurrentItem=nullptr,*origSelectSpawnable=nullptr,*origBoardMerge=nullptr;
static void *hookCurrentItem(void *self,const void *method) {
 ++directCount;
 void *item=((void *(*)(void *,const void *))origCurrentItem)(self,method);
 ++vtCurrentItemCalls;
 if (!vtTileQueue) return item;
 NSString *key=[NSString stringWithFormat:@"%p",self];
 NSString *state=vtDescribeObject("item",item);
 dispatch_sync(vtTileQueue, ^{
  if (!vtTileStates) vtTileStates=[NSMutableDictionary new];
  NSString *old=vtTileStates[key];
  if (!old || ![old isEqualToString:state]) {
   vtTileStates[key]=state;
   double age=(vtTime()-vtLastTapTime.load())*1000.0;
   if (old || vtHasIndexFive(item)) { if(old) ++vtTileTransitions; if(vtHasIndexFive(item)) ++vtObservedLevel5; vtEvent(old?@"TILE_ITEM_CHANGED":@"TILE_ITEM_FIRST_SEEN",[NSString stringWithFormat:@"tile=%p bet=%d tapId=%llu tapBet=%d tapAgeMs=%.1f before=%@ after=%@",self,vtLastBet.load(),vtTapSequence.load(),vtLastTapBet.load(),age,old?:@"(unknown)",state]); }
  }
 });
 return item;
}
static void *hookSelectSpawnable(void *self,void *items,const void *method) {
 ++directCount;
 void *result=((void *(*)(void *,void *,const void *))origSelectSpawnable)(self,items,method);
 unsigned long long n=++vtSelectCalls;
 if (n<=100 || n%100==0) vtEvent(@"SPAWN_SELECTION",[NSString stringWithFormat:@"handler=%p bet=%d input=%p selected=%p call=%llu",self,vtLastBet.load(),items,result,n]);
 return result;
}
static void hookBoardMerge(void *self,void *source,void *target,int a,int b,const void *method) {
 ++directCount;
 unsigned long long n=++vtBoardMergeCalls;
 if (n<=100 || n%100==0) vtEvent(@"BOARD_MERGE_WRITE",[NSString stringWithFormat:@"handler=%p bet=%d source=%p target=%p valueA=%d valueB=%d call=%llu",self,vtLastBet.load(),source,target,a,b,n]);
 ((void (*)(void *,void *,void *,int,int,const void *))origBoardMerge)(self,source,target,a,b,method);
}
static void *origBoardSpawn=nullptr;
struct VTVector2Int { int32_t x; int32_t y; };
struct VTNullableCellType { int32_t value; uint8_t hasValue; uint8_t padding[3]; };
static void hookBoardSpawn(void *self,VTVector2Int pos,int32_t a,int32_t b,VTNullableCellType cellType,void *additional,const void *method) {
 ++directCount;
 unsigned long long n=++vtBoardSpawnCalls;
 if (n<=200 || n%100==0 || (a==0 && b==5) || (a==5 && b==0))
  vtEvent(@"BOARD_SPAWN_ENTRY",[NSString stringWithFormat:@"call=%llu handler=%p posX=%d posY=%d arg1=%d arg2=%d cellType=%d cellTypePresent=%d additional=%p bet=%d tapId=%llu tapAgeMs=%.1f",n,self,pos.x,pos.y,a,b,cellType.value,(int)cellType.hasValue,additional,vtLastBet.load(),vtTapSequence.load(),(vtTime()-vtLastTapTime.load())*1000.0]);
 ((void (*)(void *,VTVector2Int,int32_t,int32_t,VTNullableCellType,void *,const void *))origBoardSpawn)(self,pos,a,b,cellType,additional,method);
}
static void *resolveSymbol(void *handle,const char *name) {
 void *p=handle?dlsym(handle,name):nullptr;
 return p?p:dlsym(RTLD_DEFAULT,name);
}
static bool replaceMethodPointer(const void *methodInfo, void *replacement, void **original) {
 if (!methodInfo || !replacement || !original) return false;
 void **slot=(void **)methodInfo;
 void *previous=*slot;
 if (!previous || previous==replacement) return false;
 vm_address_t page=(vm_address_t)slot & ~((vm_address_t)vm_page_size-1);
 vm_size_t span=vm_page_size;
 vm_region_basic_info_data_64_t info={};
 mach_msg_type_number_t infoCount=VM_REGION_BASIC_INFO_COUNT_64;
 mach_port_t object=0;
 vm_address_t region=page;
 vm_size_t regionSize=0;
 kern_return_t kr=vm_region_64(mach_task_self(),&region,&regionSize,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&infoCount,&object);
 if (kr!=KERN_SUCCESS || page<region || page>=region+regionSize) return false;
 vm_prot_t oldProtection=info.protection;
 if (!(oldProtection&VM_PROT_WRITE)) {
  kr=vm_protect(mach_task_self(),page,span,false,oldProtection|VM_PROT_WRITE);
  if (kr!=KERN_SUCCESS) return false;
 }
 *original=previous;
 __atomic_store_n(slot,replacement,__ATOMIC_RELEASE);
 bool ok=(*slot==replacement);
 if (!(oldProtection&VM_PROT_WRITE)) vm_protect(mach_task_self(),page,span,false,oldProtection);
 if (!ok) *original=nullptr;
 return ok;
}
static std::atomic<bool> vtProductionDiscoveryDone(false);
static void vtDiscoverProductionMethods(void *handle,const void **arr,size_t count,AssemblyImageFn image,ClassFromNameFn klass) {
 if (vtProductionDiscoveryDone.exchange(true)) return;
 typedef void *(*MethodIterFn)(void *,void **);
 typedef const char *(*MethodGetNameFn)(const void *);
 typedef unsigned int (*MethodParamCountFn)(const void *);
 typedef const void *(*MethodParamFn)(const void *,uint32_t);
 typedef const void *(*MethodReturnFn)(const void *);
 typedef char *(*TypeNameFn)(const void *);
 typedef void (*FreeFn)(void *);
  MethodIterFn iter=(MethodIterFn)resolveSymbol(handle,"il2cpp_class_get_methods");
 MethodGetNameFn getName=(MethodGetNameFn)resolveSymbol(handle,"il2cpp_method_get_name");
 MethodParamCountFn argc=(MethodParamCountFn)resolveSymbol(handle,"il2cpp_method_get_param_count");
 MethodParamFn param=(MethodParamFn)resolveSymbol(handle,"il2cpp_method_get_param");
 MethodReturnFn ret=(MethodReturnFn)resolveSymbol(handle,"il2cpp_method_get_return_type");
 TypeNameFn typeName=(TypeNameFn)resolveSymbol(handle,"il2cpp_type_get_name");
 FreeFn freeName=(FreeFn)resolveSymbol(handle,"il2cpp_free");
 if (!iter||!getName||!argc) {recordLine(@"VT15 PRODUCTION_DISCOVERY_API_MISSING");return;}
 struct Candidate {const char *ns,*cl;};
 Candidate candidates[]={
 {"MoonActive.Minigame.Merge.UI.Board","MergeMinigameBoardTileView"},
 {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameBoardOperationsHandler"},
 {"MoonActive.Minigame.Merge.Common.Data","MergeMinigameBetDataModel"},
 {"MoonActive.Minigame.Merge.Hint","MergeMinigameHintHandler"},
 {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameProducerItem"},
 {"MoonActive.Minigame.Merge.UI.Items.Behaviors","MergeMinigameProducerBehavior"},
 {"MoonActive.Minigame.Merge.Common.Data","MergeMinigameItem"},
 {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameItem"}
 };
 for (const Candidate &c:candidates) {
  void *cl=nullptr;
  for(size_t i=0;i<count&&!cl;i++){void *img=image(arr[i]);if(img)cl=klass(img,c.ns,c.cl);}
  if(!cl){recordLine([NSString stringWithFormat:@"VT15 CLASS_MISSING %s.%s",c.ns,c.cl]);continue;}
  void *it=nullptr;unsigned total=0,selected=0;
  while(const void *mi=iter(cl,&it)){
   if(++total>500)break;
   const char *name=getName(mi);if(!name)continue;
   bool match=false;
   const char *keys[]={"Produce","Spawn","Create","Energy","Power","Bet","Tap","Click","Item","Merge","Reward","Cost","Consume","Multiplier","Max","Random","Probability","Select","Generate","Output"};
   for(const char *key:keys)if(strstr(name,key)){match=true;break;}
   if(!match)continue;
   recordLine([NSString stringWithFormat:@"VT16 PRODUCTION_METHOD class=%s name=%s argc=%u method=%p",c.cl,name,argc(mi),mi]);
   selected++;
   bool focus=(!strcmp(c.cl,"MergeMinigameBoardOperationsHandler") && (strstr(name,"Spawn")||strstr(name,"Merge")||strstr(name,"Energy"))) || (!strcmp(c.cl,"MergeMinigameBetDataModel") && (strstr(name,"Level")||strstr(name,"Bet")));
   if (focus && param && ret && typeName) {
    NSMutableString *sig=[NSMutableString stringWithFormat:@"VT16 SIGNATURE class=%s name=%s argc=%u",c.cl,name,argc(mi)];
    const void *rt=ret(mi);
    if(rt){char *tn=typeName(rt);if(tn){[sig appendFormat:@" return=%s",tn];if(freeName)freeName(tn);}}
    unsigned n=argc(mi);
    for(unsigned j=0;j<n && j<16;j++){
     const void *pt=param(mi,j);if(!pt)continue;
     char *tn=typeName(pt);if(tn){[sig appendFormat:@" arg%u=%s",j,tn];if(freeName)freeName(tn);}
    }
    recordLine(sig);
   }
  }
  recordLine([NSString stringWithFormat:@"VT16 PRODUCTION_CLASS_SUMMARY class=%s total=%u selected=%u",c.cl,total,selected]);
 }
 recordLine(@"VT16 PRODUCTION_DISCOVERY_DONE read_only=1");
}
static NSString *vtListSnapshot(void *list) {
 if (!vtReadable(list,40)) return [NSString stringWithFormat:@"list=%p unreadable",list];
 void *array=nullptr;
 int32_t count=-1;
 memcpy(&array,(char *)list+16,sizeof(array));
 memcpy(&count,(char *)list+24,sizeof(count));
 if (count<0 || count>4096) return [NSString stringWithFormat:@"list=%p size_invalid=%d",list,count];
 NSMutableString *out=[NSMutableString stringWithFormat:@"list=%p count=%d array=%p",list,count,array];
 if (array && vtReadable(array,32)) {
  int32_t capacity=-1;
  memcpy(&capacity,(char *)array+24,sizeof(capacity));
  [out appendFormat:@" capacity=%d",capacity];
  if (capacity>=count && capacity<=4096) {
   for (int i=0;i<count && i<8;i++) {
    void *entry=nullptr;
    if (!vtReadable((char *)array+32+i*sizeof(void *),sizeof(entry))) break;
    memcpy(&entry,(char *)array+32+i*sizeof(void *),sizeof(entry));
    [out appendFormat:@" entry%d=%p",i,entry];
   }
  }
 }
 return out;
}
static void *vtOrigWeighted=nullptr,*vtOrigIndependent=nullptr,*vtOrigProducerClick=nullptr;
static std::atomic<int> vtV17Installed(0);
static std::atomic<unsigned long long> vtWeightedCount(0),vtIndependentCount(0),vtClickCount(0);
static void *vtWeightedHook(void *self,void *items,const void *mi) {
 unsigned long long n=++vtWeightedCount;
 vtEvent(@"V17_WEIGHTED_ENTER",[NSString stringWithFormat:@"n=%llu handler=%p input=%@ bet=%d tap=%llu",n,self,vtListSnapshot(items),vtLastBet.load(),vtTapSequence.load()]);
 void *result=((void *(*)(void *,void *,const void *))vtOrigWeighted)(self,items,mi);
 vtEvent(@"V17_WEIGHTED_EXIT",[NSString stringWithFormat:@"n=%llu output=%@ bet=%d",n,vtListSnapshot(result),vtLastBet.load()]);
 return result;
}
static void *vtIndependentHook(void *self,void *items,const void *mi) {
 unsigned long long n=++vtIndependentCount;
 vtEvent(@"V17_INDEPENDENT_ENTER",[NSString stringWithFormat:@"n=%llu handler=%p input=%@ bet=%d tap=%llu",n,self,vtListSnapshot(items),vtLastBet.load(),vtTapSequence.load()]);
 void *result=((void *(*)(void *,void *,const void *))vtOrigIndependent)(self,items,mi);
 vtEvent(@"V17_INDEPENDENT_EXIT",[NSString stringWithFormat:@"n=%llu output=%@ bet=%d",n,vtListSnapshot(result),vtLastBet.load()]);
 return result;
}
static void vtClickHook(void *self,void *event,const void *mi) {
 unsigned long long n=++vtClickCount;
 vtEvent(@"V17_PRODUCER_CLICK",[NSString stringWithFormat:@"n=%llu behavior=%p event=%p bet=%d",n,self,event,vtLastBet.load()]);
 ((void (*)(void *,void *,const void *))vtOrigProducerClick)(self,event,mi);
}
static void *vtOrigFieldSetObject=nullptr,*vtOrigFieldGetObject=nullptr;
static std::atomic<unsigned long long> vtFieldWrites(0),vtFieldReads(0);
static thread_local bool vtFieldTraceBusy=false;
static void vtFieldSetObjectHook(void *a,void *b,void *c) {
 unsigned long long n=++vtFieldWrites;
 if (!vtFieldTraceBusy && (n<=100 || n%250==0)) {
  vtFieldTraceBusy=true;
  vtEvent(@"FIELD_SET_OBJECT",[NSString stringWithFormat:@"n=%llu arg0=%p arg1=%p arg2=%p bet=%d tap=%llu time=%.3f",n,a,b,c,vtLastBet.load(),vtTapSequence.load(),vtTime()]);
  vtFieldTraceBusy=false;
 }
 ((void (*)(void *,void *,void *))vtOrigFieldSetObject)(a,b,c);
}
static void *vtFieldGetObjectHook(void *a,void *b) {
 void *result=((void *(*)(void *,void *))vtOrigFieldGetObject)(a,b);
 unsigned long long n=++vtFieldReads;
 if (!vtFieldTraceBusy && (n<=100 || n%250==0)) {
  vtFieldTraceBusy=true;
  vtEvent(@"FIELD_GET_OBJECT",[NSString stringWithFormat:@"n=%llu arg0=%p arg1=%p result=%p bet=%d tap=%llu time=%.3f",n,a,b,result,vtLastBet.load(),vtTapSequence.load(),vtTime()]);
  vtFieldTraceBusy=false;
 }
 return result;
}
static void vtInstallFieldWatch(void *handle) {
 struct FieldTarget {const char *symbol;void *replacement;void **original;};
 FieldTarget targets[]={
  {"il2cpp_field_set_value_object",(void *)vtFieldSetObjectHook,&vtOrigFieldSetObject},
  {"il2cpp_field_get_value_object",(void *)vtFieldGetObjectHook,&vtOrigFieldGetObject}
 };
 for (FieldTarget &t:targets) {
  if (*t.original) continue;
  void *addr=dlsym(handle,t.symbol);
  if (!addr) addr=dlsym(RTLD_DEFAULT,t.symbol);
  if (!addr) { recordLine([NSString stringWithFormat:@"VT21 FIELD_SYMBOL_MISSING %s",t.symbol]); continue; }
  int rc=DobbyHook(addr,t.replacement,t.original);
  recordLine([NSString stringWithFormat:@"VT21 FIELD_HOOK name=%s address=%p result=%d original=%p",t.symbol,addr,rc,*t.original]);
 }
}
static void *vtOrigProducerItemClick=nullptr;
static void *vtOrigCurrentLevelNative=nullptr;
static std::atomic<unsigned long long> vtProducerItemClicks(0),vtNativeLevelCalls(0);
static void vtProducerItemClickHook(void *self,void *event,const void *mi) {
 unsigned long long n=++vtProducerItemClicks;
 vtEvent(@"V19_PRODUCER_ITEM_CLICK",[NSString stringWithFormat:@"n=%llu self=%p event=%p bet=%d",n,self,event,vtLastBet.load()]);
 ((void (*)(void *,void *,const void *))vtOrigProducerItemClick)(self,event,mi);
}
static int vtCurrentLevelNativeHook(void *self,const void *mi) {
 int value=((int (*)(void *,const void *))vtOrigCurrentLevelNative)(self,mi);
 unsigned long long n=++vtNativeLevelCalls;
 if (n<=50 || n%100==0) vtEvent(@"V19_BET_ITEM_LEVEL",[NSString stringWithFormat:@"n=%llu level=%d bet=%d model=%p",n,value,vtLastBet.load(),self]);
 return value;
}
static void vtInstallV17(const void **arr,size_t count,AssemblyImageFn image,ClassFromNameFn klass,ClassMethodFn method) {
 struct V17Target {const char *ns,*cl,*name;int argc;void *replacement;void **original;};
 V17Target targets[]={
  {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameBoardOperationsHandler","SelectItemsWithWeights",1,(void *)vtWeightedHook,&vtOrigWeighted},
  {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameBoardOperationsHandler","SelectItemsWithIndependentProbability",1,(void *)vtIndependentHook,&vtOrigIndependent},
  {"MoonActive.Minigame.Merge.UI.Items.Behaviors","MergeMinigameProducerBehavior","OnPointerClick",1,(void *)vtClickHook,&vtOrigProducerClick},
  {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameProducerItem","ItemClickedInternal",1,(void *)vtProducerItemClickHook,&vtOrigProducerItemClick},
  {"MoonActive.Minigame.Merge.Common.Data","MergeMinigameBetDataModel","get_CurrentItemLevel",0,(void *)vtCurrentLevelNativeHook,&vtOrigCurrentLevelNative}
 };
 for(V17Target &t:targets){
  if(*t.original)continue;
  for(size_t i=0;i<count;i++){
   void *img=image(arr[i]);if(!img)continue;
   void *cl=klass(img,t.ns,t.cl);if(!cl)continue;
   const void *mi=method(cl,t.name,t.argc);if(!mi)continue;
   void *address=*(void *const *)mi;
   if(!address)continue;
   int rc=DobbyHook(address,t.replacement,t.original);
   recordLine([NSString stringWithFormat:@"VT19 INLINE_HOOK name=%s address=%p result=%d original=%p",t.name,address,rc,*t.original]);
   if(rc==0 && *t.original)vtV17Installed.fetch_add(1);
   break;
  }
 }
}
static bool installDirect(void *handle) {
 DomainGetFn domain=(DomainGetFn)resolveSymbol(handle,"il2cpp_domain_get");
 DomainAssembliesFn assemblies=(DomainAssembliesFn)resolveSymbol(handle,"il2cpp_domain_get_assemblies");
 AssemblyImageFn image=(AssemblyImageFn)resolveSymbol(handle,"il2cpp_assembly_get_image");
 ImageNameFn imageName=(ImageNameFn)resolveSymbol(handle,"il2cpp_image_get_name");
 ClassFromNameFn klass=(ClassFromNameFn)resolveSymbol(handle,"il2cpp_class_from_name");
 ClassMethodFn method=(ClassMethodFn)resolveSymbol(handle,"il2cpp_class_get_method_from_name");
 vtObjectClass=(ObjectClassFn)resolveSymbol(handle,"il2cpp_object_get_class");
 vtFieldFromName=(FieldFromNameFn)resolveSymbol(handle,"il2cpp_class_get_field_from_name");
 vtFieldOffset=(FieldOffsetFn)resolveSymbol(handle,"il2cpp_field_get_offset");
 if (!domain||!assemblies||!image||!imageName||!klass||!method) {
  recordLine(@"VT15 RESOLVE_API_MISSING"); return false;
 }
 void *d=domain(); if (!d) return false;
 size_t count=0;const void **arr=assemblies(d,&count);
 if (!arr||!count||count>4096) return false;
 recordLine(@"VT18 PRODUCTION_ONLY_DISCOVERY");
 vtInstallV17(arr,count,image,klass,method);
 for (size_t i=0;i<count && !vtItemClass;i++) {
  void *img=image(arr[i]); if (!img) continue;
  vtItemClass=klass(img,"MoonActive.Minigame.Merge.UI.Items","MergeMinigameItem");
 }
 if (vtItemClass && vtFieldFromName && vtFieldOffset) {
  const void *chain=vtFieldFromName(vtItemClass,"m_ChainId");
  const void *index=vtFieldFromName(vtItemClass,"m_IndexInChain");
  if (chain) vtChainOffset=vtFieldOffset(chain);
  if (index) vtIndexOffset=vtFieldOffset(index);
  recordLine([NSString stringWithFormat:@"VT15 ITEM_FIELDS chainOffset=%zu indexOffset=%zu",vtChainOffset,vtIndexOffset]);
 } else recordLine(@"VT15 ITEM_FIELDS_UNAVAILABLE");
 struct Target {const char *ns,*cl,*name;int argc;void *replacement;void **original;};
 Target targets[]={
  {"MoonActive.Minigame.Merge.UI.Board","MergeMinigameBoardTileView","TryTriggerProducerTap",0,(void *)hookProducer,&origProducer},
  {"MoonActive.Minigame.Merge.Common.Data","MergeMinigameBetDataModel","get_SelectedBet",0,(void *)hookBet,&origBet},
  {"MoonActive.Minigame.Merge.UI.Board","MergeMinigameBoardTileView","SetItem",4,(void *)hookSetItem,&origSetItem},
  {"MoonActive.Minigame.Merge.UI.Board","MergeMinigameBoardTileView","get_CurrentItem",0,(void *)hookCurrentItem,&origCurrentItem},
  {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameBoardOperationsHandler","SelectSpawnableItems",1,(void *)hookSelectSpawnable,&origSelectSpawnable},
  {"MoonActive.Minigame.Merge.UI.Items","MergeMinigameBoardOperationsHandler","UpdateBoardDataForSpawn",5,(void *)hookBoardSpawn,&origBoardSpawn}
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
   recordLine([NSString stringWithFormat:@"VT15 FOUND %s address=%p",t.name,address]);
   if (replaceMethodPointer(mi,t.replacement,t.original)) {
    pointerHooks.fetch_add(1);
    directHooks.fetch_add(1);
    recordLine([NSString stringWithFormat:@"VT15 POINTER_HOOK_OK %s method=%p",t.name,mi]);
   } else {
    recordLine([NSString stringWithFormat:@"VT15 POINTER_HOOK_UNAVAILABLE %s method=%p",t.name,mi]);
    if (DobbyHook(address,t.replacement,t.original)==0 && *t.original) {
     directHooks.fetch_add(1);
     recordLine([NSString stringWithFormat:@"VT15 DOBBY_FALLBACK_OK %s",t.name]);
    } else recordLine([NSString stringWithFormat:@"VT15 DOBBY_FALLBACK_FAIL %s",t.name]);
   }
   if (*t.original) found++;
   break;
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
 vtInstallFieldWatch(handle);
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
 vtTileQueue=dispatch_queue_create("vt.tile.queue",DISPATCH_QUEUE_SERIAL);
 recordLine(@"VTTRACE V21 OBSERVE INIT");
 startButtonRetry();
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
  for (int i=0;i<90 && directHooks.load()<6;i++) { attemptInstall(); [NSThread sleepForTimeInterval:1.0]; }
  recordLine([NSString stringWithFormat:@"VT21 INSTALL_DONE directHooks=%d pointerHooks=%d inlineHooks=%d",directHooks.load(),pointerHooks.load(),vtV17Installed.load()]);
 });
}

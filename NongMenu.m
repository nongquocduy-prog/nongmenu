#import <UIKit/UIKit.h>

@interface MenuView : UIView
@property UILabel *title;
@property UIButton *zalo;
@property UIButton *skip;
@property UILabel *status;
@property BOOL skipOn;
@end

@implementation MenuView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {

        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        self.layer.cornerRadius = 15;

        // TITLE
        _title = [[UILabel alloc] initWithFrame:CGRectMake(10,10,f.size.width-60,30)];
        _title.text = @"ÔNG NÔNG";
        _title.textColor = UIColor.whiteColor;
        _title.font = [UIFont boldSystemFontOfSize:24];
        _title.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_title];

        // ZALO BUTTON
        _zalo = [UIButton buttonWithType:UIButtonTypeSystem];
        _zalo.frame = CGRectMake(f.size.width-45,8,35,35);
        [_zalo setTitle:@"Z" forState:UIControlStateNormal];
        [_zalo setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [_zalo addTarget:self action:@selector(openZalo) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_zalo];

        // SKIP BUTTON
        _skip = [UIButton buttonWithType:UIButtonTypeSystem];
        _skip.frame = CGRectMake(f.size.width-90,60,80,35);
        _skip.layer.cornerRadius = 8;
        _skip.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
        [_skip setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [_skip addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_skip];

        // STATUS
        _status = [[UILabel alloc] initWithFrame:CGRectMake(10,100,f.size.width-20,25)];
        _status.textColor = UIColor.whiteColor;
        _status.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_status];

        _skipOn = NO;
        [self update];
    }
    return self;
}

- (void)update {
    [_skip setTitle:(_skipOn?@"SKIP_ON":@"SKIP_OFF") forState:UIControlStateNormal];
    _status.text = _skipOn?@"Skip Enabled":@"Skip Disabled";
}

- (void)toggle {
    _skipOn = !_skipOn;
    [self update];
}

- (void)openZalo {
    NSURL *url = [NSURL URLWithString:@"https://zalo.me/g/nlflxw592"]; //
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

@end

// DRAG MENU
@interface Drag : NSObject
@end

@implementation Drag
- (void)pan:(UIPanGestureRecognizer*)g {
    UIView *v = g.view;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x+t.x, v.center.y+t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}
@end

// SHOW MENU
static void showMenu() {
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *w = UIApplication.sharedApplication.windows.firstObject;
        if (!w) return;

        MenuView *menu = [[MenuView alloc] initWithFrame:CGRectMake(50,120,250,140)];

        Drag *d = [Drag new];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:d action:@selector(pan:)];
        [menu addGestureRecognizer:pan];

        [w addSubview:menu];
    });
}

// ENTRY POINT
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        showMenu();
    });
}

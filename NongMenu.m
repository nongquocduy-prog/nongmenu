#import <UIKit/UIKit.h>

@interface MenuView : UIView
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UIButton *zalo;
@property (nonatomic, strong) UIButton *skip;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, assign) BOOL skipOn;
@end

@implementation MenuView

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(100, 100, 200, 150)];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.layer.cornerRadius = 10;

        _title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 200, 30)];
        _title.text = @"ÔNG NÔNG";
        _title.textColor = [UIColor whiteColor];
        _title.font = [UIFont boldSystemFontOfSize:20];
        _title.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_title];

        _zalo = [UIButton buttonWithType:UIButtonTypeSystem];
        _zalo.frame = CGRectMake(20, 50, 160, 30);
        [_zalo setTitle:@"Zalo" forState:UIControlStateNormal];
        [_zalo addTarget:self action:@selector(openZalo) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_zalo];

        _skip = [UIButton buttonWithType:UIButtonTypeSystem];
        _skip.frame = CGRectMake(20, 90, 160, 30);
        [_skip setTitle:@"Toggle Skip" forState:UIControlStateNormal];
        [_skip addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_skip];

        _status = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, 200, 20)];
        _status.textColor = [UIColor whiteColor];
        _status.textAlignment = NSTextAlignmentCenter;
        _status.text = @"Skip Disabled";
        [self addSubview:_status];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)drag:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}

- (void)toggle {
    _skipOn = !_skipOn;
    _status.text = _skipOn ? @"Skip Enabled" : @"Skip Disabled";
}

- (void)openZalo {
    NSURL *url = [NSURL URLWithString:@"https://zalo.me/g/nlflxw592"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

@end

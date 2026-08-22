#import "utility_mgr.hpp"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface AuroraDebugView : UIView
@property (nonatomic, strong) NSMutableArray<NSString *> *logs;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, strong) UIView *circle;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
+ (instancetype)shared;
- (void)log:(NSString *)msg;
@end

@implementation AuroraDebugView

+ (instancetype)shared {
    static AuroraDebugView *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AuroraDebugView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
        [instance setupView];
    });
    return instance;
}

- (void)setupView {
    self.backgroundColor = [UIColor clearColor];
    self.logs = [NSMutableArray array];
    self.expanded = NO;

    self.circle = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 40, 40)];
    self.circle.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.85];
    self.circle.layer.cornerRadius = 20;
    self.circle.layer.borderWidth = 1;
    self.circle.layer.borderColor = [UIColor whiteColor].CGColor;
    self.circle.userInteractionEnabled = YES;

    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.panGesture.cancelsTouchesInView = NO;
    [self.circle addGestureRecognizer:self.panGesture];

    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    self.tapGesture.cancelsTouchesInView = NO;
    [self.circle addGestureRecognizer:self.tapGesture];
    [self.tapGesture requireGestureRecognizerToFail:self.panGesture];

    [self addSubview:self.circle];

    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    self.logView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.9];
    self.logView.textColor = [UIColor greenColor];
    self.logView.font = [UIFont fontWithName:OBF_NS("Menlo") size:10];
    self.logView.editable = NO;
    self.logView.hidden = YES;
    [self addSubview:self.logView];

    self.frame = [UIScreen mainScreen].bounds;
    self.userInteractionEnabled = YES;
    self.clipsToBounds = NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    CGPoint center = self.circle.center;
    center.x += translation.x;
    center.y += translation.y;
    self.circle.center = center;
    [gesture setTranslation:CGPointZero inView:self];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    self.expanded = !self.expanded;
    if (self.expanded) {
        [self layoutExpanded];
        self.logView.hidden = NO;
        [self bringSubviewToFront:self.logView];
    } else {
        self.logView.hidden = YES;
        self.frame = [UIScreen mainScreen].bounds;
    }
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.expanded) {
        return CGRectContainsPoint(self.circle.frame, point) || (!self.logView.hidden && CGRectContainsPoint(self.logView.frame, point));
    }
    return CGRectContainsPoint(self.circle.frame, point);
}

- (void)layoutExpanded {
    UIWindow *window = self.window;
    if (!window) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
    }
    if (!window) return;
    CGRect screen = window.bounds;
    self.frame = screen;
    self.logView.frame = CGRectMake(10, 60, screen.size.width - 20, screen.size.height - 120);

    NSMutableString *text = [NSMutableString string];
    @synchronized (self.logs) {
        for (NSString *log in self.logs) {
            [text appendFormat:OBF_NS("%@\n"), log];
        }
    }
    self.logView.text = text;

    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect rect = [self.logView.layoutManager usedRectForTextContainer:self.logView.textContainer];
        [self.logView scrollRectToVisible:CGRectMake(0, rect.size.height - 1, 1, 1) animated:NO];
    });
}

- (void)log:(NSString *)msg {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                        dateStyle:NSDateFormatterNoStyle
                                                        timeStyle:NSDateFormatterMediumStyle];
    NSString *entry = [NSString stringWithFormat:OBF_NS("[%@] %@"), timestamp, msg];
    @synchronized (self.logs) {
        [self.logs addObject:entry];
        if (self.logs.count > 500) {
            [self.logs removeObjectAtIndex:0];
        }
    }
    if (self.expanded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self layoutExpanded];
        });
    }
}

@end

namespace utility {

utility_mgr_type utility_mgr;

void utility_mgr_type::start() {
    NSLog(OBF_NS("[Aurora] utility_mgr::start"));
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
        if (!window) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            window = [[[UIApplication sharedApplication] windows] firstObject];
#pragma clang diagnostic pop
        }
        if (window) {
            AuroraDebugView *debugView = [AuroraDebugView shared];
            debugView.frame = window.bounds;
            debugView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [window addSubview:debugView];
            [window bringSubviewToFront:debugView];
        }
    });
}

void utility_mgr_type::log(const char *msg) {
    NSString *str = [NSString stringWithUTF8String:msg ? msg : OBF("(null)")];
    [[AuroraDebugView shared] log:str];
}

}

#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit2.h>
#import <CaptainHook/CaptainHook.h>

%config(generator=internal)


%group WeeAppBundles

%hook CityNotificationView

- (void)setFrame:(CGRect)frame
{
    // Big giant hack to make the weather notification bundle have the proper frames
    frame.size.width = 476.0f;
    ((UIView *)self).autoresizingMask = UIViewAutoresizingNone;
    %orig;
    frame.size.height -= 2.0f;
    for (UIView *view in ((UIView *)self).superview.subviews) {
        if (view != self) {
            view.autoresizingMask = UIViewAutoresizingNone;
            view.frame = frame;
        }
    }
}

%end

%end

%hook SBApplication

- (void)launch
{
    NSDictionary *LSEnvironment = [[[self bundle] infoDictionary] objectForKey:@"LSEnvironment"];
    if (LSEnvironment) {
        NSMutableDictionary *dict = [[self seatbeltEnvironmentVariables] mutableCopy];
        if (dict) {
            [dict addEntriesFromDictionary:LSEnvironment];
            [self setSeatbeltEnvironmentVariables:dict];
            [dict release];
        } else {
            [self setSeatbeltEnvironmentVariables:LSEnvironment];
        }
    }
    %orig;
}

%end

%hook UIApplication

- (void)motionEnded:(UIEventSubtype)motion withEvent:(id)event
{
    NSLog(@"Layout: %@", [[self keyWindow] recursiveDescription]);
    %orig;
}

%end


/*%/hook UIView

- (NSMutableString *)description
{
    UIViewController *vc = [UIViewController viewControllerForView:self];
    if (!vc)
        return %orig;
    NSMutableString *result = [[%orig mutableCopy] autorelease];
    NSInteger position = [result length] - 1;
    [result insertString:[vc description] atIndex:position];
    [result insertString:@" viewController = " atIndex:position];
    return result;
}

%/end*/

%hook NSBundle

- (BOOL)loadAndReturnError:(NSError **)error
{
    BOOL result = %orig;
    static bool loaded;
    if (!loaded) {
        if ([[self bundleIdentifier] isEqualToString:@"com.apple.weathernotifications.bundle"]) {
            loaded = true;
            %init(WeeAppBundles, CityNotificationView = objc_getClass("CityNotificationView"));
        }
    }
    return result;
}

%end

%ctor
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    %init;
    [pool drain];
}

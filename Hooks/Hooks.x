#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit2.h>

%config(generator=internal)

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

%hook UIView

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

%end

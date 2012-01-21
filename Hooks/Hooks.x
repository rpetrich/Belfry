#import <SpringBoard/SpringBoard.h>

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

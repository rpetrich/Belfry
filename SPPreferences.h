
#import <Foundation/Foundation.h>

typedef NSDictionary SPPreferences;

static NSDictionary *SPLoadPreferences() {
    return [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.chpwn.spire.preferences.plist"];
}

static NSString *SPPreferencesGetProxyURL(SPPreferences *preferences) {
    return [preferences objectForKey:@"SPProxyURL"];
}

static BOOL SPPreferencesHasProxyURL(SPPreferences *preferences) {
    NSString *proxy = SPPreferencesGetProxyURL(preferences);
    return proxy != nil && [[proxy stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
}


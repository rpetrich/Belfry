#import <UIKit/UIKit.h>

@interface PSListController : UIViewController {
    id _specifiers;
}
- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface SPPreferencesListController : PSListController
@end

@implementation SPPreferencesListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers =  [[self loadSpecifiersFromPlistName:@"SpirePreferences" target:self] mutableCopy];
    }

    return _specifiers;
}

- (void)moreInfoPressed:(id)specifier {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://chpwn.com/apps/spire"]];
}

- (void)donatePressed:(id)specifier {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=2AZTMSJJ9YPU2&lc=US&item_name=Spire%20Donation&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donate_SM%2egif%3aNonHosted"]];
}

@end


//
//  OBAInfoViewController.m
//  org.onebusaway.iphone
//
//  Created by Aaron Brethorst on 9/17/12.
//
//

#import "OBAInfoViewController.h"
#import "OBAContactUsViewController.h"
#import "OBAAgenciesListViewController.h"
#import "OBASettingsViewController.h"
#import "OBACreditsViewController.h"
#import "OBAAnalytics.h"
#import "OBAUserProfileViewController.h"
#import <ParseUI/ParseUI.h>
#import <FacebookSDK/FacebookSDK.h>
#import "OBAUser.h"

#define kUserProfileRow 0
#define kSettingsRow 1
#define kAgenciesRow 2
#define kFeatureRequests 3
#define kContactUsRow 4
#define kCreditsRow 5
#define kPrivacy 6

#define kRowCount 7

@interface OBAInfoViewController () <PFLogInViewControllerDelegate>

@end

@implementation OBAInfoViewController

- (id)init {
    self = [super initWithNibName:@"OBAInfoViewController" bundle:nil];
    if (self) {
        self.title = NSLocalizedString(@"Info", @"");
        self.tabBarItem.image = [UIImage imageNamed:@"info"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectZero];
    footerView.backgroundColor = [UIColor clearColor];
    [self.tableView setTableFooterView:footerView];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [UIColor whiteColor];
    self.tableView.tableHeaderView = self.headerView;
    self.tableView.frame = self.view.bounds;

    [self refreshLoginStatus];

    [OBAAnalytics reportScreenView:[NSString stringWithFormat:@"View: %@", [self class]]];
}

#pragma mark - Parse Login/Logout

- (void)refreshLoginStatus {
    if ([PFUser currentUser]) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Log Out", @"") style:UIBarButtonItemStyleBordered target:self action:@selector(logout)];
    }
    else {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Log In", @"") style:UIBarButtonItemStyleBordered target:self action:@selector(loginOrSignup)];
    }
}

- (void)logout {
    [PFUser logOut];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Log In", @"") style:UIBarButtonItemStyleBordered target:self action:@selector(loginOrSignup)];
}

- (void)loginOrSignup {
    //Parse setup
    PFLogInViewController *loginController = [[PFLogInViewController alloc] init];
    loginController.delegate = self;
    loginController.fields = (PFLogInFieldsUsernameAndPassword | PFLogInFieldsLogInButton | PFLogInFieldsSignUpButton | PFLogInFieldsPasswordForgotten | PFLogInFieldsDismissButton | PFLogInFieldsFacebook | PFLogInFieldsTwitter);
    loginController.facebookPermissions = @[@"friends_about_me"];

    [self presentViewController:loginController animated:YES completion:nil];
}

#pragma mark - PFLogInViewControllerDelegate

- (void)logInViewController:(PFLogInViewController *)logInController didLogInUser:(PFUser *)user {
    [self refreshLoginStatus];

    if (FBSession.activeSession.isOpen) {
        [self loadFacebookUserData];
    }
    else if ([PFTwitterUtils isLinkedWithUser:[PFUser currentUser]]) {
        [self loadTwitterUserData];
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)logInViewController:(PFLogInViewController *)logInController didFailToLogInWithError:(PFUI_NULLABLE NSError *)error {
    //
}

- (void)logInViewControllerDidCancelLogIn:(PFLogInViewController *)logInController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Handlers for User Info

- (void)loadFacebookUserData {

    OBAUser * currentUser = (OBAUser*)[PFUser currentUser];

    [[FBRequest requestForMe] startWithCompletionHandler:^(FBRequestConnection *connection, NSDictionary<FBGraphUser> *user, NSError *error) {
        if (!error) {
            currentUser.imageURL = [NSString stringWithFormat:@"https://graph.facebook.com/%@/picture?type=large&return_ssl_resources=1", user.objectID];
            currentUser.displayName = user.name;
            [currentUser saveInBackground];
        }
    }];
}

- (void)loadTwitterUserData {
    PF_Twitter *twitter = [PFTwitterUtils twitter];

    OBAUser * currentUser = (OBAUser*)[PFUser currentUser];
    currentUser.displayName = twitter.screenName;

    NSString * requestString = [NSString stringWithFormat:@"https://api.twitter.com/1.1/users/show.json?user_id=%@", twitter.userId];
    NSURL *verify = [NSURL URLWithString:requestString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:verify];
    [[PFTwitterUtils twitter] signRequest:request];

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask * dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (data.length > 0 && !error) {
            id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
            NSString *url = jsonObject[@"profile_image_url"];

            currentUser.imageURL = [url stringByReplacingOccurrencesOfString:@"_normal" withString:@"_bigger"];
        }

        [currentUser saveInBackground];
    }];

    [dataTask resume];
}

#pragma mark - Actions

- (void) openContactUs {
    UIViewController *pushMe = nil;
    pushMe = [[OBAContactUsViewController alloc] init];
    [self.navigationController pushViewController:pushMe animated:YES];
}

- (void) openSettings {
    UIViewController *pushMe = nil;
    pushMe = [[OBASettingsViewController alloc] init];
    [self.navigationController pushViewController:pushMe animated:YES];
}

- (void) openAgencies {
    UIViewController *pushMe = nil;
    pushMe = [[OBAAgenciesListViewController alloc] init];
    [self.navigationController pushViewController:pushMe animated:YES];
}

- (void)openUserProfile {
  UIViewController *vc = nil;
  vc = [[OBAUserProfileViewController alloc] init];
  [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return kRowCount;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"CellIdentifier";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont systemFontOfSize:19];
    }

    switch (indexPath.row) {
        case kContactUsRow: {
            cell.textLabel.text = NSLocalizedString(@"Contact Us", @"info row contact us");
            break;
        }
        case kSettingsRow: {
            cell.textLabel.text = NSLocalizedString(@"Settings", @"info row settings");
            break;
        }
        case kAgenciesRow: {
            cell.textLabel.text = NSLocalizedString(@"Agencies", @"info row agencies");
            break;
        }
        case kCreditsRow: {
            cell.textLabel.text = NSLocalizedString(@"Credits", @"info row credits");
            break;
        }
        case kFeatureRequests: {
            cell.textLabel.text = NSLocalizedString(@"Feature Requests", @"info row feture requests");
            break;
        }
        case kPrivacy: {
            cell.textLabel.text = NSLocalizedString(@"Privacy Policy", @"info row privacy");
            break;
        }
        case kUserProfileRow: {
          cell.textLabel.text = NSLocalizedString(@"Profile", @"info row user profile");
        }
        default:
            break;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    UIViewController *pushMe = nil;

    switch (indexPath.row) {
        case kContactUsRow: {
            [self openContactUs];
            break;
        }
        case kSettingsRow: {
            [self openSettings];
            break;
        }
        case kAgenciesRow: {
            [self openAgencies];
            break;
        }
        case kCreditsRow: {
            pushMe = [[OBACreditsViewController alloc] init];
            [self.navigationController pushViewController:pushMe animated:YES];
            break;
        }
        case kFeatureRequests: {
            [OBAAnalytics reportEventWithCategory:@"ui_action" action:@"button_press" label:@"Clicked Feature Request Link" value:nil];
            NSString *url = [NSString stringWithString: NSLocalizedString(@"http://onebusaway.ideascale.com/a/ideafactory.do?id=8715&mode=top&discussionFilter=byids&discussionID=46166",@"didSelectRowAtIndexPath case 1")];
            [[UIApplication sharedApplication] openURL: [NSURL URLWithString: url]];
            break;
        }
        case kPrivacy: {
            [OBAAnalytics reportEventWithCategory:@"ui_action" action:@"button_press" label:@"Clicked Privacy Policy Link" value:nil];
            NSString *url = [NSString stringWithString: NSLocalizedString(@"http://onebusaway.org/privacy/",@"didSelectRowAtIndexPath case 3")];
            [[UIApplication sharedApplication] openURL: [NSURL URLWithString: url]];
            break;
        }
        case kUserProfileRow: {
            [self openUserProfile];
            break;
        }
        default:
            break;
    }
}

@end

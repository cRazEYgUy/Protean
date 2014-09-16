#import <Preferences/Preferences.h>

@interface PSViewController (SettingsKit)
-(UINavigationController*)navigationController;
-(void)viewWillAppear:(BOOL)animated;
-(void)viewWillDisappear:(BOOL)animated;
@end

@interface PROrganizationController : PSViewController<UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView * tableView;
@end
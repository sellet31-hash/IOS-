#import <UIKit/UIKit.h>
#import "ABModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ABAppDetailViewController : UITableViewController
- (instancetype)initWithApp:(ABAppInfo *)app;
@end

NS_ASSUME_NONNULL_END

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ABProgressOverlay : UIView
+ (ABProgressOverlay *)showInView:(UIView *)view title:(NSString *)title cancelHandler:(void (^)(void))cancelHandler;
- (void)updateMessage:(NSString *)message fraction:(double)fraction bytesDone:(uint64_t)done bytesTotal:(uint64_t)total;
- (void)dismiss;
@end

NS_ASSUME_NONNULL_END

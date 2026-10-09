#import <Foundation/Foundation.h>
#import "ABModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ABContainerLocation : NSObject
@property (nonatomic, copy, nullable) NSURL *dataContainerURL;
@property (nonatomic, copy, nullable) NSURL *bundleURL;
@property (nonatomic, copy) NSDictionary<NSString *, NSURL *> *groupContainers;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *shortVersion;
@property (nonatomic, copy, nullable) NSString *bundleVersion;
@end

@interface ABAppLibrary : NSObject
@property (nonatomic, readonly) BOOL accessDenied;
+ (instancetype)sharedLibrary;
- (void)reload;
- (NSArray<ABAppInfo *> *)installedApps;
- (nullable ABAppInfo *)appForBundleIdentifier:(NSString *)bundleIdentifier;
- (nullable ABContainerLocation *)locationForBundleIdentifier:(NSString *)bundleIdentifier;
@end

NS_ASSUME_NONNULL_END

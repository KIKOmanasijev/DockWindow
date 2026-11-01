#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Creates Sparkle's standard updater controller after the app has verified and loaded
/// Sparkle.framework at runtime. DogBar does not link Sparkle, so an unverified framework
/// is never mapped at launch.
@interface DogBarSparkleBridge : NSObject
+ (nullable NSObject *)makeStandardUpdaterControllerWithUpdaterDelegate:(id)updaterDelegate;
@end

NS_ASSUME_NONNULL_END

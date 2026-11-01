#import "DogBarSparkleBridge.h"

// Mirrors -[SPUStandardUpdaterController initWithStartingUpdater:updaterDelegate:userDriverDelegate:]
// from the exactly pinned Sparkle version.
@protocol DogBarSparkleStandardUpdaterController
- (instancetype)initWithStartingUpdater:(BOOL)startUpdater updaterDelegate:(nullable id)updaterDelegate userDriverDelegate:(nullable id)userDriverDelegate;
@end

@implementation DogBarSparkleBridge
+ (NSObject *)makeStandardUpdaterControllerWithUpdaterDelegate:(id)updaterDelegate {
    Class controller = NSClassFromString(@"SPUStandardUpdaterController");
    SEL initializer = @selector(initWithStartingUpdater:updaterDelegate:userDriverDelegate:);
    if (controller == Nil || ![controller instancesRespondToSelector:initializer]) { return nil; }
    return (NSObject *)[(id<DogBarSparkleStandardUpdaterController>)[controller alloc] initWithStartingUpdater:NO updaterDelegate:updaterDelegate userDriverDelegate:nil];
}
@end

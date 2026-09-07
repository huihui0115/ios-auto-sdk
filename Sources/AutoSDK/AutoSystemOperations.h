#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

// Internal asynchronous-to-synchronous bridge. Not part of the public SDK.
typedef BOOL (^AutoSystemCancellation)(void);

@interface AutoPendingSystemOperation : NSObject
@property (nonatomic, strong, readonly) id result;
- (instancetype)initWithTimeout:(NSTimeInterval)timeout cancellation:(AutoSystemCancellation)cancellation;
- (BOOL)isActive;
- (void)completeWithResult:(id)result error:(NSError *)error;
// NO means deadline/cancellation; timeout has no error (location's null contract).
- (BOOL)waitWithError:(NSError **)error;
@end

@protocol AutoLocationManaging <NSObject>
@property (nonatomic, weak) id<CLLocationManagerDelegate> delegate;
@property (nonatomic, assign) CLLocationAccuracy desiredAccuracy;
@property (nonatomic, readonly) CLAuthorizationStatus authorizationStatus;
- (void)requestLocation;
- (void)requestWhenInUseAuthorization;
- (void)stopUpdatingLocation;
@end

typedef id<AutoLocationManaging> (^AutoLocationManagerFactory)(void);
NSDictionary *AutoGetLocationSnapshot(double timeoutMs, AutoSystemCancellation cancellation,
                                      AutoLocationManagerFactory factory, BOOL hasUsageDescription,
                                      NSError **error);

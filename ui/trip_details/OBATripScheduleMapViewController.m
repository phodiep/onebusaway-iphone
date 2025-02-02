#import "OBATripScheduleMapViewController.h"
#import "OBATripScheduleListViewController.h"
#import "OBAStopV2.h"
#import "OBATripStopTimeV2.h"
#import "OBAStopIconFactory.h"
#import "OBATripStopTimeMapAnnotation.h"
#import "OBATripContinuationMapAnnotation.h"
#import "OBACoordinateBounds.h"
#import "OBAStopViewController.h"
#import "OBASphericalGeometryLibrary.h"
#import "OBATripDetailsViewController.h"
#import "OBAPresentation.h"
#import "OBAAnalytics.h"
#import "UINavigationController+oba_Additions.h"

static const NSString *kTripDetailsContext = @"TripDetails";
static const NSString *kShapeContext = @"ShapeContext";

@interface OBATripScheduleMapViewController ()

@property (nonatomic, strong) id<OBAModelServiceRequest> request;
@property (nonatomic, strong) NSDateFormatter *timeFormatter;

@property (nonatomic, strong) MKPolyline *routePolyline;
@property (nonatomic, strong) MKPolylineView *routePolylineView;

@end


@implementation OBATripScheduleMapViewController

- (id)initWithApplicationDelegate:(OBAApplicationDelegate *)appDelegate {
    self = [super initWithNibName:@"OBATripScheduleMapViewController" bundle:nil];

    if (self) {
        self.appDelegate = appDelegate;
    }

    return self;
}

- (void)dealloc {
    [_request cancel];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _timeFormatter = [[NSDateFormatter alloc] init];
    [_timeFormatter setDateStyle:NSDateFormatterNoStyle];
    [_timeFormatter setTimeStyle:NSDateFormatterShortStyle];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"lines"] style:UIBarButtonItemStylePlain target:self action:@selector(showList:)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = NSLocalizedString(@"Nearby stops list", @"self.navigationItem.rightBarButtonItem.accessibilityLabel");
    self.progressView = [[OBAProgressIndicatorView alloc] initWithFrame:CGRectMake(80, 6, 160, 33)];
    self.navigationItem.titleView = self.progressView;
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Schedule", @"initWithTitle") style:UIBarButtonItemStyleBordered target:nil action:nil];
    self.navigationItem.backBarButtonItem = backItem;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (_tripInstance && !_tripDetails) {
        @weakify(self);
        _request = [_appDelegate.modelService
                    requestTripDetailsForTripInstance:_tripInstance
                                      completionBlock:^(id responseData, NSUInteger responseCode, NSError *error) {
                                          @strongify(self);
                                          if (error || responseCode >= 300) {
                                              [self updateProgressViewWithError:error responseCode:responseCode];
                                          }
                                          else {
                                              OBAEntryWithReferencesV2 *entry = responseData;
                                              self.tripDetails = entry.entry;
                                              [self handleTripDetails];
                                          }
                                      }

                                      progressBlock:^(CGFloat progress) {
                                          @strongify(self);
                                          if (progress > 1.0) {
                                              [self.progressView setMessage:NSLocalizedString(@"Downloading...", @"message") inProgress:YES progress:progress];
                                          }
                                          else {
                                              [self.progressView setInProgress:YES progress:progress];
                                          }
                                      }];
    }
    else {
        [self handleTripDetails];
    }

    [OBAAnalytics reportScreenView:[NSString stringWithFormat:@"View: %@", [self class]]];
}

- (void)showList:(id)source {
    OBATripScheduleListViewController *vc = [[OBATripScheduleListViewController alloc] initWithApplicationDelegate:self.appDelegate tripInstance:_tripInstance];

    vc.tripDetails = self.tripDetails;
    vc.currentStopId = self.currentStopId;
    [self.navigationController replaceViewController:vc animated:YES];
}

- (void)updateProgressViewWithError:(NSError *)error responseCode:(NSInteger)responseCode {
    if (responseCode == 404) {
        [_progressView setMessage:NSLocalizedString(@"Trip not found", @"message") inProgress:NO progress:0];
    }
    else if (responseCode >= 300) {
        [_progressView setMessage:NSLocalizedString(@"Unknown error", @"message") inProgress:NO progress:0];
    }
    else if (error) {
        OBALogWarningWithError(error, @"Error");
        [_progressView setMessage:NSLocalizedString(@"Error connecting", @"message") inProgress:NO progress:0];
    }
}

#pragma mark MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[OBATripStopTimeMapAnnotation class]]) {
        CGFloat scale = [OBASphericalGeometryLibrary computeStopsForRouteAnnotationScaleFactor:mapView.region];
        CGFloat alpha = scale <= 0.11f ? 0.0f : 1.0f;

        OBATripStopTimeMapAnnotation *an = (OBATripStopTimeMapAnnotation *)annotation;
        static NSString *viewId = @"StopView";

        MKAnnotationView *view = [mapView dequeueReusableAnnotationViewWithIdentifier:viewId];

        if (view == nil) {
            view = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:viewId];
        }

        view.canShowCallout = YES;
        view.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        OBAStopIconFactory *stopIconFactory = [[self appDelegate] stopIconFactory];
        view.image = [stopIconFactory getIconForStop:an.stopTime.stop];
        view.transform = CGAffineTransformMakeScale(scale, scale);
        view.alpha = alpha;
        return view;
    }
    else if ([annotation isKindOfClass:[OBATripContinuationMapAnnotation class]]) {
        static NSString *viewId = @"TripContinutationView";

        MKPinAnnotationView *view = (MKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:viewId];

        if (view == nil) {
            view = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:viewId];
        }

        view.canShowCallout = YES;
        view.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        return view;
    }

    return nil;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    id annotation = view.annotation;

    if ([annotation isKindOfClass:[OBATripStopTimeMapAnnotation class] ]) {
        OBATripStopTimeMapAnnotation *an = (OBATripStopTimeMapAnnotation *)annotation;
        OBATripStopTimeV2 *stopTime = an.stopTime;
        OBAStopViewController *vc = [[OBAStopViewController alloc] initWithApplicationDelegate:self.appDelegate stopId:stopTime.stopId];
        [self.navigationController pushViewController:vc animated:YES];
    }
    else if ([annotation isKindOfClass:[OBATripContinuationMapAnnotation class]]) {
        OBATripContinuationMapAnnotation *an = (OBATripContinuationMapAnnotation *)annotation;
        OBATripDetailsViewController *vc = [[OBATripDetailsViewController alloc] initWithApplicationDelegate:_appDelegate tripInstance:an.tripInstance];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (MKOverlayView *)mapView:(MKMapView *)mapView viewForOverlay:(id)overlay {
    MKOverlayView *overlayView = nil;

    if (overlay == _routePolyline) {
        //if we have not yet created an overlay view for this overlay, create it now.
        if (_routePolylineView == nil) {
            _routePolylineView = [[MKPolylineView alloc] initWithPolyline:_routePolyline];
            _routePolylineView.fillColor = [UIColor blackColor];
            _routePolylineView.strokeColor = [UIColor blackColor];
            _routePolylineView.lineWidth = 5;
        }

        overlayView = _routePolylineView;
    }

    return overlayView;
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    CGFloat scale = [OBASphericalGeometryLibrary computeStopsForRouteAnnotationScaleFactor:mapView.region];
    CGFloat alpha = scale <= 0.11f ? 0.f : 1.f;

    NSLog(@"scale=%f alpha=%f", scale, alpha);

    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);

    for (id<MKAnnotation> annotation in mapView.annotations) {
        if ([annotation isKindOfClass:[OBATripStopTimeMapAnnotation class]]) {
            MKAnnotationView *view = [mapView viewForAnnotation:annotation];
            view.transform = transform;
            view.alpha = alpha;
        }
    }
}

- (MKMapView *)mapView {
    return (MKMapView *)self.view;
}

- (void)handleTripDetails {
    [_progressView setMessage:NSLocalizedString(@"Route Map", @"message") inProgress:NO progress:0];

    OBATripScheduleV2 *sched = _tripDetails.schedule;
    NSArray *stopTimes = sched.stopTimes;
    MKMapView *mapView = [self mapView];

    NSMutableArray *annotations = [[NSMutableArray alloc] init];

    OBACoordinateBounds *bounds = [[OBACoordinateBounds alloc] init];

    for (OBATripStopTimeV2 *stopTime in stopTimes) {
        OBATripStopTimeMapAnnotation *an = [[OBATripStopTimeMapAnnotation alloc] initWithTripDetails:self.tripDetails stopTime:stopTime];
        an.timeFormatter = _timeFormatter;
        [annotations addObject:an];

        OBAStopV2 *stop = stopTime.stop;
        [bounds addLat:stop.lat lon:stop.lon];
    }

    if (sched.nextTripId && [stopTimes count] > 0) {
        id<MKAnnotation> an = [self createTripContinuationAnnotation:sched.nextTrip isNextTrip:YES stopTimes:stopTimes];
        [annotations addObject:an];
    }

    if (sched.previousTripId && [stopTimes count] > 0) {
        id<MKAnnotation> an = [self createTripContinuationAnnotation:sched.previousTrip isNextTrip:NO stopTimes:stopTimes];
        [annotations addObject:an];
    }

    [mapView addAnnotations:annotations];

    if (!bounds.empty) [mapView setRegion:bounds.region];

    OBATripV2 *trip = _tripDetails.trip;

    if (trip.shapeId) {
        @weakify(self);
        _request = [_appDelegate.modelService
                    requestShapeForId:trip.shapeId
                      completionBlock:^(id responseData, NSUInteger responseCode, NSError *error) {
                          @strongify(self);
                          if (responseData) {
                              NSString *polylineString = responseData;
                              self.routePolyline = [OBASphericalGeometryLibrary decodePolylineStringAsMKPolyline:polylineString];
                              [self.mapView addOverlay:self.routePolyline];
                          }

                          [self.progressView setMessage:NSLocalizedString(@"Route Map", @"message") inProgress:NO progress:0];
                      }];
    }
}

- (id<MKAnnotation>)createTripContinuationAnnotation:(OBATripV2 *)trip isNextTrip:(BOOL)isNextTrip stopTimes:(NSArray *)stopTimes {
    OBATripInstanceRef *tripRef = _tripDetails.tripInstance;

    NSString *format = isNextTrip ? NSLocalizedString(@"Continues as", @"text") : NSLocalizedString(@"Starts as", @"text");
    NSString *tripTitle = [NSString stringWithFormat:@"%@ %@", format, trip.asLabel];
    NSInteger index = isNextTrip ? ([stopTimes count] - 1) : 0;
    OBATripStopTimeV2 *stopTime = stopTimes[index];
    OBAStopV2 *stop = stopTime.stop;

    MKCoordinateRegion r = [OBASphericalGeometryLibrary createRegionWithCenter:stop.coordinate latRadius:100 lonRadius:100];
    MKCoordinateSpan span = r.span;

    NSInteger x = [self getXOffsetForStop:stop defaultValue:(isNextTrip ? 1 : -1)];
    NSInteger y = [self getYOffsetForStop:stop defaultValue:(isNextTrip ? 1 : -1)];

    double lat = (stop.lat + y * span.latitudeDelta / 2);
    double lon = (stop.lon + x * span.longitudeDelta / 2);
    CLLocationCoordinate2D p = [OBASphericalGeometryLibrary makeCoordinateLat:lat lon:lon];

    return [[OBATripContinuationMapAnnotation alloc] initWithTitle:tripTitle tripInstance:tripRef location:p];
}

- (NSInteger)getXOffsetForStop:(OBAStopV2 *)stop defaultValue:(NSInteger)defaultXOffset {
    NSString *direction = stop.direction;

    if (!direction) return defaultXOffset;

    if ([direction rangeOfString:@"W"].location != NSNotFound) return -1 * defaultXOffset;
    else if ([direction rangeOfString:@"E"].location != NSNotFound) return 1 * defaultXOffset;

    return 0;
}

- (NSInteger)getYOffsetForStop:(OBAStopV2 *)stop defaultValue:(NSInteger)defaultYOffset {
    NSString *direction = stop.direction;

    if (!direction) return defaultYOffset;

    if ([direction rangeOfString:@"S"].location != NSNotFound) return -1 * defaultYOffset;
    else if ([direction rangeOfString:@"N"].location != NSNotFound) return 1 * defaultYOffset;

    return 0;
}

@end

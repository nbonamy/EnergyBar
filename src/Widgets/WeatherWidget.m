/**
 * @file WeatherWidget.m
 *
 * @copyright 2018-2019 Bill Zissimopoulos
 */
/*
 * This file is part of EnergyBar.
 *
 * You can redistribute it and/or modify it under the terms of the GNU
 * General Public License version 3 as published by the Free Software
 * Foundation.
 */

#import "WeatherWidget.h"
#import <CoreLocation/CoreLocation.h>
#import "ImageTitleView.h"
#import "WeatherKit.h"

static NSImage *weatherImage(uint64_t conditionCode)
{
    static NSImageName imageNames[] =
    {
        @"no-report",
        @"tornado",
        @"tropical-storm",
        @"hurricane",
        @"severe-thunderstorm",
        @"severe-thunderstorm",
        @"sleet",
        @"sleet",
        @"sleet",
        @"hail",
        @"drizzle",
        @"blizzard",
        @"heavy-rain",
        @"flurry",
        @"flurry-snow-snow-shower",
        @"blowingsnow",
        @"flurry",
        @"hail",
        @"sleet",
        @"dust",
        @"fog",
        @"haze",
        @"smoke",
        @"breezy",
        @"breezy",
        @"ice",
        @"mostly-cloudy",
        @"mostly-cloudy-night",
        @"mostly-cloudy",
        @"partly-cloudy-night",
        @"partly-cloudy-day",
        @"clear-night",
        @"mostly-sunny",
        @"clear-night",
        @"mostly-sunny",
        @"hail",
        @"hot",
        @"scattered-thunderstorm",
        @"scattered-thunderstorm",
        @"scattered-showers",
        @"flurry",
        @"flurry",
        @"partly-cloudy-day",
        @"flurry",
        @"scattered-thunderstorm",
    };

    if (conditionCode >= sizeof imageNames / sizeof imageNames[0])
        conditionCode = 0;

    NSBundle *bundle = [NSBundle
        bundleWithPath:@"/System/Library/Frameworks/NotificationCenter.framework"];
    return [bundle imageForResource:imageNames[conditionCode]];
}

@interface WeatherData : NSObject
@property (retain) NSImage *icon;
@property (copy) NSString *condition;
@property (copy) NSString *placeName;
@end

@implementation WeatherData
- (void)dealloc
{
    self.icon = nil;
    self.condition = nil;
    self.placeName = nil;

    [super dealloc];
}
@end

@interface WeatherWidgetView : ImageTitleView
@end

@implementation WeatherWidgetView
- (NSSize)intrinsicContentSize
{
    return NSMakeSize(100, NSViewNoIntrinsicMetric);
}
@end

@interface WeatherWidget () <CLLocationManagerDelegate>
@property (retain) CLLocationManager *manager;
@property (retain) CLLocation* location;
@property (retain) NSTimer *timer;
@end

@implementation WeatherWidget

- (void)commonInit
{
    self.customizationLabel = @"Weather";

    ImageTitleView *view = [[[WeatherWidgetView alloc] initWithFrame:NSZeroRect] autorelease];
    view.wantsLayer = YES;
    view.layer.cornerRadius = 8.0;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.0 alpha:0.5] CGColor];
    view.imageSize = NSMakeSize(20, 20);
    view.titleFont = [NSFont boldSystemFontOfSize:[NSFont
        systemFontSizeForControlSize:NSControlSizeSmall]];
    view.titleLineBreakMode = NSLineBreakByTruncatingTail;
    view.subtitleFont = [NSFont systemFontOfSize:[NSFont
        systemFontSizeForControlSize:NSControlSizeSmall]];
    view.subtitleLineBreakMode = NSLineBreakByTruncatingTail;
    self.view = view;

    NSClickGestureRecognizer *tapRecognizer = [[[NSClickGestureRecognizer alloc]
                                                initWithTarget:self action:@selector(tapAction:)] autorelease];
    tapRecognizer.allowedTouchTypes = NSTouchTypeMaskDirect;
    [self.view addGestureRecognizer:tapRecognizer];
    
    [self updateWeather:nil];

    self.manager = [[[CLLocationManager alloc] init] autorelease];
}

- (void)dealloc
{
    self.manager = nil;
    self.location = nil;
    self.timer = nil;

    [super dealloc];
}

- (void)viewWillAppear
{
    [self start];
}

- (void)viewDidDisappear
{
    [self stop];
}

- (void)setEmbedded {
    [self.view removeGestureRecognizer:[self.view.gestureRecognizers objectAtIndex:0]];
}

- (void)start
{
    if (nil != self.timer)
        return;

    NSDate *date = [[NSDate date] dateByAddingTimeInterval:3600.0];
    NSDateComponents *comp = [[NSCalendar currentCalendar]
        components:NSCalendarUnitEra|NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|
            NSCalendarUnitHour
        fromDate:date];
    date = [[NSCalendar currentCalendar] dateFromComponents:comp];

    self.timer = [[[NSTimer alloc]
        initWithFireDate:date
        interval:3600.0
        target:self
        selector:@selector(tick:)
        userInfo:nil
        repeats:YES] autorelease];
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSDefaultRunLoopMode];

    [self tick:nil];
}

- (void)stop
{
    [self.timer invalidate];
    self.timer = nil;

    [self.manager stopUpdatingLocation];
    self.manager.delegate = nil;
}

- (void)tick:(NSTimer *)sender
{
    [self.manager startUpdatingLocation];
    self.manager.delegate = self;
}

- (void)locationManager:(CLLocationManager *)manager
    didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    [self.manager stopUpdatingLocation];
    self.manager.delegate = nil;

    self.location = [[locations lastObject] copy];
    CLGeocoder *geocoder = [[[CLGeocoder alloc] init] autorelease];
    [geocoder
        reverseGeocodeLocation:self.location
        completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error)
        {
            WeatherData *data = [[[WeatherData alloc] init] autorelease];
            data.placeName = [[placemarks firstObject] locality];
            [[WMWeatherStore sharedWeatherStore]
                currentConditionsForCoordinate:self.location.coordinate
                result:^(WMWeatherData *wmdata)
                {
                    [self performBlockOnMainThread:^
                    {
                        if (nil != wmdata)
                        {
                            NSImage *icon = weatherImage(wmdata.conditionCode);
                            if (nil == icon && nil != wmdata.imageSmallURL)
                                icon = [[[NSImage alloc]
                                    initWithContentsOfURL:wmdata.imageSmallURL] autorelease];
                            data.icon = icon;
                            data.condition = [NSString stringWithFormat:@"%.0f%@",
                                'F' == self.temperatureUnit ? wmdata.temperatureFahrenheit : wmdata.temperatureCelsius,
                                'F' == self.temperatureUnit ? @"°F" : @"°C"];
                            [self updateWeather:data];
                        }
                        else
                            [self updateWeather:nil];
                    }];
                }];
        }];
}

- (void)locationManager:(CLLocationManager *)manager
    didFailWithError:(NSError *)error
{
    switch (error.code)
    {
    case kCLErrorDenied:
        [self.manager stopUpdatingLocation];
        self.manager.delegate = nil;
        [self updateWeather:nil];
        break;
    default:
        break;
    }
}

- (void)updateWeather:(WeatherData *)data
{
    NSImage *icon = data.icon;
    NSString *title = data.condition;
    NSString *subtitle = data.placeName;

    if (nil == icon && nil == title && nil == subtitle)
    {
        icon = weatherImage(0);
        if (nil == icon)
            title = @"--";
    }

    ImageTitleViewLayoutOptions layoutOptions = 0;
    if (nil != icon)
        layoutOptions = layoutOptions | ImageTitleViewLayoutOptionImage;
    if (nil != title)
        layoutOptions = layoutOptions | ImageTitleViewLayoutOptionTitle;
    if (nil != subtitle)
        layoutOptions = layoutOptions | ImageTitleViewLayoutOptionSubtitle;

    ImageTitleView *view = self.view;
    view.image = icon;
    view.title = title;
    view.subtitle = subtitle;
    view.layoutOptions = layoutOptions;
    
    // refresh
    [view layout];
}

- (void)resetWeather
{
    if (nil == self.timer)
        return;

    [self stop];
    [self start];
}

- (void) tapAction:(id) sender
{
    NSString* weatherUrlPrefix = @"https://weather.com/weather/today/l";
    NSString* weatherUrlSuffix = @"&par=apple_todayosx";
    NSString* url = [NSString stringWithFormat:@"%@/%.2f,%.2f?temp=%@%@", weatherUrlPrefix, self.location.coordinate.latitude, self.location.coordinate.longitude, 'F' == self.temperatureUnit ? @"f" : @"c", weatherUrlSuffix];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}

- (void)performBlockOnMainThread:(void (^)(void))block
{
    block = [block copy];
    [self
        performSelectorOnMainThread:@selector(performBlockOnMainThread_:)
        withObject:block
        waitUntilDone:NO];
    [block release];
}

- (void)performBlockOnMainThread_:(void (^)(void))block
{
    block();
}
@end

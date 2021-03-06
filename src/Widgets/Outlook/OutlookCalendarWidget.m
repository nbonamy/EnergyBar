//
//  OutlookCalendarWidget.m
//  EnergyBar
//
//  Created by Nicolas Bonamy on 9/27/20.
//  Copyright © 2020 Nicolas Bonamy. All rights reserved.
//

#import "OutlookCalendarWidget.h"
#import "OutlookNextEventWidget.h"
#import "ImageTileWidget.h"
#import "NSDate+Utils.h"
#import "OutlookEvent.h"
#import "Outlook.h"

#define DUMP 0

#define SIGNIN_INDEX 0
#define LOADING_INDEX 1
#define EMPTY_INDEX 2
#define EVENT_INDEX 3

#define REFRESH_TIMER_DELAY 30
#define FETCH_CALENDAR_EVERY_SECONDS 5*60
#define FETCH_CALENDAR_EVERY_SECONDS_IF_EMPTY 60

@interface OutlookCalendarWidget()
@property (retain) OutlookNextEventWidget* nextEventWidget;
@property (retain) NSTimer* doubleTapTimer;
@property (retain) NSTimer* refreshTimer;
@property (retain) Outlook* outlook;
@property (retain) NSDate* lastFetch;
@property (retain) id target;
@property (assign) SEL action;
@end

@implementation OutlookCalendarWidget

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [super encodeWithCoder:coder];
}

- (void)commonInit {
    
    // no connection
    [self addWidget:[[[ImageTileWidget alloc] initWithIdentifier:@"_OutlookNoSignin"
                                             customizationLabel:@"Outlook Calendar"
                                                          title:@"Tap to setup your Microsoft account"
                                                           icon:[NSImage imageNamed:NSImageNameUserAccounts]] autorelease]];
    
    // loading
    [self addWidget:[[[ImageTileWidget alloc] initWithIdentifier:@"_OutlookLoading"
                                             customizationLabel:@"Outlook Calendar"
                                                          title:@"Loading your calendar..."
                                                           icon:[NSImage imageNamed:@"ActivityIndicator"]] autorelease]];
    
    // no event
    [self addWidget:[[[ImageTileWidget alloc] initWithIdentifier:@"_OutlookNoEvents"
                                             customizationLabel:@"Outlook Calendar"
                                                          title:@"No events for now!"
                                                            icon:[NSImage imageNamed:@"Checkmark"]] autorelease]];
    
    // add widgets
    self.nextEventWidget = [[[OutlookNextEventWidget alloc] initWithIdentifier:@"_OutlookNextEvent"] autorelease];
    [self.nextEventWidget setDelegate:self];
    [self addWidget:self.nextEventWidget];
    
    // init outlook
    self.outlook = [[[Outlook alloc] init] autorelease];
        
}

- (void)setPressTarget:(id)target action:(SEL)action
{
    self.target = target;
    self.action = action;
}

- (void)currentEventChanged:(nonnull OutlookEvent *)event {

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.nextEventWidget.currentEvent != nil) {
            [self setActiveIndex:EVENT_INDEX];
        } else {
            [self setActiveIndex:EMPTY_INDEX];
        }
    });
}

- (void)requestReload {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setActiveIndex:LOADING_INDEX];
    });
    [self reloadEvents];
}


- (void)tapAction:(id)sender {

    switch (self.activeIndex) {
        case SIGNIN_INDEX:
            // show configuration
            [self.target performSelector:self.action withObject:[NSNumber numberWithInt:2]];
            break;
            
        case LOADING_INDEX:
            break;
            
        case EMPTY_INDEX:
            // handle double tap
            if (self.doubleTapTimer != nil && [self.doubleTapTimer isValid]) {
                [self.doubleTapTimer invalidate];
                self.doubleTapTimer = nil;
                [self requestReload];
            } else {
                self.doubleTapTimer = [NSTimer scheduledTimerWithTimeInterval:[NSEvent doubleClickInterval] repeats:NO block:^(NSTimer * _Nonnull timer) {
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://outlook.office.com/calendar/"]];
                    self.doubleTapTimer = nil;
                }];
            }
            break;
            
        case EVENT_INDEX:
            break;
    }
    
}

- (void)viewWillAppear {
    [self tick:nil];
}

- (void)reloadEvents {
    self.lastFetch = nil;
    [self tick:nil];
}

- (void)tick:(NSTimer *)sender {
    
    // invalidate any existing timer
    [self.refreshTimer invalidate];
    
    // update
    if (self.lastFetch == nil || fabs([self.lastFetch timeIntervalSinceNow]) > FETCH_CALENDAR_EVERY_SECONDS) {
        [self loadEvents];
    } else {
        [self.nextEventWidget refresh];
    }
    
    // schedule next
    NSDate* fireDate = [NSDate nextTickForEverySeconds:REFRESH_TIMER_DELAY withDelta:0];
    self.refreshTimer = [[[NSTimer alloc]
                          initWithFireDate:fireDate
                          interval:0
                          target:self
                          selector:@selector(tick:)
                          userInfo:nil
                          repeats:NO] autorelease];
    
    self.refreshTimer.tolerance = 0;
    
    [[NSRunLoop currentRunLoop] addTimer:self.refreshTimer forMode:NSDefaultRunLoopMode];
    
}

- (void)loadEvents {
    
    [self.outlook loadCurrentAccount:^{
        
        // need an account
        if (self.outlook.currentAccount == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setActiveIndex:SIGNIN_INDEX];
            });
            return;
        }
        
        // while loading
        if (self.activeIndex != EVENT_INDEX) {
            [self setActiveIndex:LOADING_INDEX];
        }
        
        // load categories
        //[self.outlook getCategories:^(NSDictionary * jsonCategories) {
        //    LOG("[CALENDAR] %@", jsonCategories);
        //    [self.nextEventWidget setCategories:[jsonCategories objectForKey:@"value"]];
        //}];
        
        // load events
        ShowTomorrow showTomorrow = (ShowTomorrow) [[NSUserDefaults standardUserDefaults] doubleForKey:@"outlookShowTomorrow"];
        [self.outlook getCalendarEvents:showTomorrow completionBlock:^(NSDictionary * jsonCalendar) {
            
            // check
            NSArray<NSDictionary*>* jsonEvents = [jsonCalendar objectForKey:@"value"];
            if (jsonEvents == nil || [jsonEvents count] == 0) {
                // make sure it is reload in 60 seconds
                self.lastFetch = [[NSDate date] dateByAddingTimeInterval:-FETCH_CALENDAR_EVERY_SECONDS + FETCH_CALENDAR_EVERY_SECONDS_IF_EMPTY];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setActiveIndex:EMPTY_INDEX];
                });
                return;
            }
            
            // record and ensure it will be reloaded next time
            self.lastFetch = [[NSDate date] dateByAddingTimeInterval:-REFRESH_TIMER_DELAY];
            
            // process
            NSArray<OutlookEvent*>* events = [OutlookEvent listFromJson:jsonEvents];
            
            // filter
            NSMutableArray<OutlookEvent*>* filtered = [NSMutableArray<OutlookEvent*> array];
            for (OutlookEvent* event in events) {
                
                // skip cancelled
                if (event.cancelled == YES) {
                    continue;
                }
                
                // skip all day events
                if (event.allDay == YES) {
                    continue;
                }
                
                // skip out of office we do not organize
                if (event.showAs == ShowAsOutOfOffice) {
                    if ([event.organizerName isEqualTo:self.outlook.currentAccount.username] == NO) {
                        continue;
                    }
                }
                
                // valid
                [filtered addObject:event];
                
            }
#if DUMP
            for (OutlookEvent* event in filtered) {
                LOG("[CALENDAR] Event = %@", event);
            }
#endif
            
            // now load
            [self.nextEventWidget showEvents:[filtered sortedArrayUsingSelector:@selector(compare:)]];
            
        }];
        
    }];
}

- (void)viewWillDisappear {
    [self.refreshTimer invalidate];
}

- (void)updateReloadingAccount:(BOOL) reloadAccount reloadingEvents:(BOOL) reloadEvents {
    
    // clear previous account
    if (reloadAccount == YES) {
        self.outlook = [[[Outlook alloc] init] autorelease];
        reloadEvents = YES;
    }
    
    // main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // do we have an account
        if (self.outlook.currentAccount == nil) {
            [self setActiveIndex:SIGNIN_INDEX];
            return;
        }
        
        // reload
        if (reloadEvents == YES) {
            [self setActiveIndex:LOADING_INDEX];
            [self reloadEvents];
        } else if (self.activeIndex == EVENT_INDEX || self.activeIndex == EMPTY_INDEX) {
            [self.nextEventWidget selectEvent];
        }
        
        // recalc
        [self.view invalidateIntrinsicContentSize];
        
    });
    
}

@end

//
//  OutlookEvent.m
//  EnergyBar
//
//  Created by Nicolas Bonamy on 9/27/20.
//  Copyright © 2020 Nicolas Bonamy. All rights reserved.
//

#import "OutlookEvent.h"
#import "NSDate+Utils.h"

#define EVENT_STARTING_DELTA_MINUTES 3
#define EVENT_NOW_DELTA EVENT_STARTING_DELTA_MINUTES*60
#define EVENT_IN_PROGRESS_FOR 10*60
#define EVENT_SOON_DELTA 1*60*60
#define EVENT_CLOSE_DELTA 4*60*60

@interface NSDictionary(Json)
- (id) getJsonValue:(NSString*) key;
- (id) getJsonValue:(NSString*) key sub:(NSString*) subkey;
@end

@implementation NSDictionary(Json)

- (id) getJsonValue:(NSString*) key {
    id value = [self objectForKey:key];
    return (IsValid(value) ? value : nil);
}

- (id) getJsonValue:(NSString*) key sub:(NSString*) subkey {
    NSDictionary* dict = [self objectForKey:key];
    return (IsValid(dict) ? [dict getJsonValue:subkey] : nil);
}

- (id) getJsonValue:(NSString*) key sub1:(NSString*) subkey1 sub2:(NSString*) subkey2 {
    NSDictionary* dict = [self objectForKey:key];
    if (IsValid(dict)) {
        dict = [dict objectForKey:subkey1];
        if (IsValid(dict)) {
            return [dict getJsonValue:subkey2];
        }
    }
    return nil;
}

@end

@implementation OutlookEvent

- (NSString*) description {
    return [NSString stringWithFormat:@"[EVENT] %@: %@ (%@)", self.startTime, self.title, [self.categories componentsJoinedByString:@"/"]];
}

- (id) init {
    self = [super init];
    self.showAs = ShowAsUnknown;
    self.importance = ImportanceNormal;
    return self;
}

- (id) initWithJson:(NSDictionary*) jsonEvent {
    
    // start with easy one
    self = [self init];
    self.uid = [jsonEvent getJsonValue:@"id"];
    self.title = [jsonEvent getJsonValue:@"subject"];
    self.webLink = [jsonEvent getJsonValue:@"webLink"];
    self.cancelled = [[jsonEvent getJsonValue:@"isCancelled"] boolValue];

    // organizer
    self.organizerName = [jsonEvent getJsonValue:@"organizer" sub1:@"emailAddress" sub2:@"name"];
    self.organizerEmail = [jsonEvent getJsonValue:@"organizer" sub1:@"emailAddress" sub2:@"address"];

    // show as
    self.showAs = ShowAsUnknown;
    NSString* jsonShowAs = [jsonEvent getJsonValue:@"showAs"];
    if ([jsonShowAs caseInsensitiveCompare:@"free"] == NSOrderedSame) {
        self.showAs = ShowAsFree;
    } else if ([jsonShowAs caseInsensitiveCompare:@"busy"] == NSOrderedSame) {
        self.showAs = ShowAsBusy;
    } else if ([jsonShowAs caseInsensitiveCompare:@"tentative"] == NSOrderedSame) {
        self.showAs = ShowAsTentative;
    } else if ([jsonShowAs caseInsensitiveCompare:@"oof"] == NSOrderedSame) {
        self.showAs = ShowAsOutOfOffice;
    } else if ([jsonShowAs caseInsensitiveCompare:@"workingelsewhere"] == NSOrderedSame) {
        self.showAs = ShowAsBusy;
    }
    
    // importance
    self.importance = ImportanceNormal;
    NSString* jsonImportance = [jsonEvent getJsonValue:@"importance"];
    if ([jsonImportance caseInsensitiveCompare:@"low"] == NSOrderedSame) {
        self.importance = ImportanceLow;
    } else if ([jsonImportance caseInsensitiveCompare:@"high"] == NSOrderedSame) {
        self.importance = ImportanceHigh;
    }
    
    // start date: 2020-09-28T01:00:00.0000000
    NSString* jsonStartDate = [jsonEvent getJsonValue:@"start" sub:@"dateTime"];
    NSString* jsonEndDate = [jsonEvent getJsonValue:@"end" sub:@"dateTime"];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS"];
    self.startTime = [dateFormatter dateFromString:jsonStartDate];
    self.endTime = [dateFormatter dateFromString:jsonEndDate];
    self.allDay = [[jsonEvent getJsonValue:@"isAllDay"] boolValue];
    
    // categories
    self.categories = [jsonEvent getJsonValue:@"categories"];
    if ([self.categories isKindOfClass:[NSArray class]] == NO) {
        self.categories = [NSArray array];
    }

    // online provider
    self.onlineProvider = [jsonEvent getJsonValue:@"onlineMeetingProvider"];

    // join url basic info
    self.joinUrl = [jsonEvent getJsonValue:@"onlineMeetingUrl"];
    if (IsValidString(self.joinUrl) == NO) {
        self.joinUrl = [jsonEvent getJsonValue:@"onlineMeeting" sub:@"joinUrl"];
    }
    
    // parse body for teams
    if (IsValidString(self.joinUrl) == NO) {
        NSString* body = [jsonEvent getJsonValue:@"body" sub:@"content"];
        NSRange rangeStart = [body rangeOfString:@"https://teams.microsoft.com/l/meetup-join/"];
        if (rangeStart.location != NSNotFound) {
            NSRange rangeEnd = [body rangeOfString:@"\"" options:0 range:NSMakeRange(rangeStart.location, body.length - rangeStart.location)];
            if (rangeEnd.location != NSNotFound) {
                self.joinUrl = [body substringWithRange:NSMakeRange(rangeStart.location, rangeEnd.location - rangeStart.location)];
            }
        }
    }
    
    // parse body for webex
    if (IsValidString(self.joinUrl) == NO) {
        NSString* body = [jsonEvent getJsonValue:@"body" sub:@"content"];
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:@"https://.*\\.webex.com/.*/j.php[^\"]*"
            options:NSRegularExpressionCaseInsensitive
            error:nil];
        [regex enumerateMatchesInString:body options:0 range:NSMakeRange(0, body.length)
                             usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            self.joinUrl = [[[body substringWithRange:match.range] componentsSeparatedByString:@"\""] objectAtIndex:0];
            *stop = YES;
        }];

    }
    
    // check
    if (IsValidString(self.joinUrl) == NO) {
        [self setJoinUrl:nil];
    }

    // done
    return self;
    
}

- (void) dealloc {
    
    [self.uid release];
    [self.title release];
    [self.categories release];
    [self.startTime release];
    [self.endTime release];
    [self.webLink release];
    [self.joinUrl release];
    
    [super dealloc];
    
}

- (NSString*) startTimeDesc {
    
    // now
    if ([self isInProgress]) {
        return @"Now";
    }
    
    // needed to compare
    NSDate* date = self.startTime;
    NSDate* reference = [[NSDate date] dateBySettingSeconds:0];
    NSTimeInterval interval = [date timeIntervalSinceDate:reference];
    
    // soon
    if (interval > 0 && interval <= EVENT_SOON_DELTA) {
        return [NSString stringWithFormat:@"In %@", [OutlookEvent formatDuration:interval longMinutes:YES]];
    }
    
    // get components
    NSDateComponents* nowComponents = [reference components];
    NSDateComponents* eventComponents = [date components];;
    
    // need a date formatter
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterNoStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    
    // final
    if (eventComponents.day == nowComponents.day) {
        return [NSString stringWithFormat:@"Today, %@", [dateFormatter stringFromDate:date]];
    } else if (eventComponents.day == nowComponents.day + 1) {
        return [NSString stringWithFormat:@"Tomorrow, %@", [dateFormatter stringFromDate:date]];
    } else {
        // default
        [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
        return [dateFormatter stringFromDate:date];
    }
}

- (NSString*) durationDesc {
    
    // need an end time
    if (self.endTime == nil) {
        return nil;
    } else {
        return [OutlookEvent formatDuration:[self.endTime timeIntervalSinceDate:self.startTime] longMinutes:NO];
    }
}

+ (NSString*) formatDuration:(NSTimeInterval) duration longMinutes:(BOOL) longMinutes {
    
    duration = round(duration / 60);
    int hours = floor(duration / 60);
    int minutes = duration - hours * 60;
    if (hours == 0) {
        minutes = MAX(1, minutes);
        NSString* suffix = longMinutes ? (minutes == 1 ? @"minute" : @"minutes") : @"min";
        return [NSString stringWithFormat:@"%d %@", minutes, suffix];
    } else {
        if (minutes == 0) {
            return [NSString stringWithFormat:@"%dh", hours];
        } else {
            return [NSString stringWithFormat:@"%dh%02d", hours, minutes];
        }
    }

}

- (NSString*) timingDesc {
    
    // progress
    if ([self isInProgress]) {
        
        NSString* timeLeft = [OutlookEvent formatDuration:[self.endTime timeIntervalSinceMinuteStart] longMinutes:YES];
        if ([self isStarting]) {
            return [NSString stringWithFormat:@"Now, %@ left", timeLeft];
        } else {
            return [NSString stringWithFormat:@"%@ left", timeLeft];
        }
    }
    
    // needed
    NSString* startDesc = [self startTimeDesc];
    NSString* durationDesc = [self durationDesc];

    // else
    if (durationDesc == nil) {
        return startDesc;
    } else {
        return [NSString stringWithFormat:@"%@ (%@)", startDesc, durationDesc];
    }
    
}

- (NSTimeInterval) intervalWithNow {
    return [self.startTime timeIntervalSinceMinuteStart];
}

- (BOOL) canBeJoined {
    return [self isStarting] || [self isInProgress];
}

- (BOOL) isStarting {
    return [self.startTime isNowWithinMinutes:EVENT_STARTING_DELTA_MINUTES];
}

- (BOOL) isStarted {
    return [self.startTime isInPast];
}

- (BOOL) isEnded {
    return [self.endTime isInPast];
}

- (BOOL) isInProgress {
    return [self isStarted] == YES && [self isEnded] == NO;
}

- (BOOL) isSkype {
    return [self.onlineProvider isEqualToString:@"skypeForBusiness"];
}

- (BOOL) isTeams {
    return
        [self.onlineProvider isEqualToString:@"teamsForBusiness"] ||
        [self.joinUrl localizedCaseInsensitiveContainsString:@"teams.microsoft.com"];
}

- (BOOL) isWebEx {
    return [self.joinUrl localizedCaseInsensitiveContainsString:@"webex.com"];
}

- (NSString*) directJoinUrl {
    
    // microsoft teams meeting
    if (self.isTeams) {
        NSString* directJoinUrl = self.joinUrl;
        directJoinUrl = [directJoinUrl stringByReplacingOccurrencesOfString:@"https://teams.microsoft.com/" withString:@"msteams:"];
        directJoinUrl = [directJoinUrl stringByAppendingString:@"&anon=true&launchAgent=join_launcher&type=meetup-join&directDl=true&msLaunch=true&enableMobilePage=true&fqdn=teams.microsoft.com"];
        return directJoinUrl;
    }
    
    // default
    return self.joinUrl;
    
}

- (NSComparisonResult) compare:(OutlookEvent*) other {
    
    // same
    if ([self.uid isEqualToString:other.uid]) {
        return NSOrderedSame;
    }
    
    // date is first
    NSComparisonResult dateCompare = [self.startTime compare:other.startTime];
    if (dateCompare != NSOrderedSame) {
        return dateCompare;
    }
    
    // busy first
    int diff = self.showAs - other.showAs;
    if (diff > 0) return NSOrderedAscending;
    if (diff < 0) return NSOrderedDescending;
    return NSOrderedSame;
    
}

+ (NSArray*) listFromJson:(NSArray*) jsonArray {
    NSMutableArray* array = [NSMutableArray array];
    if (jsonArray != nil) {
        for (NSDictionary* dict in jsonArray) {
            OutlookEvent* event = [[OutlookEvent alloc] initWithJson:dict];
            [array addObject:event];
        }
    }
    return [NSArray arrayWithArray:array];
}


+ (OutlookEvent*) findSoonestEvent:(NSArray*) events busyOnly:(BOOL)busyOnly {
    
    // check
    if (events == nil || events.count == 0) {
        return nil;
    }
    
    // best
    OutlookEvent* soonest = nil;
    for (OutlookEvent* event in events) {
        
        // discard old events
        NSTimeInterval interval = [event intervalWithNow];
        if (interval < -EVENT_IN_PROGRESS_FOR) {
            continue;
        }
        
        // only busy
        if (busyOnly && event.showAs != ShowAsBusy) {
            continue;
        }
        
        // first is best
        if (soonest == nil) {
            soonest = event;
            continue;
        }
        
        // if same date
        if ([event.startTime isEqualToDate:soonest.startTime] == NO) {
            break;
        }
        
        // compare show As
        int delta = event.showAs - soonest.showAs;
        if (delta > 0) {
            soonest = event;
        }
        
    }
    
    // done
    return soonest;

}

@end

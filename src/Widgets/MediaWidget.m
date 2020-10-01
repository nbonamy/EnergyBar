//
//  MediaWidget.m
//  EnergyBar
//
//  Created by Nicolas Bonamy on 9/30/20.
//  Copyright © 2020 Bill Zissimopoulos. All rights reserved.
//

#import "MediaWidget.h"
#import "MediaControlsWidget.h"
#import "MediaAllInOneWidget.h"

@implementation MediaWidget

- (void)commonInit
{
    // dynamic sizing
    self.dynamicSizing = YES;

    // add widgets
    [self addWidget:[[MediaControlsWidget alloc] initWithIdentifier:@"_mediaControls"]];
    [self addWidget:[[MediaAllInOneWidget alloc] initWithIdentifier:@"_volumeAllInOne"]];

}

- (void)viewWillAppear {
    BOOL showsSmallWidget = [[NSUserDefaults standardUserDefaults] boolForKey:@"mediaShowsSmallWidget"];
    [self setShowsSmallWidget:showsSmallWidget];
}

- (void)setShowsSmallWidget:(BOOL)value
{
    [self setActiveIndex:value ? 1 : 0];
    [self.view invalidateIntrinsicContentSize];
}

@end

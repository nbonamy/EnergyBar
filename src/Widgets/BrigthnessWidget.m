/**
 * @file BrightnessControlWidget.m
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

#import "BrightnessWidget.h"
#import "Brightness.h"
#import "BezelWindow.h"
#import "MediaKeys.h"

#define BrightnessAdjustIncrement			 (1.0/16.0)

@implementation BrightnessWidget

- (void)commonInit
{
    NSSegmentedControl *control = [NSSegmentedControl
        segmentedControlWithImages:[NSArray arrayWithObjects:
            [NSImage imageNamed:@"BrightnessDown"],
            [NSImage imageNamed:@"BrightnessUp"],
            nil]
        trackingMode:NSSegmentSwitchTrackingMomentary
        target:self
        action:@selector(click:)];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    control.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    control.tag = 'ctrl';
    
    for (int i=0; i<control.segmentCount; i++) {
        [control setWidth:56 forSegment:i];
    }
    
    self.customizationLabel = @"Brigthness";
    self.view = control;
    
}

- (void)adjustBrightnessBy:(double)delta {
    double brgt = GetDisplayBrightness(0);
    brgt = MAX(0, MIN(1, brgt + delta));
    SetDisplayBrightness(0, brgt);
    [BezelWindow showWithType:kBrightness andValue:brgt];
}

- (void)click:(id)sender
{
    NSSegmentedControl *control = sender;
    switch (control.selectedSegment)
    {
        case 0:
            // brightness down
            HIDPostAuxKeyPress(NX_KEYTYPE_BRIGHTNESS_DOWN);
            //[self adjustBrightnessBy:-BrightnessAdjustIncrement];
            break;
        case 1:
            // brightness up
            HIDPostAuxKeyPress(NX_KEYTYPE_BRIGHTNESS_UP);
            //[self adjustBrightnessBy:+BrightnessAdjustIncrement];
            break;
    }
}

@end

/**
 * @file MicMuteWidget.m
 *
 * @copyright 2020 Nicolas Bonamy
 */
/*
 * This file is part of EnergyBar.
 *
 * You can redistribute it and/or modify it under the terms of the GNU
 * General Public License version 3 as published by the Free Software
 * Foundation.
 */

#import "MicMuteWidget.h"
#import "ImageTitleView.h"
#import "AudioControl.h"
#import "BezelWindow.h"
#import "NSColor+Hex.h"
#import "KeyEvent.h"

@interface MicMuteWidgetView : ImageTitleView
@end

@implementation MicMuteWidgetView
- (NSSize)intrinsicContentSize
{
    return NSMakeSize(WIDGET_STANDARD_WIDTH, NSViewNoIntrinsicMetric);
}
@end

@interface MicMuteWidget()
@property (retain) NSRunningApplication* runningApplication;
@property (assign) BOOL muteToRestore;
@property (assign) BOOL restoreMute;
@end

@implementation MicMuteWidget

- (void)commonInit
{
    // experimental
    //self.applicationMute = NO;
    
    self.customizationLabel = @"Mic Mute";
    self.micOnImage = [NSImage imageNamed:@"MicOn"];
    self.micOffImage = [NSImage imageNamed:@"MicOff"];
    
    ImageTitleView *view = [[[MicMuteWidgetView alloc] initWithFrame:NSZeroRect] autorelease];
    view.wantsLayer = YES;
    view.layer.cornerRadius = 6.0;
    view.imageSize = NSMakeSize(36, 36);
    view.layoutOptions = ImageTitleViewLayoutOptionImage;
    
    NSClickGestureRecognizer *tapRecognizer = [[[NSClickGestureRecognizer alloc]
                                                initWithTarget:self action:@selector(tapAction:)] autorelease];
    tapRecognizer.allowedTouchTypes = NSTouchTypeMaskDirect;
    [view addGestureRecognizer:tapRecognizer];
    
    self.view = view;
    
    [AudioControl sharedInstanceInput];
    [self setMicMuteImage];

}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter]
     removeObserver:self];
    
    [super dealloc];
}

- (void)viewWillAppear
{
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(audioControlNotification:)
     name:AudioControlNotification
     object:nil];

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserver:self
        selector:@selector(didActivateApplication:)
        name:NSWorkspaceDidActivateApplicationNotification
        object:nil];
    
    [self checkRunningApplication];

}

- (void)viewDidDisappear
{
    [[NSNotificationCenter defaultCenter]
     removeObserver:self];
}

- (void)setApplicationMute:(BOOL)value
{
    self->_applicationMute = value;
    [self checkRunningApplication];
}

- (void)audioControlNotification:(NSNotification *)notification
{
    [self setMicMuteImage];
}

- (void)setMicMuteImage
{
    // when application mute we do not know the status
    if (self.applicationMute) {
        if ([self isTeamsRunning]) {
            [((ImageTitleView*) self.view) setImage:self.micOnImage];
            self.view.layer.backgroundColor = [[NSColor colorFromHex:0x0078d4] CGColor];
            return;
        }
    }
    
    // default
    BOOL mute = [AudioControl sharedInstanceInput].mute;
    NSImage* image = mute ? _micOffImage : _micOnImage;
    NSColor* bgColor = mute ? [NSColor redColor] : [NSColor colorFromHex:0x008000];
    [((ImageTitleView*) self.view) setImage:image];
    self.view.layer.backgroundColor = [bgColor CGColor];
}

- (void)tapAction:(id)sender
{
    
    if (self.applicationMute) {
    
        if ([self isTeamsRunning]) {
        
            CGEventRef eventDown;
            eventDown = CGEventCreateKeyboardEvent (NULL, (CGKeyCode)46, true);//or 20
            CGEventSetFlags(eventDown, kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
            CGEventPost(kCGSessionEventTap, eventDown);
            CFRelease(eventDown);

            CGEventRef eventUp;
            eventUp = CGEventCreateKeyboardEvent (NULL, (CGKeyCode)46, false);//or 20
            CGEventSetFlags(eventUp, kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
            CGEventPost(kCGSessionEventTap, eventUp);
            CFRelease(eventUp);
            
            // done
            return;

        }
        
    }
        
    // modify
    BOOL mute = [AudioControl sharedInstanceInput].mute;
    [AudioControl sharedInstanceInput].mute = !mute;
    
    // reload to make sure something happened
    mute = [AudioControl sharedInstanceInput].mute;
    [BezelWindow showLevelFor:(mute ? kAudioInputMute : kAudioInputOn) withValue:-1];
    [self setMicMuteImage];

}

- (void)didActivateApplication:(NSNotification *)notification
{
    [self checkRunningApplication];
}

- (void)checkRunningApplication
{
    // restore
    if (self.restoreMute) {
        [AudioControl sharedInstanceInput].mute = self.muteToRestore;
        self.restoreMute = NO;
    }
    
    // update
    self.runningApplication = [[NSWorkspace sharedWorkspace] menuBarOwningApplication];
    
    // check if we use application mute
    if (self.applicationMute) {
        if ([self isTeamsRunning]) {
            
            // save
            self.muteToRestore = [AudioControl sharedInstanceInput].mute;
            self.restoreMute = YES;
            
            // now unmute
            [AudioControl sharedInstanceInput].mute = FALSE;
        }
    }
    
    // update
    [self setMicMuteImage];

}

- (BOOL) isTeamsRunning {
    return [self.runningApplication.bundleIdentifier isEqualToString:@"com.microsoft.teams"];
}

@end

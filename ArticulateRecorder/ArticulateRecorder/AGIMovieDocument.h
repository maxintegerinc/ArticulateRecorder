//
//  AGIDocument.h
//  ArticulateRecorder
//
//  Created by Christopher Miller on 4/9/14.
//  Copyright (c) 2014 Articulate Global, Inc. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AGIMovieDocument : NSDocument

// views and controls
@property (weak) IBOutlet NSView *previewView;
@property (weak) IBOutlet NSLevelIndicator *audioLevelMeter;
@property (assign) float previewVolume;

// devices
@property (strong) NSArray *videoDevices;
@property (strong) NSArray *audioDevices;

@property (weak) AVCaptureDevice *selectedVideoDevice;
@property (weak) AVCaptureDevice *selectedAudioDevice;

// recording
@property (readonly) BOOL hasRecordingDevice;
@property (assign, getter=isRecording) BOOL recording;
@property (weak) IBOutlet NSTextField *recordedDurationLabel;
@property (strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (weak) IBOutlet NSTextField *captionTextField;

// volume
@property (weak) IBOutlet NSSlider *volumeSlider;
- (IBAction)volumeDown:(id)sender;
- (IBAction)volumeUp:(id)sender;

@end

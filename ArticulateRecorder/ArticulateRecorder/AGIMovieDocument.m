//
//  AGIDocument.m
//  ArticulateRecorder
//
//  Created by Christopher Miller on 4/9/14.
//  Copyright (c) 2014 Articulate Global, Inc. All rights reserved.
//


// connect bindings
// add caption code
// add CMTimer

#import "AGIMovieDocument.h"

@interface AGIMovieDocument () <AVCaptureFileOutputRecordingDelegate>

@property (strong) AVCaptureSession *captureSession;
@property (strong) AVCaptureAudioPreviewOutput *audioPreviewOutput;

@property (strong) AVCaptureDeviceInput *videoDeviceInput;
@property (strong) AVCaptureDeviceInput *audioDeviceInput;

@property (readonly) BOOL selectedVideoDeviceProvidesAudio;

@property (strong) NSArray *observers;
@property (weak) NSTimer *audioLevelTimer;

@end

@implementation AGIMovieDocument {
    dispatch_queue_t sessionQueue;
}

#pragma mark - NSDocument

- (id)init {
    self = [super init];
    if (self) {
        
        // create dispatch queue
        sessionQueue = dispatch_queue_create("agi_session_queue", DISPATCH_QUEUE_SERIAL);

        // configure capture session
        [self configureCaptureSession];
        
        // add observers
        [self addObservers];
        
        // outputs
        [self configureMovieFileOutput];
        [self configureAudioPreviewOutput];
        
        // select default devices
        [self configureDefaultCaptureDevice];
        
        // refresh device list
        [self refreshDevices];
    }
    
    return self;
}

- (NSString *)windowNibName {
    return @"AGIMovieDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController {
    [super windowControllerDidLoadNib:aController];
    
    // add preview layer
    [self configureVideoPreviewLayer];
    
    dispatch_async(sessionQueue, ^{
        [self.captureSession startRunning];
    });
    
    self.audioLevelTimer = [NSTimer scheduledTimerWithTimeInterval:0.1f target:self selector:@selector(updateAudioLevels:) userInfo:nil repeats:YES];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    
    // let go of the audio meter timer
    [self.audioLevelTimer invalidate];
    
    // stop capture session
    [self.captureSession stopRunning];
    
    // remove observers
	for (id observer in self.observers) {
		[[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
}

#pragma mark - Properties

- (BOOL)hasRecordingDevice {
	return ((self.videoDeviceInput != nil) || (self.audioDeviceInput != nil));
}

- (BOOL)isRecording {
	return self.movieFileOutput.isRecording;
}

- (void)setRecording:(BOOL)record {
	if (record) {
		// record to a temporary file
		[self.movieFileOutput startRecordingToOutputFileURL:[self tempFileURL] recordingDelegate:self];
	} else {
		[self.movieFileOutput stopRecording];
	}
    
    [self toggleRecordDurationTimer];
}

- (AVCaptureDevice *)selectedVideoDevice {
	return self.videoDeviceInput.device;
}

- (void)setSelectedVideoDevice:(AVCaptureDevice *)selectedVideoDevice {
    
	[self.captureSession beginConfiguration];
	
	if (self.videoDeviceInput) {
        
		// remove current video input device
		[self.captureSession removeInput:self.videoDeviceInput];
		self.videoDeviceInput = nil;
	}
	
	if (selectedVideoDevice) {
        
		NSError *error = nil;
		
		// create the new video device input and add it to the capture session
		AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedVideoDevice error:&error];
        
		if (newVideoDeviceInput == nil) {
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[self presentError:error];
			});
		} else {
			if (![selectedVideoDevice supportsAVCaptureSessionPreset:self.captureSession.sessionPreset]) {
				self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
			}
            
			self.videoDeviceInput = newVideoDeviceInput;
			[self.captureSession addInput:self.videoDeviceInput];
		}
	}
	
	// use video audio if available
	if (self.selectedVideoDeviceProvidesAudio) {
		self.selectedAudioDevice = nil;
	}
    
	[self.captureSession commitConfiguration];
}

- (AVCaptureDevice *)selectedAudioDevice {
	return self.audioDeviceInput.device;
}

- (void)setSelectedAudioDevice:(AVCaptureDevice *)selectedAudioDevice {
    
	[self.captureSession beginConfiguration];
	
	if (self.audioDeviceInput) {

        // remove current audio input device
        [self.captureSession removeInput:self.audioDeviceInput];
		self.audioDeviceInput = nil;
	}
	
	if (selectedAudioDevice && ![self selectedVideoDeviceProvidesAudio]) {
        
		NSError *error = nil;
		
		// create the new audio device input and add it to the capture session
		AVCaptureDeviceInput *newAudioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedAudioDevice error:&error];
        
		if (newAudioDeviceInput == nil) {
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[self presentError:error];
			});
		} else {
			if (![selectedAudioDevice supportsAVCaptureSessionPreset:self.captureSession.sessionPreset]) {
				[self.captureSession setSessionPreset:AVCaptureSessionPresetHigh];
            }
			
            self.audioDeviceInput = newAudioDeviceInput;
            [self.captureSession addInput:self.audioDeviceInput];
		}
	}
	
	[self.captureSession commitConfiguration];
}

- (float)previewVolume {
	return self.audioPreviewOutput.volume;
}

- (void)setPreviewVolume:(float)newPreviewVolume {
	self.audioPreviewOutput.volume = newPreviewVolume;
}

#pragma mark - Private

/**
 *  Create and configure capture device and device input.
 */
- (void)configureDefaultCaptureDevice {
    
    NSLog(@"Entering %s", __PRETTY_FUNCTION__);
    
    AVCaptureDevice *muxedDevice = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeMuxed];
    
    if (muxedDevice) {
        
		NSLog (@"Found a default muxed capture device");
        self.selectedVideoDevice = muxedDevice;
        
	} else {
        
		AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeVideo];
		if (videoDevice) {
            
			NSLog (@"Found a default video capture device");
            self.selectedVideoDevice = videoDevice;
		}
        
		AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeAudio];
		if (audioDevice) {
            
			NSLog (@"Found a default audio device");
            self.selectedAudioDevice = audioDevice;
		}
	}
}

/**
 *  Create a session, and pre-configure it with settings suitable for high quality video and audio output.
 */
- (void)configureCaptureSession {
    
    NSLog(@"Entering %s", __PRETTY_FUNCTION__);
    
    if (_captureSession == nil) {
        _captureSession = [AVCaptureSession new];
    }
    
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
}

/**
 *  Create and configure movie file output.
 */
- (void)configureMovieFileOutput {
    
    NSLog(@"Entering %s", __PRETTY_FUNCTION__);
    
	_movieFileOutput = [AVCaptureMovieFileOutput new];
	[self.captureSession addOutput:self.movieFileOutput];
}

/**
 *  Create and configure movie file output.
 */
- (void)configureAudioPreviewOutput {
    
    NSLog(@"Entering %s", __PRETTY_FUNCTION__);
    
    _audioPreviewOutput = [AVCaptureAudioPreviewOutput new];
    self.audioPreviewOutput.volume = 0.0f;
    [self.captureSession addOutput:self.audioPreviewOutput];
}

/**
 *  Create and configure video preview layer.
 */
- (void)configureVideoPreviewLayer {
    
    NSLog(@"Entering %s", __PRETTY_FUNCTION__);
    
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    previewLayer.frame = self.previewView.bounds;
    previewLayer.backgroundColor = [NSColor blackColor].CGColor;
    previewLayer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.previewView.layer addSublayer:previewLayer];
}

- (BOOL)selectedVideoDeviceProvidesAudio {
	return ([self.selectedVideoDevice hasMediaType:AVMediaTypeMuxed] || [self.selectedVideoDevice hasMediaType:AVMediaTypeAudio]);
}

- (void)toggleRecordDurationTimer {
    
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (timer) {
        uint64_t milliseconds = 500ull;
        uint64_t interval = milliseconds * NSEC_PER_MSEC;
        uint64_t leeway = 100ull * NSEC_PER_MSEC;
        __block typeof(self) _self = self;
        
        dispatch_source_set_timer(timer, dispatch_walltime(NULL, 0), interval, leeway);
        dispatch_source_set_event_handler(timer, ^{
            if ( _self.movieFileOutput.isRecording) {
                NSTimeInterval duration = CMTimeGetSeconds(_self.movieFileOutput.recordedDuration);
                int hours = duration / (60 * 60);
                int minutes = (duration - (hours*60*60)) / 60;
                int seconds = (duration - (hours*60*60) - (minutes*60));
                if (seconds > 0) {
                    _self.recordedDurationLabel.stringValue = [NSString stringWithFormat:@"%02d:%02d:%02d", hours, minutes, seconds];
                }
            }
            else {
                dispatch_source_cancel(timer);
                _self.recordedDurationLabel.stringValue = @"00:00:00";
            }
        });
        
        dispatch_resume(timer);
    }
}

- (CALayer *)captionLayerForSize:(CGSize)videoSize {
    
    NSLog(@"Entering %s", __PRETTY_FUNCTION__);

    // Create a layer for the title animation
    CALayer *captionLayer = [CALayer layer];
    
    // Create a layer for the text of the title.
	CATextLayer *titleLayer = [CATextLayer layer];
	titleLayer.string = self.captionTextField.stringValue;
	titleLayer.font = (__bridge void*)[NSFont fontWithName:@"Helvetica" size:videoSize.height/6] ;
	titleLayer.shadowOpacity = 0.5;
	titleLayer.alignmentMode = kCAAlignmentCenter;
	titleLayer.bounds = CGRectMake(0, 0, videoSize.width/2, videoSize.height/2);
	
	// Add it to the overall layer.
	[captionLayer addSublayer:titleLayer];
    [captionLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
    
    return captionLayer;
}

- (void)updateAudioLevels:(NSTimer *)timer {
    
	NSInteger channelCount = 0;
	float decibels = 0.f;
	
	// Sum all of the average power levels and divide by the number of channels
	for (AVCaptureConnection *connection in self.movieFileOutput.connections) {
		for (AVCaptureAudioChannel *audioChannel in connection.audioChannels) {
			decibels += audioChannel.averagePowerLevel;
			channelCount += 1;
		}
	}
	
	decibels /= channelCount;
	
	self.audioLevelMeter.floatValue = (pow(10.f, 0.05f * decibels) * 20.0f);
}

- (void)refreshDevices {
    
    // video devices
    self.videoDevices = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]];
    NSLog(@"Video devices: %@", self.videoDevices);
    
    // audio devices
    self.audioDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    NSLog(@"Audio devices: %@", self.audioDevices);

    // nil out unavailable devices
    [self.captureSession beginConfiguration];
    
    if (![self.videoDevices containsObject:self.selectedVideoDevice]) {
		self.selectedVideoDevice = nil;
	}
    
	if (![self.audioDevices containsObject:self.selectedAudioDevice]) {
		self.selectedAudioDevice = nil;
    }
    
    [self.captureSession commitConfiguration];
}

/**
 *  Creates a temporary file name.
 *  
 *  Will delete the file if it already exists!
 *
 *  @return NSURL for a temporary file
 */
- (NSURL *)tempFileURL {
    
    NSString *outputPath = [NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), @"recordr.mov"];
    NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:outputPath]) {
        [fileManager removeItemAtPath:outputPath error:nil];
    }
    
    NSLog(@"Temp file URL: %@", outputURL);
    
    return outputURL;
}

#pragma mark - Keypaths

+ (NSSet *)keyPathsForValuesAffectingSelectedVideoDeviceProvidesAudio {
	return [NSSet setWithObjects:@"selectedVideoDevice", nil];
}

+ (NSSet *)keyPathsForValuesAffectingHasRecordingDevice {
	return [NSSet setWithObjects:@"selectedVideoDevice", @"selectedAudioDevice", nil];
}

+ (NSSet *)keyPathsForValuesAffectingRecording {
	return [NSSet setWithObject:@"movieFileOutput.recording"];
}

+ (NSSet *)keyPathsForValuesAffectingRecordedDuration {
	return [NSSet setWithObject:@"movieFileOutput.recordedDuration"];
}

+ (NSSet *)keyPathsForValuesAffectingLocalizedName {
	return [NSSet setWithObject:@"videoDevices.localizedName"];
}

#pragma mark - Actions

/**
 *  Set volume to MIN level.
 *
 *  @param sender Volume Down button
 */
- (IBAction)volumeDown:(id)sender {
    [self.volumeSlider setDoubleValue:0.0];
}

/**
 *  Set volume to MAX level.
 *
 *  @param sender Volume Up button
 */
- (IBAction)volumeUp:(id)sender {
    [self.volumeSlider setDoubleValue:1.0];
}

/**
 *  Adds AVCaptureXXX observers
 */
- (void)addObservers {
    
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    // Session Runtime Error Notification
    id runtimeErrorObserver = [notificationCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification
                                                              object:self.captureSession
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *note) {
                                                              dispatch_async(dispatch_get_main_queue(), ^(void) {
                                                                  [self presentError:note.userInfo[AVCaptureSessionErrorKey]];
                                                              });
                                                          }];

    // Device Was Connected Notification
    id deviceWasConnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification
                                                                    object:nil
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    [self refreshDevices];
                                                                }];
    
    // Device Was Disconnected Notification
    id deviceWasDisconnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification
                                                                       object:nil
                                                                        queue:[NSOperationQueue mainQueue]
                                                                   usingBlock:^(NSNotification *note) {
                                                                       [self refreshDevices];
                                                                   }];
    
    _observers = @[runtimeErrorObserver, deviceWasConnectedObserver, deviceWasDisconnectedObserver];
}


#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections {
	NSLog(@"Did start recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error {
    NSLog(@"Did finish recording to %@", [outputFileURL description]);
    
    if (error != nil && [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue] == NO) {
		[[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			[self presentError:error];
		});
	} else {

        [self askUserToSave:outputFileURL];

	}
}

- (void)applyCaptionForAssetAtURL:(NSURL *)assetURL output:(NSURL *)outputURL {
    
    AVAsset *asset = [AVAsset assetWithURL:assetURL];
    
    AVAssetTrack *videoTrack = nil;
    AVAssetTrack *audioTrack = nil;
    CALayer *captionLayer = nil;
    AVMutableVideoComposition *mutableVideoComposition = nil;
    
    // Check if the asset contains video and audio tracks
    if ([[asset tracksWithMediaType:AVMediaTypeVideo] count] != 0) {
        videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    }
    
    if ([[asset tracksWithMediaType:AVMediaTypeAudio] count] != 0) {
        audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    }
    
    CMTime insertionPoint = kCMTimeZero;
    NSError * error = nil;
    AVMutableComposition *mutableComposition = [AVMutableComposition composition];
    
    // Insert the video and audio tracks from AVAsset
    if (videoTrack != nil) {
        AVMutableCompositionTrack *vtrack = [mutableComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        [vtrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, [asset duration]) ofTrack:videoTrack atTime:insertionPoint error:&error];
    }
    
    if (audioTrack != nil) {
        AVMutableCompositionTrack *atrack = [mutableComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        [atrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, [asset duration]) ofTrack:audioTrack atTime:insertionPoint error:&error];
    }

    // Check if the input asset contains only audio
    if ([[mutableComposition tracksWithMediaType:AVMediaTypeVideo] count] != 0) {
        
        // build a pass through video composition
        mutableVideoComposition = [AVMutableVideoComposition videoComposition];
        mutableVideoComposition.frameDuration = CMTimeMake(1, 30); // 30 fps
        mutableVideoComposition.renderSize = mutableComposition.naturalSize;
        
        AVMutableVideoCompositionInstruction *passThroughInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        passThroughInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, [mutableComposition duration]);
        
        AVAssetTrack *videoTrack = [[mutableComposition tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
        AVMutableVideoCompositionLayerInstruction *passThroughLayer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
        
        passThroughInstruction.layerInstructions = [NSArray arrayWithObject:passThroughLayer];
        mutableVideoComposition.instructions = [NSArray arrayWithObject:passThroughInstruction];
        
        CGSize videoSize = mutableVideoComposition.renderSize;
        captionLayer = [self captionLayerForSize:videoSize];
    }
    
    if (captionLayer) {
        
        CALayer *parentLayer = [CALayer layer];
        CALayer *videoLayer = [CALayer layer];
        parentLayer.frame = CGRectMake(0, 0, mutableVideoComposition.renderSize.width, mutableVideoComposition.renderSize.height);
        videoLayer.frame = CGRectMake(0, 0, mutableVideoComposition.renderSize.width, mutableVideoComposition.renderSize.height);
        [parentLayer addSublayer:videoLayer];
        captionLayer.position = CGPointMake(mutableVideoComposition.renderSize.width/2, mutableVideoComposition.renderSize.height/4);
        [parentLayer addSublayer:captionLayer];
        mutableVideoComposition.animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:parentLayer];
    }
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:[mutableComposition copy] presetName:AVAssetExportPreset1280x720];
    
    exportSession.videoComposition = mutableVideoComposition;
    exportSession.outputURL = outputURL;
    exportSession.outputFileType=AVFileTypeQuickTimeMovie;
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^(void){
        switch (exportSession.status) {
            case AVAssetExportSessionStatusCompleted:
                NSLog(@"Complete:%@", exportSession.error);
                // remove original
                [[NSFileManager defaultManager] removeItemAtURL:assetURL error:nil];
                
                // open in QT
                [[NSWorkspace sharedWorkspace] openURL:outputURL];
                
                break;
            case AVAssetExportSessionStatusFailed:
                //
                NSLog(@"Failed:%@", exportSession.error);
                break;
            case AVAssetExportSessionStatusCancelled:
                //
                NSLog(@"Canceled:%@", exportSession.error);
                break;
            default:
                break;
        }
    }];
}

- (void)askUserToSave:(NSURL *)outputFileURL {
    
    // move the recorded temporary file to a user-specified location
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    [savePanel setAllowedFileTypes:@[AVFileTypeQuickTimeMovie]];
    [savePanel setCanSelectHiddenExtension:YES];
    [savePanel beginSheetModalForWindow:[self windowForSheet] completionHandler:^(NSInteger result) {
        NSError *error = nil;
        if (result == NSOKButton) {
            
            if ([self.captionTextField.stringValue length] > 0) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    [self applyCaptionForAssetAtURL:outputFileURL output:[savePanel URL]];
                });

            } else {
                
                [[NSFileManager defaultManager] removeItemAtURL:[savePanel URL] error:nil]; // attempt to remove file at the desired save location before moving the recorded file to that location
                if ([[NSFileManager defaultManager] moveItemAtURL:outputFileURL toURL:[savePanel URL] error:&error]) {
                    [[NSWorkspace sharedWorkspace] openURL:[savePanel URL]];
                } else {
                    [savePanel orderOut:self];
                    [self presentError:error modalForWindow:[self windowForSheet] delegate:self didPresentSelector:nil contextInfo:NULL];
                }
            }
        } else {
            // remove the temporary recording file if it's not being saved
            [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        }
    }];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections dueToError:(NSError *)error {
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		[self presentError:error];
	});
}

@end

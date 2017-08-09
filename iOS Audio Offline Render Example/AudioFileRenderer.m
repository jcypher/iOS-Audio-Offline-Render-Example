//
//  AudioFileRenderer.m
//  iOS Audio Offline Render Example
//
//  Created by Leo Thiessen on 2017-08-08.
//  Copyright © 2017 Leo Thiessen. All rights reserved.
//

#import "AudioFileRenderer.h"
#import <AudioToolbox/AudioToolbox.h>
#import "TAAE2Utils.h"



#pragma mark - Utilities

/// Makes an NSError object a little more consisely
static inline NSError *_Nonnull AudErrMake(NSInteger code,
                                           NSString *_Nonnull msg) {
    
    return [NSError errorWithDomain:@"AudioError"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey:msg}];
    
}

/// Conditionally sets the **error
static inline void AudErrSet(NSError *_Nullable *_Nullable error,
                             NSInteger code,
                             NSString *_Nonnull msg) {
    
    if ( error ) {
        *error = AudErrMake(code, msg);
    }
    
}



#pragma mark - Interface

@interface AudioFileRenderer() {
    
    // Source File
    AudioFileID _sourceFile;
    AudioStreamBasicDescription _sourceFormat;
    UInt32 _sourceTotalFrames;
    
    // AUGraph
    AUGraph _graph;
    AudioUnit _outputAU;
    
    // Destination File
    ExtAudioFileRef _destinationFile;
    AudioStreamBasicDescription _destinationFormat;
    
    // Misc.
    BOOL _didStartRendering;
    UInt32 _maximumFramesPerSlice;
    AudioBufferList *_abl;
    AudioStreamBasicDescription _clientFormat;
    
}

@property (nonatomic, strong, readwrite) NSError *_Nullable lastError;
@property (nonatomic, readwrite) double progress;

@end



#pragma mark - Implementation

@implementation AudioFileRenderer

- (instancetype)initWithSourceFile:(NSURL *)srcURL
                   destinationFile:(NSURL *)destinationURL
                             error:(NSError **)error {
    
    // Re-usable iVars
    CFURLRef cfURL;
    OSStatus status;
    UInt32 propSize;
    AUNode outputNode;
    AUNode playerNode;
    AudioUnit playerAU;
    
    // Open source file
    cfURL = (__bridge CFURLRef _Nonnull)(srcURL);
    status = AudioFileOpenURL(cfURL, kAudioFileReadPermission, 0, &_sourceFile);
    if ( !AECheckOSStatus(status, "AudioFileOpenURL") ) {
        AudErrSet(error, status, @"Couldn't open the source audio file.");
        return nil;
    }
    
    // Get source file format
    propSize = sizeof(_sourceFormat);
    status = AudioFileGetProperty(_sourceFile,
                                  kAudioFilePropertyDataFormat,
                                  &propSize,
                                  &_sourceFormat);
    if ( !AECheckOSStatus(status, "AudioFileGetProperty") ) {
        AudErrSet(error, status, @"Couldn't read the source audio file format.");
        [self _teardown];
        return nil;
    }
    
    // Create graph
    status = NewAUGraph(&_graph);
    if ( !AECheckOSStatus(status, "NewAUGraph") ) {
        AudErrSet(error, status, @"Couldn't create audio graph.");
        [self _teardown];
        return nil;
    }
    
    // Add output node
    AudioComponentDescription outputDesc =
            AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple,
                                            kAudioUnitType_Output,
                                            kAudioUnitSubType_GenericOutput);
    status = AUGraphAddNode(_graph, &outputDesc, &outputNode);
    if ( !AECheckOSStatus(status, "AUGraphAddNode: GenericOutput") ) {
        AudErrSet(error, status, @"Couldn't add GenericOutput node to AUGraph.");
        [self _teardown];
        return nil;
    }
    
    // Add file player node
    AudioComponentDescription playerDesc =
            AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple,
                                            kAudioUnitType_Generator,
                                            kAudioUnitSubType_AudioFilePlayer);
    status = AUGraphAddNode(_graph, &playerDesc, &playerNode);
    if ( !AECheckOSStatus(status, "AUGraphAddNode: AudioFilePlayer") ) {
        AudErrSet(error, status, @"Couldn't add AudioFilePlayer node to AUGraph.");
        [self _teardown];
        return nil;
    }
    
    // Open the graph (opens all contained audio units but doesn't allocate
    // resource yet)
    status = AUGraphOpen(_graph);
    if ( !AECheckOSStatus(status, "AUGraphOpen") ) {
        AudErrSet(error, status, @"Couldn't open the audio graph.");
        [self _teardown];
        return nil;
    }
    
    // Connect the nodes
    status = AUGraphConnectNodeInput(_graph, playerNode, 0, outputNode, 0);
    if ( !AECheckOSStatus(status, "AUGraphConnectNodeInput") ) {
        AudErrSet(error, status, @"Couldn't connect playerNode to outputNode.");
        [self _teardown];
        return nil;
    }
    
    // Get the AudioUnit references
    status = AUGraphNodeInfo(_graph, outputNode, NULL, &_outputAU);
    if ( !AECheckOSStatus(status, "AUGraphNodeInfo: outputNode") ) {
        AudErrSet(error, status, @"Couldn't access the outputNode audio unit.");
        [self _teardown];
        return nil;
    }
    status = AUGraphNodeInfo(_graph, playerNode, NULL, &playerAU);
    if ( !AECheckOSStatus(status, "AUGraphNodeInfo: playerNode") ) {
        AudErrSet(error, status, @"Couldn't access the playerNode audio unit.");
        [self _teardown];
        return nil;
    }
    
    // Get the client format (format in which audio will be provided to
    // ExtAudio... before conversion & saving)
    propSize = sizeof(_clientFormat);
    status = AudioUnitGetProperty(_outputAU,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &_clientFormat,
                                  &propSize);
    if ( !AECheckOSStatus(status, "AudioUnitGetProperty: StreamFormat") ) {
        AudErrSet(error, status, @"Couldn't retrieve the client audio format.");
        [self _teardown];
        return nil;
    }
    
    // Set the Maximum Frames Per Slice (must set on every AU)
    _maximumFramesPerSlice = 4096 * 3; // 4096 == just under 0.1s for 44100hz
    status = AudioUnitSetProperty(_outputAU,
                                  kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global,
                                  0,
                                  &_maximumFramesPerSlice,
                                  sizeof(_maximumFramesPerSlice));
    if ( !AECheckOSStatus(status, "AudioUnitSetProperty: MaximumFramesPerSlice on outputAU") ) {
        AudErrSet(error, status, @"Couldn't set max frames on the outputAU.");
        [self _teardown];
        return nil;
    }
    status = AudioUnitSetProperty(playerAU,
                                  kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global,
                                  0,
                                  &_maximumFramesPerSlice,
                                  sizeof(_maximumFramesPerSlice));
    if ( !AECheckOSStatus(status, "AudioUnitSetProperty: MaximumFramesPerSlice on playerAU") ) {
        AudErrSet(error, status, @"Couldn't set max frames on the playerAU.");
        [self _teardown];
        return nil;
    }
    
    // Allocate an AudioBufferList
    _abl = AEAudioBufferListCreateWithFormat(_clientFormat, _maximumFramesPerSlice);
    if ( !(_abl) ) {
        AudErrSet(error, status, @"Couldn't allocate an audio buffer list.");
        [self _teardown];
        return nil;
    }
    
    // Initialize the graph (causes resources to be allocated)
    status = AUGraphInitialize(_graph);
    if ( !AECheckOSStatus(status, "AUGraphInitialize") ) {
        AudErrSet(error, status, @"Couldn't initialize the audio graph.");
        [self _teardown];
        return nil;
    }
    
    // Load source file
    status = AudioUnitSetProperty(playerAU,
                                  kAudioUnitProperty_ScheduledFileIDs,
                                  kAudioUnitScope_Global,
                                  0,
                                  &_sourceFile,
                                  sizeof(_sourceFile));
    if ( !AECheckOSStatus(status, "AudioUnitSetProperty(kAudioUnitProperty_ScheduledFileIDs)") ) {
        AudErrSet(error, status, @"Couldn't load the source audio file.");
        [self _teardown];
        return nil;
    }
    
    // Get source frame count
    UInt64 srcPacketCount;
    propSize = sizeof(srcPacketCount);
    status = AudioFileGetProperty(_sourceFile, kAudioFilePropertyAudioDataPacketCount, &propSize, &srcPacketCount);
    if ( !AECheckOSStatus(status, "AudioFileGetProperty(kAudioFilePropertyAudioDataPacketCount)") ) {
        AudErrSet(error, status, @"Couldn't read the source audio file packet count.");
        return nil;
    }
    _sourceTotalFrames = (UInt32)(srcPacketCount * _sourceFormat.mFramesPerPacket);
    
    // Schedule a "playback region" (the region to be rendered)
    ScheduledAudioFileRegion srcRegion;
    memset(&srcRegion.mTimeStamp, 0, sizeof(srcRegion.mTimeStamp));
    srcRegion.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    srcRegion.mTimeStamp.mSampleTime = 0;
    srcRegion.mCompletionProc = NULL;
    srcRegion.mCompletionProcUserData = NULL;
    srcRegion.mAudioFile = _sourceFile;
    srcRegion.mLoopCount = 0;
    srcRegion.mStartFrame = 0;
    srcRegion.mFramesToPlay = _sourceTotalFrames;
    status = AudioUnitSetProperty(playerAU,
                                  kAudioUnitProperty_ScheduledFileRegion,
                                  kAudioUnitScope_Global,
                                  0,
                                  &srcRegion,
                                  sizeof(srcRegion));
    if ( !AECheckOSStatus(status, "AudioUnitSetProperty: ScheduledFileRegion") ) {
        AudErrSet(error, status, @"Couldn't set the region to export.");
        [self _teardown];
        return nil;
    }
    
    // Set the number of frames to read from disk before returning
    UInt32 zeroToUseDefaultValue = 0;
    status = AudioUnitSetProperty(playerAU,
                                  kAudioUnitProperty_ScheduledFilePrime,
                                  kAudioUnitScope_Global,
                                  0,
                                  &zeroToUseDefaultValue,
                                  sizeof(zeroToUseDefaultValue));
    if ( !AECheckOSStatus(status, "AudioUnitSetProperty: ScheduledFilePrime") ) {
        AudErrSet(error, status, @"Couldn't prime the playback region for exporting.");
        [self _teardown];
        return nil;
    }
    
    // Tell file player AU when to start playing (next render cycle)
    AudioTimeStamp startTime = {0};
    startTime.mFlags = kAudioTimeStampSampleTimeValid;
    startTime.mSampleTime = -1; // this means start playing "next render cycle" (aka ASAP)
    status = AudioUnitSetProperty(playerAU,
                                  kAudioUnitProperty_ScheduleStartTimeStamp,
                                  kAudioUnitScope_Global,
                                  0,
                                  &startTime,
                                  sizeof(startTime));
    if ( !AECheckOSStatus(status, "AudioUnitSetProperty: ScheduleStartTimeStamp") ) {
        AudErrSet(error, status, @"Could not schedule file player audio unit playback start time.");
        [self _teardown];
        return nil;
    }
    
    // Start the graph
    status = AUGraphStart(_graph);
    if ( !AECheckOSStatus(status, "AUGraphStart") ) {
        AudErrSet(error, status, @"Couldn't start the audio graph.");
        [self _teardown];
        return nil;
    }
    
    // Create destination file format (mpeg4 AAC)
    memset(&_destinationFormat, 0, sizeof(_destinationFormat));
    _destinationFormat.mSampleRate = _clientFormat.mSampleRate; // same as outputAU (this is an offline AU, not system hardware-linked AU)
    _destinationFormat.mChannelsPerFrame = 1;
    _destinationFormat.mFormatID = kAudioFormatMPEG4AAC;
    propSize = sizeof(_destinationFormat);
    status = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                    0,
                                    NULL,
                                    &propSize,
                                    &_destinationFormat); // This fills in the ASBD details
    if ( !AECheckOSStatus(status, "AudioFormatGetProperty: FormatInfo") ) {
        AudErrSet(error, status, @"Couldn't create the output format AudioStreamBasicDescription.");
        [self _teardown];
        return nil;
    }
    
    // Create desination file
    cfURL = (__bridge CFURLRef)(destinationURL);
    status = ExtAudioFileCreateWithURL(cfURL, kAudioFileM4AType,
                                       &_destinationFormat,
                                       NULL,
                                       kAudioFileFlags_EraseFile, // overwrite if exist
                                       &_destinationFile);
    if ( !AECheckOSStatus(status, "ExtAudioFileCreateWithURL") ) {
        AudErrSet(error, status, @"Couldn't create the destination audio file.");
        [self _teardown];
        return nil;
    }
    
    // Set the client format on the ExtAudio service file
    status = ExtAudioFileSetProperty(_destinationFile,
                                     kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(_clientFormat),
                                     &_clientFormat);
    if ( !AECheckOSStatus(status, "ExtAudioFileSetProperty: ClientDataFormat") ) {
        AudErrSet(error, status, @"Couldn't set the client format on the extended audio service.");
        [self _teardown];
        return nil;
    }
    
    // Specify the export codec being used
    UInt32 codec = kAppleHardwareAudioCodecManufacturer;
    status = ExtAudioFileSetProperty(_destinationFile,
                                     kExtAudioFileProperty_CodecManufacturer,
                                     sizeof(codec),
                                     &codec);
    if ( !AECheckOSStatus(status, "ExtAudioFileSetProperty: CodecManufacturer") ) {
        AudErrSet(error, status, @"Couldn't set the audio codec on the destination file.");
        [self _teardown];
        return nil;
    }
    
    // Prepare to write (allocates resources)
    status = ExtAudioFileWriteAsync(_destinationFile, 0, NULL);
    if ( !AECheckOSStatus(status, "ExtAudioFileWriteAsync: priming call") ) {
        AudErrSet(error, status, @"Failed to prime destination file for writing.");
        [self _teardown];
        return nil;
    }
    
    return self;
}

- (void)dealloc {
    [self _teardown];
}

- (void)_teardown {
    
    if ( _graph ) {
        AUGraphStop(_graph);
        AUGraphUninitialize(_graph);
        AUGraphClose(_graph);
        _graph = NULL;
    }
    
    if ( _sourceFile ) {
        AudioFileClose(_sourceFile);
        _sourceFile = NULL;
    }
    
    if ( _destinationFile ) {
        ExtAudioFileDispose(_destinationFile);
        _destinationFile = NULL;
    }
    
    if ( _abl ) {
        AEAudioBufferListFree(_abl);
        _abl = NULL;
    }

}

- (void)startRendering {
    if ( _didStartRendering ) {
        return;
    }
    _didStartRendering = YES;
    
    // Dispatch export to a concurrent background thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self _renderTheFile];
    });
}

/// Render the source file to the destination file (while changing audio
/// format/codec)
- (void)_renderTheFile {
    
    // Total frame count with consideration for possible sample rate conversion
    UInt32 totFrames = _sourceTotalFrames * (_clientFormat.mSampleRate / _sourceFormat.mSampleRate);
    
    // Various iVars for while loop state
    _progress = 0; // percent
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp inTimeStamp;
    memset(&inTimeStamp, 0, sizeof(AudioTimeStamp));
    inTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    inTimeStamp.mSampleTime = 0;
    __block UInt32 remainingFrames = totFrames;
    UInt32 numberFramesToRender = _maximumFramesPerSlice;
    __block float microfadeIn  = 0.0f; // starting value
    BOOL isLastRender = NO;
    OSStatus status;
    
    // Export the full region
    while ( remainingFrames > 0 ) {
        
        // Cap the number of frames to render to precisely what we want to export
        if ( remainingFrames < numberFramesToRender ) { numberFramesToRender = remainingFrames; }
        
        // Decrement remaining frames
        remainingFrames -= numberFramesToRender;
        isLastRender = (remainingFrames == 0);
        
        // Render to Buffer
        status = AudioUnitRender(_outputAU, &flags, &inTimeStamp, 0, numberFramesToRender, _abl);
        if ( !AECheckOSStatus(status, "AudioUnitRender") ) {
            self.lastError = AudErrMake(status, @"Failed to render audio.");
            [self _messageDelegate:AudRendererEventFailed];
            break; // failed
        }
        
        // Example DSP (digital signal processing)
        // Micro Fades (no "buffer offset" because we're just fading for entire buffer length)
        if ( microfadeIn < FLT_EPSILON ) { // aka "is first iteration"
            // Fade-in
            AEDSPApplyRamp(_abl, &microfadeIn, 1.0f / ((float)numberFramesToRender), numberFramesToRender);
        } else if ( isLastRender ) {
            // Fade-out
            float microfadeOut = 1.0f; // starting value
            AEDSPApplyRamp(_abl, &microfadeOut, -1.0f / ((float)numberFramesToRender), numberFramesToRender);
        }
        
        // Write to File
        status = ExtAudioFileWrite(_destinationFile, numberFramesToRender, _abl);
        if ( !AECheckOSStatus(status, "ExtAudioFileWrite") ) {
            self.lastError = AudErrMake(status, @"Failed to write to the audio file.");
            [self _messageDelegate:AudRendererEventFailed];
            break; // failed
        }
        
        // Update progress & message delegate
        inTimeStamp.mSampleTime += numberFramesToRender;
        _progress = isLastRender ? 1 : ( 1.0 - (((double)remainingFrames) / ((double)totFrames)) );
        [self _messageDelegate:AudRendererEventProgress];
    }
    
    // Completed! -- currently we are on a bg thread...
    [self _teardown]; // free up resources, OK on bg thread?
    [self _messageDelegate:AudRendererEventCompleted];
} // END - (void)_exportTheFile{} ... (this is run in the background)

/// Message delegate on main thread only
- (void)_messageDelegate:(AudRendererEvent)event {
    id<AudioFileRendererDelegate> __strong strongDelegate = self.delegate;
    if ( strongDelegate ) {
        if ( NSThread.isMainThread ) {
            [strongDelegate renderer:self event:event];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongDelegate renderer:self event:event];
            });
        }
    }
}



@end

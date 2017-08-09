//
//  TAAE2Utils.m
//  RecordEngine
//
//  Original source: AEAudioBufferListUtilities.m and other TAAE2 files
//  TheAmazingAudioEngine
//
//  Original was created by Michael Tyson on 24/03/2016.
//  Copyright © 2016 A Tasty Pixel. All rights reserved.
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//
//  THE CODE IN THIS FILE IS LIKELY MODIFIED FROM IT'S ORIGINAL TAAE2 SOURCES
//  Modifications by Leo Thiessen on 2017-06-08.
//

#import "TAAE2Utils.h"
#import <Accelerate/Accelerate.h>
#import <mach/mach_time.h>



#pragma mark - AETime.m

static double __hostTicksToSeconds = 0.0;
static double __secondsToHostTicks = 0.0;

const AudioTimeStamp AETimeStampNone = {};

void AETimeInit() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info_data_t tinfo;
        mach_timebase_info(&tinfo);
        __hostTicksToSeconds = ((double)tinfo.numer / tinfo.denom) * 1.0e-9;
        __secondsToHostTicks = 1.0 / __hostTicksToSeconds;
    });
}

AEHostTicks AECurrentTimeInHostTicks(void) {
    return mach_absolute_time();
}

AESeconds AECurrentTimeInSeconds(void) {
    if ( !__hostTicksToSeconds ) AETimeInit();
    return mach_absolute_time() * __hostTicksToSeconds;
}

AEHostTicks AEHostTicksFromSeconds(AESeconds seconds) {
    if ( !__secondsToHostTicks ) AETimeInit();
    assert(seconds >= 0);
    return seconds * __secondsToHostTicks;
}

AESeconds AESecondsFromHostTicks(AEHostTicks ticks) {
    if ( !__hostTicksToSeconds ) AETimeInit();
    return ticks * __hostTicksToSeconds;
}

AudioTimeStamp AETimeStampWithHostTicks(AEHostTicks ticks) {
    if ( !ticks ) return AETimeStampNone;
    return (AudioTimeStamp) { .mFlags = kAudioTimeStampHostTimeValid, .mHostTime = ticks };
}

AudioTimeStamp AETimeStampWithSamples(Float64 samples) {
    return (AudioTimeStamp) { .mFlags = kAudioTimeStampSampleTimeValid, .mSampleTime = samples };
}



#pragma mark - AEUtilities.h (may be modified)

AudioComponentDescription AEAudioComponentDescriptionMake(OSType manufacturer, OSType type, OSType subtype) {
    AudioComponentDescription description;
    memset(&description, 0, sizeof(description));
    description.componentManufacturer = manufacturer;
    description.componentType = type;
    description.componentSubType = subtype;
    return description;
}

BOOL AERateLimit(void) {
    static double lastMessage = 0;
    static int messageCount=0;
    double now = AECurrentTimeInSeconds();
    if ( now-lastMessage > 1 ) {
        messageCount = 0;
        lastMessage = now;
    }
    if ( ++messageCount >= 10 ) {
        if ( messageCount == 10 ) {
            NSLog(@"TAAE: Suppressing some messages");
        }
        return NO;
    }
    return YES;
}

void AEError(OSStatus result, const char * _Nonnull operation, const char * _Nonnull file, int line) {
    if ( AERateLimit() ) {
        int fourCC = CFSwapInt32HostToBig(result);
        if ( isascii(((char*)&fourCC)[0]) && isascii(((char*)&fourCC)[1]) && isascii(((char*)&fourCC)[2]) ) {
            NSLog(@"%s:%d: %s: '%4.4s' (%d)", file, line, operation, (char*)&fourCC, (int)result);
        } else {
            NSLog(@"%s:%d: %s: %d", file, line, operation, (int)result);
        }
    }
}



#pragma mark - AudioBufferListUtils.m

AudioBufferList *AEAudioBufferListCreateWithFormat(AudioStreamBasicDescription audioFormat, int frameCount) {
    int numberOfBuffers = audioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? audioFormat.mChannelsPerFrame : 1;
    int channelsPerBuffer = audioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? 1 : audioFormat.mChannelsPerFrame;
    int bytesPerBuffer = audioFormat.mBytesPerFrame * frameCount;
    
    AudioBufferList *audio = malloc(sizeof(AudioBufferList) + (numberOfBuffers-1)*sizeof(AudioBuffer));
    if ( !audio ) {
        return NULL;
    }
    audio->mNumberBuffers = numberOfBuffers;
    for ( int i=0; i<numberOfBuffers; i++ ) {
        if ( bytesPerBuffer > 0 ) {
            audio->mBuffers[i].mData = calloc(bytesPerBuffer, 1);
            if ( !audio->mBuffers[i].mData ) {
                for ( int j=0; j<i; j++ ) free(audio->mBuffers[j].mData);
                free(audio);
                return NULL;
            }
        } else {
            audio->mBuffers[i].mData = NULL;
        }
        audio->mBuffers[i].mDataByteSize = bytesPerBuffer;
        audio->mBuffers[i].mNumberChannels = channelsPerBuffer;
    }
    return audio;
}


void AEAudioBufferListFree(AudioBufferList *bufferList ) {
    if ( bufferList ) {
        for ( int i=0; i<bufferList->mNumberBuffers; i++ ) {
            if ( bufferList->mBuffers[i].mData ) free(bufferList->mBuffers[i].mData);
        }
        free(bufferList);
    }
}


void AEDSPApplyGain(const AudioBufferList * bufferList, float gain, UInt32 frames) {
    for ( int i=0; i < bufferList->mNumberBuffers; i++ ) {
        if ( gain < FLT_EPSILON ) {
            vDSP_vclr(bufferList->mBuffers[i].mData, 1, frames); // silence
        } else {
            vDSP_vsmul(bufferList->mBuffers[i].mData, 1, &gain, bufferList->mBuffers[i].mData, 1, frames);
        }
    }
}


void AEDSPApplyRamp(const AudioBufferList * bufferList, float * start, float step, UInt32 frames) {
    if ( bufferList->mNumberBuffers == 2 ) {
        // Stereo buffer: use stereo utility
        vDSP_vrampmul2(bufferList->mBuffers[0].mData, bufferList->mBuffers[1].mData, 1, start, &step,
                       bufferList->mBuffers[0].mData, bufferList->mBuffers[1].mData, 1, frames);
    } else {
        // Mono or multi-channel buffer: treat channel by channel
        float s = *start;
        for ( int i=0; i < bufferList->mNumberBuffers; i++ ) {
            s = *start;
            vDSP_vrampmul(bufferList->mBuffers[i].mData, 1, &s, &step, bufferList->mBuffers[i].mData, 1, frames);
        }
        *start = s;
    }
}



//
//  TAAE2Utils.h
//  RecordEngine
//
//  Original source: AEAudioBufferListUtilities.h and other TAAE2 files
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

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>



#pragma mark - AETime.h (may be modified)

typedef uint64_t AEHostTicks;
typedef double AESeconds;

extern const AudioTimeStamp AETimeStampNone; //!< An empty timestamp

/*!
 * Initialize
 */
void AETimeInit();

/*!
 * Get current global timestamp, in host ticks
 */
AEHostTicks AECurrentTimeInHostTicks(void);

/*!
 * Get current global timestamp, in seconds
 */
AESeconds AECurrentTimeInSeconds(void);

/*!
 * Convert time in seconds to host ticks
 *
 * @param seconds The time in seconds
 * @return The time in host ticks
 */
AEHostTicks AEHostTicksFromSeconds(AESeconds seconds);

/*!
 * Convert time in host ticks to seconds
 *
 * @param ticks The time in host ticks
 * @return The time in seconds
 */
AESeconds AESecondsFromHostTicks(AEHostTicks ticks);

/*!
 * Create an AudioTimeStamps with a host ticks value
 *
 *  If a zero value is provided, then AETimeStampNone will be returned.
 *
 * @param ticks The time in host ticks
 * @return The timestamp
 */
AudioTimeStamp AETimeStampWithHostTicks(AEHostTicks ticks);

/*!
 * Create an AudioTimeStamps with a sample time value
 *
 * @param samples The time in samples
 * @return The timestamp
 */
AudioTimeStamp AETimeStampWithSamples(Float64 samples);



#pragma mark - AEUtilities.h (may be modified)

/*!
 * Create an AudioComponentDescription structure
 *
 * @param manufacturer  The audio component manufacturer (e.g. kAudioUnitManufacturer_Apple)
 * @param type          The type (e.g. kAudioUnitType_Generator)
 * @param subtype       The subtype (e.g. kAudioUnitSubType_AudioFilePlayer)
 * @returns An AudioComponentDescription structure with the given attributes
 */
AudioComponentDescription AEAudioComponentDescriptionMake(OSType manufacturer, OSType type, OSType subtype);

/*!
 * Rate limit an operation
 *
 *  This can be used to prevent spamming error messages to the console
 *  when something goes wrong.
 */
BOOL AERateLimit(void);

/*!
 * An error occurred within AECheckOSStatus
 *
 *  Create a symbolic breakpoint with this function name to break on errors.
 */
void AEError(OSStatus result, const char * _Nonnull operation, const char * _Nonnull file, int line);

/*!
 * Check an OSStatus condition
 *
 * @param result The result
 * @param operation A description of the operation, for logging purposes
 */
#define AECheckOSStatus(result,operation) (_AECheckOSStatus((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _AECheckOSStatus(OSStatus result, const char * _Nonnull operation, const char * _Nonnull file, int line) {
    if ( result != noErr ) {
        AEError(result, operation, file, line);
        return NO;
    }
    return YES;
}



#pragma mark - AEAudioBufferListUtilities.h (may be modified)

/*!
 * Allocate an audio buffer list and the associated mData pointers, with a custom audio format.
 *
 *  Note: Do not use this utility from within the Core Audio thread (such as inside a render
 *  callback). It may cause the thread to block, inducing audio stutters.
 *
 * @param audioFormat Audio format describing audio to be stored in buffer list
 * @param frameCount The number of frames to allocate space for (or 0 to just allocate the list structure itself)
 * @return The allocated and initialised audio buffer list
 */
AudioBufferList *_Nullable AEAudioBufferListCreateWithFormat(AudioStreamBasicDescription audioFormat, int frameCount);


/*!
 * Free a buffer list and associated mData buffers
 *
 *  Note: Do not use this utility from within the Core Audio thread (such as inside a render
 *  callback). It may cause the thread to block, inducing audio stutters.
 */
void AEAudioBufferListFree(AudioBufferList *_Nullable bufferList);


/*!
 * Scale values in a buffer list by some gain value
 *
 * @param bufferList Audio buffer list, in non-interleaved float format
 * @param gain Gain amount (power ratio)
 * @param frames Length of buffer in frames
 */
void AEDSPApplyGain(const AudioBufferList *_Nonnull bufferList, float gain, UInt32 frames);


/*!
 * Apply a ramp to values in a buffer list
 *
 * @param bufferList Audio buffer list, in non-interleaved float format
 * @param start Starting gain (power ratio) on input; final gain value on output
 * @param step Amount per frame to advance gain
 * @param frames Length of buffer in frames
 */
void AEDSPApplyRamp(const AudioBufferList *_Nonnull bufferList, float *_Nonnull start, float step, UInt32 frames);


/*!
 * Convert decibels to power ratio
 *
 * @param decibels Value in decibels
 * @return Power ratio value
 */
static inline double AEDSPDecibelsToRatio(double decibels) {
    return pow(10.0, decibels / 20.0);
}

/*!
 * Convert power ratio to decibels
 *
 * @param ratio Power ratio
 * @return Value in decibels
 */
static inline double AEDSPRatioToDecibels(double ratio) {
    return 20.0 * log10(ratio);
}



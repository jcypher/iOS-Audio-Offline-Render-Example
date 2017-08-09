//
//  AudioFileRenderer.h
//  iOS Audio Offline Render Example
//
//  Created by Leo Thiessen on 2017-08-08.
//  Copyright © 2017 Leo Thiessen. All rights reserved.
//

#import <Foundation/Foundation.h>



typedef NS_ENUM(NSUInteger, AudRendererEvent) {
    AudRendererEventProgress,
    AudRendererEventCompleted,
    AudRendererEventFailed, ///< see self.lastError
};



@class AudioFileRenderer;
@protocol AudioFileRendererDelegate <NSObject>
@required
- (void)renderer:(AudioFileRenderer *_Nonnull)renderer event:(AudRendererEvent)event;
@end



#pragma mark - Interface

@interface AudioFileRenderer : NSObject

- (instancetype _Nullable)initWithSourceFile:(NSURL *_Nonnull)srcURL
                             destinationFile:(NSURL *_Nonnull)destinationURL
                                       error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;

- (instancetype _Nonnull)init NS_UNAVAILABLE;

- (void)startRendering; ///< start the offline rendering


#pragma mark - Properties

@property (nonatomic, weak, readwrite) id<AudioFileRendererDelegate> _Nullable delegate;
@property (nonatomic, strong, readonly) NSError *_Nullable lastError;
@property (nonatomic, readonly) double progress;

@end

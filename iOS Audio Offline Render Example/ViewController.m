//
//  ViewController.m
//  iOS Audio Offline Render Example
//
//  Created by Leo Thiessen on 2017-08-08.
//  Copyright © 2017 Leo Thiessen. All rights reserved.
//

#import "ViewController.h"
#import "AudioFileRenderer.h"
#import <AVFoundation/AVFoundation.h>


@interface ViewController () <AudioFileRendererDelegate, AVAudioPlayerDelegate>
@property (nonatomic, strong) AudioFileRenderer *renderer;
@property (nonatomic, strong) NSURL *sourceURL;
@property (nonatomic, strong) NSURL *destinationURL;
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, assign) CFTimeInterval startTime;
@end



@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.sourceURL = [NSBundle.mainBundle URLForResource:@"file" withExtension:@"caf"];
    self.destinationURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"file.m4a"]];
}

- (IBAction)startRendering:(UIButton *)sender {
    if ( self.renderer ) {
        return;
    }
    
    // Delete any previously rendered file
    [NSFileManager.defaultManager removeItemAtURL:self.destinationURL error:nil];
    
    // Create renderer
    NSError *error;
    self.renderer = [[AudioFileRenderer alloc] initWithSourceFile:self.sourceURL
                                                  destinationFile:self.destinationURL
                                                            error:&error];
    if ( error ) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ERROR: init renderer"
                                                                       message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:NULL];
    } else {
        
        // Start renderer
        self.startTime = CACurrentMediaTime();
        self.renderer.delegate = self;
        [self.renderer startRendering];
    }
}



#pragma mark - <AudioFileRendererDelegate>

- (void)renderer:(AudioFileRenderer *)renderer event:(AudRendererEvent)event {
    switch ( event ) {
        case AudRendererEventProgress: {
            printf("Progress: %.1f\n", renderer.progress * 100.0);
            break;
        }
        case AudRendererEventCompleted: {
            printf("Completed!\n");
            self.renderer = nil;
            NSError *error;
            self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:self.destinationURL
                                                                 error:&error];
            if ( error ) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ERROR: play new file"
                                                                               message:error.localizedDescription
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [self presentViewController:alert animated:YES completion:NULL];
            } else {
                CFTimeInterval endTime = CACurrentMediaTime();
                self.player.delegate = self;
                __typeof__(self) __weak weakSelf = self;
                NSString *msg = [NSString stringWithFormat:@"Rendering took %.3f seconds", endTime - _startTime];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Completed!"
                                                                               message:msg
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss/Stop Playing" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [alert dismissViewControllerAnimated:YES completion:NULL];
                    NSLog(@"will stop player... %@", weakSelf);
                    [weakSelf.player stop];
                    weakSelf.player = nil;
                }]];
                [self presentViewController:alert animated:YES completion:^{
                    [weakSelf.player play];
                }];
            }
            break;
        }
        case AudRendererEventFailed: {
            NSString *errDesc = self.renderer.lastError.localizedDescription;
            printf("Failed! Error: %s\n", errDesc.UTF8String);
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ERROR: rendering"
                                                                           message:errDesc
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:alert animated:YES completion:NULL];
            self.renderer = nil;
            break;
        }
    }
}



#pragma mark - <AVAudioPlayerDelegate>

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    self.player = nil;
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ERROR: player decode"
                                                                   message:error.localizedDescription
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:NULL];
    self.player = nil;
}


@end

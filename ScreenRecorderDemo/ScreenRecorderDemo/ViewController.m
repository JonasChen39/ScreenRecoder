//
//  ViewController.m
//  ScreenRecorderDemo
//
//  Created by cj on 16/6/1.
//  Copyright © 2016年 JonasChen. All rights reserved.
//

#import "ViewController.h"
#import "ScreenRecorder.h"
#import "BViewController.h"
#import <MediaPlayer/MediaPlayer.h>

@interface ViewController ()<ScreenRecorderDelegate>
{
    __weak IBOutlet UIImageView *imageView;
    ScreenRecorder *_record;
    NSString *_path;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _record = [ScreenRecorder sharedRecorder];
    _record.frameRate = 35;
    _record.delegate = self;
}



- (IBAction)toNextPage:(id)sender {
    BViewController *controller = [[BViewController alloc] init];
    [self presentViewController:controller animated:YES completion:nil];
}

- (IBAction)selector:(UIButton *)sender
{
    if ([sender.currentTitle isEqualToString:@"开始录制"]) {
        [_record performSelector:@selector(startRecording)];
        
        [sender setTitle:@"停止录制" forState:UIControlStateNormal];
        [UIView animateWithDuration:3 animations:^{
            imageView.bounds = CGRectMake(0, 0, imageView.bounds.size.width*2, imageView.bounds.size.height*2);
        }];
        
    }
    else {
        [_record performSelector:@selector(stopRecording)];
        [sender setTitle:@"开始录制" forState:UIControlStateNormal];
    }
}

- (IBAction)play:(id)sender {
    MPMoviePlayerViewController *theMovie =[[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL fileURLWithPath:_path]];
    [self presentMoviePlayerViewControllerAnimated:theMovie];
    theMovie.moviePlayer.movieSourceType = MPMovieSourceTypeFile;
    [theMovie.moviePlayer play];
}

#pragma mark -
#pragma mark THCaptureDelegate

- (void)recordingFinished:(NSString*)outputPath
{
    _path = outputPath;
    
    NSLog(@"录制完成");
}




@end

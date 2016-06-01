//
//  ScreenRecorder.h
//  iOS-screen-recorder
//
//  Created by cj on 16/6/1.
//  Copyright © 2016年 JonasChen. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol ScreenRecorderDelegate;

@interface ScreenRecorder : NSObject

@property (nonatomic, assign) NSUInteger frameRate;//用来设置录制帧的视频，就是一秒钟录制几帧图像
@property (nonatomic, strong) id<ScreenRecorderDelegate> delegate;

//创建实例
+ (ScreenRecorder *)sharedRecorder;
//开始录制
- (BOOL)startRecording;
//结束录制
- (void)stopRecording;



@end


@protocol ScreenRecorderDelegate <NSObject>

- (void)recordingFinished:(NSString*)outputPath;

@end
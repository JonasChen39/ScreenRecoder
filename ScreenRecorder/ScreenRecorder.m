//
//  ScreenRecorder.m
//  iOS-screen-recorder
//
//  Created by cj on 16/6/1.
//  Copyright © 2016年 JonasChen. All rights reserved.
//

#import "ScreenRecorder.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#define FilePath [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)objectAtIndex:0] stringByAppendingPathComponent:@"output.mov"]
static ScreenRecorder *_screenRecorder;

@implementation ScreenRecorder{
    
    AVAssetWriter *videoWriter;//使用 AVAssetWriter 对象可以将样本缓存写入文件
    AVAssetWriterInput *videoWriterInput;
    AVAssetWriterInputPixelBufferAdaptor *avAdaptor;
    
    BOOL            _recording;     //正在录制中
    BOOL            _writing;       //正在将帧写入文件
    float           _spaceDate;     //秒   这个变量一直为0，如果去掉这个变量程序会发生崩溃.....
    NSDate          *startedAt;     //录制的开始时间
    CGContextRef    context;        //绘制layer的context
    NSTimer         *timer;         //按帧率写屏的定时器
}


+ (ScreenRecorder *)sharedRecorder
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _screenRecorder = [[self alloc] init];
        _screenRecorder.frameRate = 10;//默认帧率为10
    });
    
    return _screenRecorder;
}

- (BOOL)startRecording
{
    BOOL result = NO;
    if (!_recording) {
        
        result = [self setUpWriter];
        if (result) {
            startedAt   = [NSDate date];
            _recording  = YES;
            _writing    = NO;
            _spaceDate  = 0;

            timer = [NSTimer scheduledTimerWithTimeInterval:1.0/self.frameRate target:self selector:@selector(drawFrame) userInfo:nil repeats:YES];
        }
        
    }
    return result;
}

- (void)stopRecording
{
    if (_recording) {
        _recording = NO;
        [timer invalidate];
        timer = nil;
        [self completeRecordingSession];
        [self cleanupWriter];
    }
}

-(void) writeVideoFrameAtTime:(CMTime)time addImage:(CGImageRef )newImage
{
    //视频输入是否准备接受更多的媒体数据
    if (![videoWriterInput isReadyForMoreMediaData]) {
        NSLog(@"Not ready for video data");
    } else {
        
        @synchronized (self) {//创建一个互斥锁，保证此时没有其它线程对self对象进行修改
            CVPixelBufferRef pixelBuffer = NULL;
            CGImageRef cgImage = CGImageCreateCopy(newImage);
            CFDataRef image = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
            
            int status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, avAdaptor.pixelBufferPool, &pixelBuffer);
            if(status != 0){
                //could not get a buffer from the pool
                NSLog(@"Error creating pixel buffer:  status=%d", status);
            }
            // set image data into pixel buffer
            CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
            uint8_t* destPixels = CVPixelBufferGetBaseAddress(pixelBuffer);
            CFDataGetBytes(image, CFRangeMake(0, CFDataGetLength(image)), destPixels);  //XXX:  will work if the pixel buffer is contiguous and has the same bytesPerRow as the input data

            if(status == 0) {
                
                BOOL success = [avAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
                if (!success)
                    NSLog(@"Warning:  Unable to write buffer to video");
            }
            
            //clean up
            CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
            CVPixelBufferRelease( pixelBuffer );
            CFRelease(image);
            CGImageRelease(cgImage);
        }
        
    }
}

- (void)completeRecordingSession
{
    [videoWriterInput markAsFinished];
    
    // wait for the video
    int status = videoWriter.status;
    while (status == AVAssetWriterStatusUnknown)
    {
        NSLog(@"Waiting...");
        [NSThread sleepForTimeInterval:0.5f];
        status = videoWriter.status;
    }
    
    [videoWriter finishWritingWithCompletionHandler:^{
        if ([_delegate respondsToSelector:@selector(recordingFinished:)]) {
            [_delegate recordingFinished:FilePath];
        }
    }];
}


- (void)drawFrame
{
    if (!_writing) {
        [self performSelector:@selector(getFrame) withObject:nil];
    }
}

- (void)getFrame
{
    if (!_writing) {
        
        _writing = YES;
        
        size_t width = CGBitmapContextGetWidth(context);
        size_t height = CGBitmapContextGetHeight(context);
        
        CGContextClearRect(context, CGRectMake(0, 0, width, height));//将显示区域填充为透明背景
        
        //用下边注释掉的方法截屏不能够截取到动画效果
//        [[[UIApplication sharedApplication].delegate window].layer renderInContext:context];
//        [[UIApplication sharedApplication].delegate window].layer.contents = nil;
//        CGImageRef cgImage = CGBitmapContextCreateImage(context);
        
        [[[UIApplication sharedApplication].delegate window] drawViewHierarchyInRect:[[UIApplication sharedApplication].delegate window].bounds afterScreenUpdates:NO];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        //UIGraphicsEndImageContext();
        CGImageRef cgImage = image.CGImage;
        
        if (_recording) {
            float millisElapsed = [[NSDate date] timeIntervalSinceDate:startedAt] * 1000.0-_spaceDate*1000.0;
            [self writeVideoFrameAtTime:CMTimeMake((int)millisElapsed, 1000) addImage:cgImage];
        }
        
        
       // CGImageRelease(cgImage);//在64位机器中添加该代码程序可以正常运行，在32位系统中添加该代码程序会崩溃
        
        _writing = NO;
    }
}



- (BOOL)setUpWriter
{
    [self is64bit];
    
    CGSize tmpsize = [UIScreen mainScreen].bounds.size;
    float scaleFactor = [[UIScreen mainScreen] scale];
    CGSize size = CGSizeMake(tmpsize.width*scaleFactor, tmpsize.height*scaleFactor);
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:FilePath]) {
        
        if ([fileManager removeItemAtPath:FilePath error:&error] == NO) {
            NSLog(@"Could not delete old recording file at path:  %@", FilePath);
            return NO;
        }
    }
    
    //configure videoWriter
    NSURL *fileUrl = [NSURL fileURLWithPath:FilePath];
    videoWriter = [[AVAssetWriter alloc] initWithURL:fileUrl fileType:AVFileTypeQuickTimeMovie error:&error];
    NSParameterAssert(videoWriter);

    //Configure videoWriterInput
    NSDictionary* videoCompressionProps = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSNumber numberWithDouble:size.width*size.height], AVVideoAverageBitRateKey,//视频尺寸*比率，10.1相当于AVCaptureSessionPresetHigh，数值越大，显示越精细
                                           nil ];
    
    
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecH264, AVVideoCodecKey,
                                   [NSNumber numberWithInt:size.width], AVVideoWidthKey,
                                   [NSNumber numberWithInt:size.height], AVVideoHeightKey,
                                   videoCompressionProps, AVVideoCompressionPropertiesKey,
                                   nil];
    videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    
    NSParameterAssert(videoWriterInput);
    videoWriterInput.expectsMediaDataInRealTime = YES;
    NSMutableDictionary* bufferAttributes = [[NSMutableDictionary alloc] init];
    
    [bufferAttributes setObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];//之前配置的下边注释掉的context使用的是kCVPixelFormatType_32ARGB，用起来颜色没有问题。但是用UIGraphicsBeginImageContextWithOptions([[UIApplication sharedApplication].delegate window].bounds.size, YES, 0);配置的context使用kCVPixelFormatType_32ARGB的话颜色会变成粉色，替换成kCVPixelFormatType_32BGRA之后，颜色正常。。。
    
    [bufferAttributes setObject:[NSNumber numberWithUnsignedInt:size.width] forKey:(NSString*)kCVPixelBufferWidthKey];//这个位置包括下面的两个，必须写成(int)size.width/16*16,因为这个的大小必须是16的倍数，否则图像会发生拉扯、挤压、旋转。。。。不知道为啥
    [bufferAttributes setObject:[NSNumber numberWithUnsignedInt:size.height ] forKey:(NSString*)kCVPixelBufferHeightKey];
    
    
    avAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput sourcePixelBufferAttributes:bufferAttributes];
    
    //add input
    [videoWriter addInput:videoWriterInput];
    [videoWriter startWriting];
    [videoWriter startSessionAtSourceTime:CMTimeMake(0, 1000)];
    
    //create context
    if (context== NULL)
    {
//        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
//        context = CGBitmapContextCreate (
//                                         NULL,//参数data指向绘图操作被渲染的内存区域，这个内存区域大小应该为（bytesPerRow*height）个字节。如果对绘制操作被渲染的内存区域并无特别的要求，那么可以传递NULL给参数data。
//                                         (int)size.width/16*16,        //bitmap的宽度，单位为像素
//                                         size.height ,       //bitmap的高度，单位为像素
//                                         8,                 //内存中像素的每个组件的位数。例如，对于32位像素格式和RGB 颜色空间，你应该将这个值设为8.
//                                         (int)size.width/16*16 * 4,    //bitmap的每一行在内存所占的比特数
//                                         colorSpace,        //bitmap上下文使用的颜色空间
//                                         kCGImageAlphaNoneSkipFirst
//                                         );
//        CGContextScaleCTM(context, scaleFactor, scaleFactor);
//        CGColorSpaceRelease(colorSpace);
//        CGContextSetAllowsAntialiasing(context,NO);//取消防锯齿
//        CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, size.height/scaleFactor);
//         CGContextConcatCTM(context, flipVertical);//应用这种变换
        
        UIGraphicsBeginImageContextWithOptions([[UIApplication sharedApplication].delegate window].bounds.size, YES, 0);
        context = UIGraphicsGetCurrentContext();

    }
    if (context== NULL)
    {
        fprintf (stderr, "Context not created!");
        return NO;
    }
    
    return YES;
}



- (void) cleanupWriter {
    
    avAdaptor = nil;
    
    videoWriterInput = nil;
    
    videoWriter = nil;
    
    startedAt = nil;

}

- (BOOL)is64bit
{
#if defined(__LP64__) && __LP64__
    NSLog(@"设备是64位的");
    return YES;
#else
    NSLog(@"设备是32位的");
    return NO;
#endif
}

@end























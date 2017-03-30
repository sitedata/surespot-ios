/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloaderOperation.h"
#import "SDWebImageDecoder.h"
#import "UIImage+MultiFormat.h"
#import <ImageIO/ImageIO.h>
#import "CredentialCachingController.h"

#import "CocoaLumberjack.h"

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelInfo;
#else
static const DDLogLevel ddLogLevel = DDLogLevelOff;
#endif

@interface SDWebImageDownloaderOperation ()

@property (copy, nonatomic) SDWebImageDownloaderProgressBlock progressBlock;
@property (copy, nonatomic) SDWebImageDownloaderCompletedBlock completedBlock;
@property (copy, nonatomic) void (^cancelBlock)();

@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;
@property (assign, nonatomic) long long expectedSize;
@property (strong, atomic) NSMutableData *imageData;
@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSString * ourVersion;
@property (strong, nonatomic) NSString * theirUsername;
@property (strong, nonatomic) NSString * theirVersion;
@property (strong, nonatomic) NSString * iv;
@property (strong, nonatomic) NSString * mimeType;
@property (assign, nonatomic) BOOL hashed;


#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;
#endif

@end



@implementation SDWebImageDownloaderOperation
{
    size_t width, height;
    BOOL responseFromCached;
}

@synthesize executing = _executing;
@synthesize finished = _finished;

- (id)initWithRequest:(NSURLRequest *)request
             mimeType: (NSString *) mimeType
           ourVersion: (NSString *) ourversion
        theirUsername: (NSString *) theirUsername
         theirVersion: (NSString *) theirVersion
                   iv: (NSString *) iv
               hashed: (BOOL) hashed
              options:(SDWebImageDownloaderOptions)options progress:(void (^)(NSUInteger, long long))progressBlock completed:(void (^)(id, NSData *, NSString *, NSError *, BOOL))completedBlock cancelled:(void (^)())cancelBlock
{
    if ((self = [super init]))
    {
        _request = request;
        _ourVersion = ourversion;
        _theirUsername = theirUsername;
        _theirVersion = theirVersion;
        _mimeType = mimeType;
        _iv = iv;
        _hashed = hashed;
        _options = options;
        
        _progressBlock = [progressBlock copy];
        _completedBlock = [completedBlock copy];
        _cancelBlock = [cancelBlock copy];
        _executing = NO;
        _finished = NO;
        _expectedSize = 0;
        responseFromCached = YES; // Initially wrong until `connection:willCacheResponse:` is called or not called
    }
    return self;
}

- (void)start
{
    if (self.isCancelled)
    {
        DDLogVerbose(@"isCancelled");
        self.finished = YES;
        [self reset];
        return;
    }
    
#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
    if ([self shouldContinueWhenAppEntersBackground])
    {
        __weak __typeof__(self) wself = self;
        self.backgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^
                                 {
                                     __strong __typeof(wself)sself = wself;
                                     
                                     if (sself)
                                     {
                                         [sself cancel];
                                         
                                         [[UIApplication sharedApplication] endBackgroundTask:sself.backgroundTaskId];
                                         sself.backgroundTaskId = UIBackgroundTaskInvalid;
                                     }
                                 }];
    }
#endif
    
    self.executing = YES;
    self.connection = [NSURLConnection.alloc initWithRequest:self.request delegate:self startImmediately:NO];
    
    [self.connection start];
    DDLogVerbose(@"downloading image: %@", [self.request.URL absoluteString]);
    
    if (self.connection)
    {
        if (self.progressBlock)
        {
            self.progressBlock(0, -1);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStartNotification object:self];
        
        if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_5_1)
        {
            // Make sure to run the runloop in our background thread so it can process downloaded data
            // Note: we use a timeout to work around an issue with NSURLConnection cancel under iOS 5
            //       not waking up the runloop, leading to dead threads (see https://github.com/rs/SDWebImage/issues/466)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, false);
        }
        else
        {
            CFRunLoopRun();
        }
        
        //        if (!self.isFinished)
        //        {
        //
        //            [self.connection cancel];
        //            [self connection:self.connection didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:@{NSURLErrorFailingURLErrorKey: self.request.URL}]];
        //        }
    }
    else
    {
        if (self.completedBlock)
        {
            self.completedBlock(nil, nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Connection can't be initialized"}], YES);
        }
    }
}

- (void)cancel
{
    DDLogVerbose(@"cancel");
    if (self.isFinished) return;
    [super cancel];
    if (self.cancelBlock) self.cancelBlock();
    
    if (self.connection)
    {
        [self.connection cancel];
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:self];
        
        // As we cancelled the connection, its callback won't be called and thus won't
        // maintain the isFinished and isExecuting flags.
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    }
    
    [self reset];
}

- (void)done
{
    DDLogVerbose(@"done");
    self.finished = YES;
    self.executing = NO;
    [self reset];
}

- (void)reset
{
    DDLogVerbose(@"reset");
    self.cancelBlock = nil;
    self.completedBlock = nil;
    self.progressBlock = nil;
    self.connection = nil;
    self.imageData = nil;
}

- (void)setFinished:(BOOL)finished
{
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing
{
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isConcurrent
{
    return YES;
}

#pragma mark NSURLConnection (delegate)

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if (![response respondsToSelector:@selector(statusCode)] || [((NSHTTPURLResponse *)response) statusCode] < 400)
    {
        NSUInteger expected = response.expectedContentLength > 0 ? (NSUInteger)response.expectedContentLength : 0;
        self.expectedSize = expected;
        if (self.progressBlock)
        {
            self.progressBlock(0, expected);
        }
        
        self.imageData = [NSMutableData.alloc initWithCapacity:expected];
        // [self setFinished:YES];
    }
    else
    {
        [self.connection cancel];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:nil];
        
        if (self.completedBlock)
        {
            self.completedBlock(nil, nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:[((NSHTTPURLResponse *)response) statusCode] userInfo:nil], YES);
        }
        
        [self done];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    DDLogVerbose(@"appending %lu bytes", (unsigned long)data.length);
    [self.imageData appendData:data];
    
    //    if ((self.options & SDWebImageDownloaderProgressiveDownload) && self.expectedSize > 0 && self.completedBlock)
    //  {
    //        // The following code is from http://www.cocoaintheshell.com/2011/05/progressive-images-download-imageio/
    //        // Thanks to the author @Nyx0uf
    //
    //        // Get the total bytes downloaded
    //        const NSUInteger totalSize = self.imageData.length;
    //
    //        // Update the data source, we must pass ALL the data, not just the new bytes
    //        CGImageSourceRef imageSource = CGImageSourceCreateIncremental(NULL);
    //        CGImageSourceUpdateData(imageSource, (__bridge  CFDataRef)self.imageData, totalSize == self.expectedSize);
    //
    //        if (width + height == 0)
    //        {
    //            CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
    //            if (properties)
    //            {
    //                CFTypeRef val = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
    //                if (val) CFNumberGetValue(val, kCFNumberLongType, &height);
    //                val = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
    //                if (val) CFNumberGetValue(val, kCFNumberLongType, &width);
    //                CFRelease(properties);
    //            }
    //        }
    //
    //        if (width + height > 0 && totalSize < self.expectedSize)
    //        {
    //            // Create the image
    //            CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    //
    //#ifdef TARGET_OS_IPHONE
    //            // Workaround for iOS anamorphic image
    //            if (partialImageRef)
    //            {
    //                const size_t partialHeight = CGImageGetHeight(partialImageRef);
    //                CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    //                CGContextRef bmContext = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
    //                CGColorSpaceRelease(colorSpace);
    //                if (bmContext)
    //                {
    //                    CGContextDrawImage(bmContext, (CGRect){.origin.x = 0.0f, .origin.y = 0.0f, .size.width = width, .size.height = partialHeight}, partialImageRef);
    //                    CGImageRelease(partialImageRef);
    //                    partialImageRef = CGBitmapContextCreateImage(bmContext);
    //                    CGContextRelease(bmContext);
    //                }
    //                else
    //                {
    //                    CGImageRelease(partialImageRef);
    //                    partialImageRef = nil;
    //                }
    //            }
    //#endif
    //
    //            if (partialImageRef)
    //            {
    //                UIImage *image = [UIImage imageWithCGImage:partialImageRef];
    //                UIImage *scaledImage = [self scaledImageForKey:self.request.URL.absoluteString image:image];
    //                image = [UIImage decodedImageWithImage:scaledImage];
    //                CGImageRelease(partialImageRef);
    //                dispatch_main_sync_safe(^
    //                                        {
    //                                            if (self.completedBlock)
    //                                            {
    //                                                self.completedBlock(image, nil, nil, NO);
    //                                            }
    //                                        });
    //            }
    //        }
    //
    //        CFRelease(imageSource);
    //    }
    
    if (self.progressBlock)
    {
        self.progressBlock(self.imageData.length, self.expectedSize);
    }
}

- (UIImage *)scaledImageForKey:(NSString *)key image:(UIImage *)image
{
    return SDScaledImageForKey(key, image);
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection
{
    CFRunLoopStop(CFRunLoopGetCurrent());
    self.connection = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:nil];
    
    SDWebImageDownloaderCompletedBlock completionBlock = self.completedBlock;
    
    if (completionBlock)
    {
        if (self.options & SDWebImageDownloaderIgnoreCachedResponse && responseFromCached)
        {
            completionBlock(nil, nil, nil, nil, YES);
            self.completionBlock = nil;
            [self done];
        }
        else
        {
            [[CredentialCachingController sharedInstance] getSharedSecretForOurVersion:_ourVersion theirUsername:_theirUsername theirVersion:_theirVersion hashed: _hashed callback:^(id key) {
                
                
                if ([_mimeType isEqualToString:MIME_TYPE_IMAGE]) {
                    
                    UIImage *image = [UIImage sd_imageWithEncryptedData:self.imageData key: key iv:_iv];
                    
                    if (image) {
                        image = [self scaledImageForKey:self.request.URL.absoluteString image:image];
                        
                        if (!image.images) // Do not force decod animated GIFs
                        {
                            image = [UIImage decodedImageWithImage:image];
                        }
                    }
                    
                    
                    
                    if (!image || CGSizeEqualToSize(image.size, CGSizeZero))
                    {
                        completionBlock(nil, nil, nil, [NSError errorWithDomain:@"SDWebImageErrorDomain" code:0 userInfo:@{NSLocalizedDescriptionKey: @"Downloaded image has 0 pixels"}], YES);
                    }
                    else
                    {
                        completionBlock(image, self.imageData, _mimeType, nil, YES);
                    }
                    
                }
                else {
                    if ([_mimeType isEqualToString:MIME_TYPE_M4A]) {
                        //decrypt the audio and cache it
                        NSData * audioData = [EncryptionController symmetricDecryptData: _imageData key: key iv: _iv];
                        if (!audioData)
                        {
                            completionBlock(nil, nil, nil, [NSError errorWithDomain:@"SDWebImageErrorDomain" code:0 userInfo:@{NSLocalizedDescriptionKey: @"no audio data"}], YES);
                        }
                        else
                        {
                            completionBlock(audioData, self.imageData, _mimeType, nil, YES);
                        }
                    }
                    else {
                        completionBlock(nil, nil, nil, [NSError errorWithDomain:@"SDWebImageErrorDomain" code:0 userInfo:@{NSLocalizedDescriptionKey: @"unknown mime type"}], YES);
                    }
                }
                
                self.completionBlock = nil;
                [self done];
                
            }];
        }
        
    }
    else
    {
        [self done];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    CFRunLoopStop(CFRunLoopGetCurrent());
    [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:nil];
    
    if (self.completedBlock)
    {
        self.completedBlock(nil, nil, nil, error, YES);
    }
    
    [self done];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    responseFromCached = NO; // If this method is called, it means the response wasn't read from cache
    if (self.request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData)
    {
        // Prevents caching of responses
        return nil;
    }
    else
    {
        return cachedResponse;
    }
}

- (BOOL)shouldContinueWhenAppEntersBackground
{
    return self.options & SDWebImageDownloaderContinueInBackground;
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    BOOL trustAllCertificates = (self.options & SDWebImageDownloaderAllowInvalidSSLCertificates);
    if (trustAllCertificates && [challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]
             forAuthenticationChallenge:challenge];
    }
    
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

@end

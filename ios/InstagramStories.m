#import <React/RCTLog.h>
#import <Photos/Photos.h>
#import "InstagramStories.h"

@interface InstagramStories ()
@property (nonatomic, strong) NSString *pendingClipboardRestore;
@property (nonatomic, assign) BOOL isRestoringClipboard;
@end

static const NSTimeInterval CLIPBOARD_RESTORE_DELAY = 1.5; // Delay Time for Restoring Clipboard
static const NSTimeInterval CLIPBOARD_RETRY_DELAY = 0.75; // Gap Time for Retrying Restoring Clipboard

@implementation InstagramStories

RCT_EXPORT_MODULE();

- (void)cleanupPendingRestore {
    self.pendingClipboardRestore = nil;
    self.isRestoringClipboard = NO;
}

- (void)restoreClipboardContent:(NSString *)content withRetry:(int)retryCount {
    if (content == nil || retryCount <= 0) {
        [self cleanupPendingRestore];
        return;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CLIPBOARD_RETRY_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[UIPasteboard generalPasteboard] setString:content];
        
        // 클립보드 복원 확인
        if (![content isEqualToString:[UIPasteboard generalPasteboard].string]) {
            [self restoreClipboardContent:content withRetry:retryCount - 1];
        } else {
            [self cleanupPendingRestore];
        }
    });
}

- (void)safeRestoreClipboard:(NSString *)content {
    if (self.isRestoringClipboard) {
        [self cleanupPendingRestore];
    }
    
    if (content != nil) {
        self.pendingClipboardRestore = content;
        self.isRestoringClipboard = YES;
        [self restoreClipboardContent:content withRetry:3];
    }
}

- (void)openInstagramWithItems:(NSDictionary *)items 
                    urlScheme:(NSURL *)urlScheme 
             clipboardContent:(NSString *)previousClipboardContent 
                     resolve:(RCTPromiseResolveBlock)resolve 
                      reject:(RCTPromiseRejectBlock)reject {
    
    NSArray *pasteboardItems = @[items];
    NSDictionary *pasteboardOptions = @{
        UIPasteboardOptionExpirationDate : [[NSDate date] dateByAddingTimeInterval:60 * 5]
    };
    
    [[UIPasteboard generalPasteboard] setItems:pasteboardItems options:pasteboardOptions];
    [[UIApplication sharedApplication] openURL:urlScheme options:@{} completionHandler:^(BOOL success) {
        if (success) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CLIPBOARD_RESTORE_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self safeRestoreClipboard:previousClipboardContent];
            });
            resolve(@[@true, @""]);
        } else {
            reject(@"open_url_error", @"Failed to open Instagram", nil);
        }
    }];    
}

- (void)shareSingle:(NSDictionary *)options
    reject:(RCTPromiseRejectBlock)reject
    resolve:(RCTPromiseResolveBlock)resolve {
    
    NSString *previousClipboardContent = [UIPasteboard generalPasteboard].string;

    NSURL *urlScheme = [NSURL URLWithString:[NSString stringWithFormat:@"instagram-stories://share?source_application=%@", options[@"appId"]]];
    if (![[UIApplication sharedApplication] canOpenURL:urlScheme]) {
        NSError* error = [self fallbackInstagram];
        reject(@"cannot_open_url", @"Instagram is not installed", error);
        return;
    }

    // Create dictionary of assets and attribution
    NSMutableDictionary *items = [NSMutableDictionary dictionary];

    if(![options[@"backgroundImage"] isEqual:[NSNull null]] && options[@"backgroundImage"] != nil) {
        NSURL *backgroundImageURL = [RCTConvert NSURL:options[@"backgroundImage"]];
        UIImage *image = [UIImage imageWithData: [NSData dataWithContentsOfURL:backgroundImageURL]];
        [items setObject:UIImagePNGRepresentation(image) forKey:@"com.instagram.sharedSticker.backgroundImage"];
    }

    if(![options[@"stickerImage"] isEqual:[NSNull null]] && options[@"stickerImage"] != nil) {
        NSURL *stickerImageURL = [RCTConvert NSURL:options[@"stickerImage"]];
        UIImage *image = [UIImage imageWithData: [NSData dataWithContentsOfURL:stickerImageURL]];
        [items setObject:UIImagePNGRepresentation(image) forKey:@"com.instagram.sharedSticker.stickerImage"];
    }

    if(![options[@"attributionURL"] isEqual:[NSNull null]] && options[@"attributionURL"] != nil) {
        NSString *attrURL = [RCTConvert NSString:options[@"attributionURL"]];
        [items setObject:attrURL forKey:@"com.instagram.sharedSticker.contentURL"];
    }

    NSString *backgroundTopColor;
    if(![options[@"backgroundTopColor"] isEqual:[NSNull null]] && options[@"backgroundTopColor"] != nil) {
        backgroundTopColor = [RCTConvert NSString:options[@"backgroundTopColor"]];
    } else {
        backgroundTopColor = @"#906df4";
    }
    [items setObject:backgroundTopColor forKey:@"com.instagram.sharedSticker.backgroundTopColor"];

    NSString *backgroundBottomColor;
    if(![options[@"backgroundBottomColor"] isEqual:[NSNull null]] && options[@"backgroundBottomColor"] != nil) {
        backgroundBottomColor = [RCTConvert NSString:options[@"backgroundBottomColor"]];
    } else {
        backgroundBottomColor = @"#837DF4";
    }
    [items setObject:backgroundBottomColor forKey:@"com.instagram.sharedSticker.backgroundBottomColor"];

    if(![options[@"linkUrl"] isEqual:[NSNull null]] && options[@"linkUrl"] != nil) {
        NSString *linkURL = [RCTConvert NSString:options[@"linkUrl"]];
        [items setObject:linkURL forKey:@"com.instagram.sharedSticker.linkURL"];
    }

    if(![options[@"linkText"] isEqual:[NSNull null]] && options[@"linkText"] != nil) {
        NSString *linkText = [RCTConvert NSString:options[@"linkText"]];
        [items setObject:linkText forKey:@"com.instagram.sharedSticker.linkText"];
    }

    if(![options[@"backgroundVideo"] isEqual:[NSNull null]] && options[@"backgroundVideo"] != nil) {
        NSURL *backgroundVideoURL = [RCTConvert NSURL:options[@"backgroundVideo"]];
        NSString *urlString = backgroundVideoURL.absoluteString;
        NSURLComponents *components = [[NSURLComponents alloc] initWithString:urlString];
        NSString *assetId = nil;

        for (NSURLQueryItem *item in components.queryItems) {
           if ([item.name isEqualToString:@"id"]) {
               assetId = item.value;
               break;
           }
        }

        if (assetId) {
           PHFetchResult *fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetId] options:nil];
           PHAsset *asset = fetchResult.firstObject;
           
           if (asset) {
               PHVideoRequestOptions *videoOptions = [[PHVideoRequestOptions alloc] init];
               videoOptions.networkAccessAllowed = YES;
               videoOptions.deliveryMode = PHVideoRequestOptionsDeliveryModeHighQualityFormat;
               
               [[PHImageManager defaultManager] requestAVAssetForVideo:asset
                                                             options:videoOptions
                                                       resultHandler:^(AVAsset * _Nullable avAsset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
                   if ([avAsset isKindOfClass:[AVURLAsset class]]) {
                       AVURLAsset *urlAsset = (AVURLAsset *)avAsset;
                       NSData *video = [NSData dataWithContentsOfURL:urlAsset.URL];
                       
                       dispatch_async(dispatch_get_main_queue(), ^{
                           if (video) {
                               [items setObject:video forKey:@"com.instagram.sharedSticker.backgroundVideo"];
                               [self openInstagramWithItems:items urlScheme:urlScheme clipboardContent:previousClipboardContent resolve:resolve reject:reject];
                           } else {
                               NSLog(@"Failed to convert video asset to NSData");
                               [self openInstagramWithItems:items urlScheme:urlScheme clipboardContent:previousClipboardContent resolve:resolve reject:reject];
                           }
                       });
                   }
               }];
           } else {
               NSLog(@"Could not find asset with ID: %@", assetId);
               [self openInstagramWithItems:items urlScheme:urlScheme clipboardContent:previousClipboardContent resolve:resolve reject:reject];
           }
        }
    } else {
        [self openInstagramWithItems:items urlScheme:urlScheme clipboardContent:previousClipboardContent resolve:resolve reject:reject];
    }
}

- (NSError*)fallbackInstagram {
    NSString *stringURL = @"https://itunes.apple.com/app/instagram/id389801252";
    NSURL *url = [NSURL URLWithString:stringURL];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];

    NSString *errorMessage = @"Instagram is not installed";
    NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedString(errorMessage, nil)};
    NSError *error = [NSError errorWithDomain:@"com.rnshare" code:1 userInfo:userInfo];

    NSLog(@"%@", errorMessage);
    return error;
}

@end
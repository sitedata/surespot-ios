//
//  UIUtils.h
//  surespot
//
//  Created by Adam on 11/1/13.
//  Copyright (c) 2013 surespot. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import "SurespotConstants.h"
#import "SurespotMessage.h"
#import "REMenu.h"
#import "TTTAttributedLabel.h"

@interface UIUtils : NSObject
+ (void) showToastKey: (NSString *) key;
+ (void) showToastKey: (NSString *) key duration: (CGFloat) duration;
+ (UIColor *) surespotBlue;
+(UIColor *) surespotSelectionBlue;
+(UIColor *) surespotSeparatorGrey;
+(UIColor *) surespotTransparentBlue;
+ (void)setAppAppearances;
+ (BOOL)stringIsNilOrEmpty:(NSString*)aString;
+(UIColor *) surespotGrey;
+(UIColor *) surespotForegroundGrey;
+(UIColor *) surespotTransparentGrey;
+(void) setImageMessageHeights: (SurespotMessage *) message;
+(void) setVoiceMessageHeights: (SurespotMessage *) message;
+(void) startSpinAnimation: (UIView *) view;
+(void) stopSpinAnimation: (UIView *) view;
+(void) startPulseAnimation: (UIView *) view;
+(void) stopPulseAnimation: (UIView *) view;
+(void) showAlertController: (UIAlertController *) controller window: (UIWindow *) window;
+(void) showToastMessage: (NSString *) message duration: (CGFloat) duration;
+(NSString *) getMessageErrorText: (NSInteger) errorStatus mimeType: (NSString *) mimeType;
+(REMenu *) createMenu: (NSArray *) menuItems closeCompletionHandler: (void (^)(void))completionHandler;
+(void) setLinkLabel:(TTTAttributedLabel *) label
            delegate: (id) delegate
           labelText: (NSString *) labelText
      linkMatchTexts: (NSArray *) linkMatchTexts
          urlStrings: (NSArray *) urlStrings;
+(BOOL) getBoolPrefWithDefaultYesForUser: (NSString *) username key:(NSString *) key;
+(BOOL) getBoolPrefWithDefaultNoForUser: (NSString *) username key:(NSString *) key;
+(void) clearLocalCache;
+(NSInteger) getDefaultImageMessageHeight;
+(CGSize)imageSizeAfterAspectFit:(UIImageView*)imgview;
+ (NSString *) buildAliasStringForUsername: (NSString *) username alias: (NSString *) alias;
+ (NSString *)localizedStringForKey:(NSString *)key replaceValue:(NSString *)comment bundle: (NSBundle *) bundle table: (NSString *) table;
+(BOOL) isBlackTheme;
+(void) setTextFieldColors: (UITextField *) textField localizedStringKey: (NSString *) key;
+(BOOL) confirmLogout;
+(double) generateIntervalK: (double) k maxInterval: (double) maxInterval;
+(void) getLocalImageFromAssetUrlOrId: (NSString *) url callback:(CallbackBlock) callback;
+(void) saveImage: (UIImage *) image completionHandler:(void (^)(NSString * localIdentifier)) completionHandler;
+(void) showPasswordAlertTitle: (NSString *) title
                       message: (NSString *) message
                    controller: (UIViewController *) controller
                      callback: (CallbackBlock) callback;
+(UIColor*) getTextColor;
+(NSString *) ensureGiphyLang;
+(UIWindow *) getHighestLevelWindowKeyboardShowing: (BOOL) keyboardShowing;
@end



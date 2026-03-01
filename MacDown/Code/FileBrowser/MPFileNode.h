//
//  MPFileNode.h
//  MacDown
//

#import <Foundation/Foundation.h>

@interface MPFileNode : NSObject

@property (nonatomic, strong, readonly) NSURL *url;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic, readonly) BOOL isMarkdown;
@property (nonatomic, strong, readonly) NSArray<MPFileNode *> *children;
@property (nonatomic, readonly) NSImage *icon;

+ (instancetype)nodeWithURL:(NSURL *)url;
- (void)reloadChildren;
- (void)invalidateChildren;

@end

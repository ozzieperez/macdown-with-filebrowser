//
//  MPFileBrowserController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

extern NSString * const MPFileBrowserRootDidChangeNotification;

@interface MPFileBrowserController : NSViewController
    <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>

@property (nonatomic, strong) NSURL *rootURL;

- (void)reloadTree;
- (IBAction)openFolder:(id)sender;

@end

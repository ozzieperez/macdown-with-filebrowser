//
//  MPFileBrowserController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

extern NSString * const MPFileBrowserRootDidChangeNotification;

@protocol MPFileBrowserDelegate <NSObject>
- (void)fileBrowser:(id)controller didRequestOpenURL:(NSURL *)url;
@end

@interface MPFileBrowserController : NSViewController
    <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>

@property (nonatomic, strong) NSURL *rootURL;
@property (nonatomic, weak) id<MPFileBrowserDelegate> delegate;

- (void)reloadTree;
- (IBAction)openFolder:(id)sender;

@end

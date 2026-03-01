//
//  MPFileNode.m
//  MacDown
//

#import "MPFileNode.h"

static NSSet *MPMarkdownExtensions(void)
{
    static NSSet *extensions = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        extensions = [NSSet setWithObjects:
            @"md", @"markdown", @"mdown", @"mkd", @"mkdn", @"mdwn",
            @"text", @"txt", nil];
    });
    return extensions;
}

@interface MPFileNode ()
@property (nonatomic, strong, readwrite) NSURL *url;
@property (nonatomic, readwrite) BOOL isDirectory;
@property (nonatomic, strong) NSArray<MPFileNode *> *cachedChildren;
@property (nonatomic) BOOL childrenLoaded;
@end

@implementation MPFileNode

+ (instancetype)nodeWithURL:(NSURL *)url
{
    MPFileNode *node = [[MPFileNode alloc] init];
    node.url = url;

    NSNumber *isDir = nil;
    [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
    node.isDirectory = isDir.boolValue;

    return node;
}

- (NSString *)name
{
    return self.url.lastPathComponent;
}

- (BOOL)isMarkdown
{
    if (self.isDirectory)
        return NO;
    NSString *ext = self.url.pathExtension.lowercaseString;
    return [MPMarkdownExtensions() containsObject:ext];
}

- (NSImage *)icon
{
    return [[NSWorkspace sharedWorkspace] iconForFile:self.url.path];
}

- (NSArray<MPFileNode *> *)children
{
    if (!self.isDirectory)
        return nil;
    if (!self.childrenLoaded)
        [self reloadChildren];
    return self.cachedChildren;
}

- (void)reloadChildren
{
    if (!self.isDirectory)
    {
        self.cachedChildren = nil;
        self.childrenLoaded = YES;
        return;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *keys = @[NSURLIsDirectoryKey, NSURLIsHiddenKey];
    NSArray *urls = [manager contentsOfDirectoryAtURL:self.url
                           includingPropertiesForKeys:keys
                                              options:NSDirectoryEnumerationSkipsHiddenFiles
                                                error:nil];

    NSMutableArray<MPFileNode *> *nodes = [NSMutableArray array];
    for (NSURL *childURL in urls)
    {
        MPFileNode *child = [MPFileNode nodeWithURL:childURL];
        if (child.isDirectory || child.isMarkdown)
            [nodes addObject:child];
    }

    [nodes sortUsingComparator:^NSComparisonResult(MPFileNode *a, MPFileNode *b) {
        if (a.isDirectory != b.isDirectory)
            return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedStandardCompare:b.name];
    }];

    self.cachedChildren = [nodes copy];
    self.childrenLoaded = YES;
}

- (void)invalidateChildren
{
    self.childrenLoaded = NO;
    self.cachedChildren = nil;
}

@end

# File Browser Sidebar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an embedded, collapsible file browser sidebar to MacDown's document windows that lets users browse, open, and create markdown files.

**Architecture:** A new outer `NSSplitView` wraps the existing `MPDocumentSplitView` (editor+preview). The left pane holds an `NSOutlineView`-based file browser managed by `MPFileBrowserController`. Files open as tabs via `NSDocumentController`. A new `MPFileNode` model represents the file tree with lazy-loaded children and FSEvents-based file watching.

**Tech Stack:** Objective-C, Cocoa (NSSplitView, NSOutlineView, NSViewController), FSEvents, NSDocumentController

---

### Task 1: Add Preference Properties for File Browser

**Files:**
- Modify: `MacDown/Code/Preferences/MPPreferences.h`

**Step 1: Add file browser preference properties**

In `MPPreferences.h`, add these properties after the `editorEnsuresNewlineAtEndOfFile` line (around line 55):

```objc
// File browser
@property (assign) BOOL fileBrowserVisible;
@property (assign) NSString *fileBrowserRootPath;
@property (assign) CGFloat fileBrowserWidth;
```

**Step 2: Verify the app still compiles**

Run: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacDown/Code/Preferences/MPPreferences.h
git commit -m "feat: add file browser preference properties"
```

---

### Task 2: Create MPFileNode Model Class

**Files:**
- Create: `MacDown/Code/FileBrowser/MPFileNode.h`
- Create: `MacDown/Code/FileBrowser/MPFileNode.m`

**Step 1: Create the header file**

Create `MacDown/Code/FileBrowser/MPFileNode.h`:

```objc
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
```

**Step 2: Create the implementation file**

Create `MacDown/Code/FileBrowser/MPFileNode.m`:

```objc
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
        // Include directories and markdown files only
        if (child.isDirectory || child.isMarkdown)
            [nodes addObject:child];
    }

    // Sort: directories first, then alphabetical
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
```

**Step 3: Add files to the Xcode project**

The new files need to be added to the Xcode project. Open `MacDown.xcodeproj/project.pbxproj` and add the new source files to the `MacDown` target, or do it programmatically:

Run: `mkdir -p MacDown/Code/FileBrowser`

Then add the source files to the Xcode project by editing `project.pbxproj` (or use `xcodegen`/manually add in Xcode).

**Step 4: Verify compilation**

Run: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add MacDown/Code/FileBrowser/
git commit -m "feat: add MPFileNode model for file browser tree"
```

---

### Task 3: Create MPFileBrowserController

**Files:**
- Create: `MacDown/Code/FileBrowser/MPFileBrowserController.h`
- Create: `MacDown/Code/FileBrowser/MPFileBrowserController.m`

**Step 1: Create the header**

Create `MacDown/Code/FileBrowser/MPFileBrowserController.h`:

```objc
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

@end
```

**Step 2: Create the implementation**

Create `MacDown/Code/FileBrowser/MPFileBrowserController.m`:

```objc
//
//  MPFileBrowserController.m
//  MacDown
//

#import "MPFileBrowserController.h"
#import "MPFileNode.h"
#import "MPPreferences.h"

NSString * const MPFileBrowserRootDidChangeNotification =
    @"MPFileBrowserRootDidChangeNotificationName";

@interface MPFileBrowserController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSView *toolbarView;
@property (nonatomic, strong) NSButton *openFolderButton;
@property (nonatomic, strong) NSButton *newFileButton;
@property (nonatomic, strong) NSTextField *pathLabel;
@property (nonatomic, strong) NSView *emptyStateView;
@property (nonatomic, strong) MPFileNode *rootNode;
@property (nonatomic, strong) FSEventStreamRef eventStream;
@end

static void MPFSEventsCallback(
    ConstFSEventStreamRef streamRef,
    void *clientCallBackInfo,
    size_t numEvents,
    void *eventPaths,
    const FSEventStreamEventFlags eventFlags[],
    const FSEventStreamEventId eventIds[])
{
    MPFileBrowserController *controller =
        (__bridge MPFileBrowserController *)clientCallBackInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller reloadTree];
    });
}

@implementation MPFileBrowserController

#pragma mark - Lifecycle

- (void)loadView
{
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 500)];

    [self setupToolbar];
    [self setupOutlineView];
    [self setupEmptyState];
    [self setupContextMenu];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(rootDidChange:)
               name:MPFileBrowserRootDidChangeNotification
             object:nil];
}

- (void)dealloc
{
    [self stopWatching];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Setup

- (void)setupToolbar
{
    NSView *toolbar = [[NSView alloc] init];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:toolbar];
    self.toolbarView = toolbar;

    // Open Folder button
    NSButton *openBtn = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameFolder]
                                           target:self
                                           action:@selector(openFolder:)];
    openBtn.bezelStyle = NSBezelStyleInline;
    openBtn.bordered = NO;
    openBtn.toolTip = @"Open Folder";
    openBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:openBtn];
    self.openFolderButton = openBtn;

    // New File button
    NSButton *newBtn = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameAddTemplate]
                                          target:self
                                          action:@selector(newFile:)];
    newBtn.bezelStyle = NSBezelStyleInline;
    newBtn.bordered = NO;
    newBtn.toolTip = @"New Markdown File";
    newBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:newBtn];
    self.newFileButton = newBtn;

    // Path label
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:10];
    label.textColor = [NSColor secondaryLabelColor];
    label.lineBreakMode = NSLineBreakByTruncatingHead;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:label];
    self.pathLabel = label;

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:28],

        [openBtn.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:4],
        [openBtn.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [openBtn.widthAnchor constraintEqualToConstant:24],
        [openBtn.heightAnchor constraintEqualToConstant:24],

        [newBtn.leadingAnchor constraintEqualToAnchor:openBtn.trailingAnchor constant:2],
        [newBtn.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [newBtn.widthAnchor constraintEqualToConstant:24],
        [newBtn.heightAnchor constraintEqualToConstant:24],

        [label.leadingAnchor constraintEqualToAnchor:newBtn.trailingAnchor constant:4],
        [label.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-4],
        [label.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
    ]];
}

- (void)setupOutlineView
{
    NSOutlineView *outline = [[NSOutlineView alloc] init];
    outline.headerView = nil;
    outline.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
    outline.floatsGroupRows = NO;
    outline.indentationPerLevel = 14;
    outline.dataSource = self;
    outline.delegate = self;
    outline.doubleAction = @selector(outlineViewDoubleClicked:);
    outline.target = self;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"NameColumn"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [outline addTableColumn:column];
    outline.outlineTableColumn = column;

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = outline;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    self.scrollView = scroll;
    self.outlineView = outline;

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.toolbarView.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupEmptyState
{
    NSView *empty = [[NSView alloc] init];
    empty.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:empty];

    NSButton *btn = [[NSButton alloc] init];
    btn.title = @"Open Folder";
    btn.bezelStyle = NSBezelStyleRounded;
    btn.target = self;
    btn.action = @selector(openFolder:);
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [empty addSubview:btn];

    NSTextField *hint = [NSTextField labelWithString:@"Choose a folder to browse\nmarkdown files"];
    hint.alignment = NSTextAlignmentCenter;
    hint.font = [NSFont systemFontOfSize:12];
    hint.textColor = [NSColor tertiaryLabelColor];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [empty addSubview:hint];

    [NSLayoutConstraint activateConstraints:@[
        [empty.topAnchor constraintEqualToAnchor:self.toolbarView.bottomAnchor],
        [empty.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [empty.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [empty.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [btn.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor],
        [btn.centerYAnchor constraintEqualToAnchor:empty.centerYAnchor constant:-10],

        [hint.topAnchor constraintEqualToAnchor:btn.bottomAnchor constant:8],
        [hint.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor],
        [hint.widthAnchor constraintLessThanOrEqualToConstant:180],
    ]];

    self.emptyStateView = empty;
}

- (void)setupContextMenu
{
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    self.outlineView.menu = menu;
}

#pragma mark - Properties

- (void)setRootURL:(NSURL *)rootURL
{
    _rootURL = rootURL;

    [self stopWatching];

    if (rootURL)
    {
        self.rootNode = [MPFileNode nodeWithURL:rootURL];
        self.pathLabel.stringValue = rootURL.path.lastPathComponent;
        self.emptyStateView.hidden = YES;
        self.scrollView.hidden = NO;
        [self.outlineView reloadData];
        [self startWatching];

        // Save to preferences
        MPPreferences *prefs = [MPPreferences sharedInstance];
        prefs.fileBrowserRootPath = rootURL.path;
    }
    else
    {
        self.rootNode = nil;
        self.pathLabel.stringValue = @"";
        self.emptyStateView.hidden = NO;
        self.scrollView.hidden = YES;
        [self.outlineView reloadData];
    }
}

#pragma mark - Actions

- (IBAction)openFolder:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"Open";

    [panel beginSheetModalForWindow:self.view.window
                  completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK)
        {
            self.rootURL = panel.URL;
            // Notify all other windows
            [[NSNotificationCenter defaultCenter]
                postNotificationName:MPFileBrowserRootDidChangeNotification
                              object:self
                            userInfo:@{@"url": panel.URL}];
        }
    }];
}

- (IBAction)newFile:(id)sender
{
    NSURL *targetDir = self.rootURL;

    // If a directory is selected, create in that directory
    MPFileNode *selected = [self.outlineView itemAtRow:self.outlineView.selectedRow];
    if (selected && selected.isDirectory)
        targetDir = selected.url;

    if (!targetDir)
        return;

    [self createNewFileInDirectory:targetDir];
}

- (void)outlineViewDoubleClicked:(id)sender
{
    MPFileNode *item = [self.outlineView itemAtRow:self.outlineView.clickedRow];
    if (!item || item.isDirectory)
        return;

    [self openFileAtURL:item.url];
}

#pragma mark - File Operations

- (void)openFileAtURL:(NSURL *)url
{
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];

    // Check if already open — bring to front if so
    NSDocument *existing = [dc documentForURL:url];
    if (existing)
    {
        [existing showWindows];
        return;
    }

    [dc openDocumentWithContentsOfURL:url
                              display:YES
                    completionHandler:^(NSDocument *doc, BOOL wasOpen, NSError *err) {
        if (err)
            NSLog(@"Failed to open %@: %@", url, err);
    }];
}

- (void)createNewFileInDirectory:(NSURL *)directoryURL
{
    // Generate a unique filename
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *baseName = @"Untitled";
    NSString *ext = @"md";
    NSURL *fileURL = [directoryURL URLByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@.%@", baseName, ext]];
    int counter = 1;
    while ([fm fileExistsAtPath:fileURL.path])
    {
        fileURL = [directoryURL URLByAppendingPathComponent:
                   [NSString stringWithFormat:@"%@ %d.%@", baseName, counter, ext]];
        counter++;
    }

    // Create empty file
    [fm createFileAtPath:fileURL.path contents:[NSData data] attributes:nil];

    // Reload tree and open the file
    [self reloadTree];
    [self openFileAtURL:fileURL];
}

- (void)deleteFileAtURL:(NSURL *)url
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete \"%@\"?", url.lastPathComponent];
    alert.informativeText = @"This will move the file to the Trash.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    [alert beginSheetModalForWindow:self.view.window
                  completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn)
        {
            NSError *error = nil;
            [[NSFileManager defaultManager] trashItemAtURL:url
                                          resultingItemURL:nil
                                                     error:&error];
            if (error)
                NSLog(@"Failed to trash %@: %@", url, error);
            else
                [self reloadTree];
        }
    }];
}

#pragma mark - Tree Management

- (void)reloadTree
{
    [self.rootNode invalidateChildren];
    [self.outlineView reloadData];
}

#pragma mark - FSEvents

- (void)startWatching
{
    if (!self.rootURL || self.eventStream)
        return;

    FSEventStreamContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    CFArrayRef paths = (__bridge CFArrayRef)@[self.rootURL.path];

    self.eventStream = FSEventStreamCreate(
        NULL, &MPFSEventsCallback, &context,
        paths, kFSEventStreamEventIdSinceNow, 1.0,
        kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
    );

    FSEventStreamScheduleWithRunLoop(
        self.eventStream, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    FSEventStreamStart(self.eventStream);
}

- (void)stopWatching
{
    if (self.eventStream)
    {
        FSEventStreamStop(self.eventStream);
        FSEventStreamInvalidate(self.eventStream);
        FSEventStreamRelease(self.eventStream);
        self.eventStream = NULL;
    }
}

#pragma mark - Notifications

- (void)rootDidChange:(NSNotification *)notification
{
    // Another window changed the root folder — sync
    if (notification.object == self)
        return;

    NSURL *url = notification.userInfo[@"url"];
    if (url)
        self.rootURL = url;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (!self.rootNode)
        return 0;
    MPFileNode *node = item ?: self.rootNode;
    return node.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    MPFileNode *node = item ?: self.rootNode;
    return node.children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    MPFileNode *node = item;
    return node.isDirectory;
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    MPFileNode *node = item;

    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"FileCell"
                                                          owner:self];
    if (!cell)
    {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = @"FileCell";

        NSImageView *iv = [[NSImageView alloc] init];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:iv];
        cell.imageView = iv;

        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:tf];
        cell.textField = tf;

        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:16],
            [iv.heightAnchor constraintEqualToConstant:16],

            [tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    cell.textField.stringValue = node.name;
    cell.imageView.image = node.icon;

    // Gray out non-markdown files (shouldn't appear due to filtering, but safety)
    if (!node.isDirectory && !node.isMarkdown)
    {
        cell.textField.textColor = [NSColor tertiaryLabelColor];
    }
    else
    {
        cell.textField.textColor = [NSColor labelColor];
    }

    return cell;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    MPFileNode *node = item;
    // Directories are selectable (for context menu), but non-markdown files are not
    return node.isDirectory || node.isMarkdown;
}

#pragma mark - NSMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];

    NSInteger row = self.outlineView.clickedRow;
    if (row < 0)
        return;

    MPFileNode *node = [self.outlineView itemAtRow:row];
    if (!node)
        return;

    if (node.isDirectory)
    {
        NSMenuItem *newItem = [[NSMenuItem alloc]
            initWithTitle:@"New Markdown File Here"
                   action:@selector(contextNewFile:)
            keyEquivalent:@""];
        newItem.representedObject = node;
        newItem.target = self;
        [menu addItem:newItem];
    }
    else
    {
        NSMenuItem *openItem = [[NSMenuItem alloc]
            initWithTitle:@"Open"
                   action:@selector(contextOpen:)
            keyEquivalent:@""];
        openItem.representedObject = node;
        openItem.target = self;
        [menu addItem:openItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *revealItem = [[NSMenuItem alloc]
        initWithTitle:@"Reveal in Finder"
               action:@selector(contextReveal:)
        keyEquivalent:@""];
    revealItem.representedObject = node;
    revealItem.target = self;
    [menu addItem:revealItem];

    if (!node.isDirectory)
    {
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *deleteItem = [[NSMenuItem alloc]
            initWithTitle:@"Delete"
                   action:@selector(contextDelete:)
            keyEquivalent:@""];
        deleteItem.representedObject = node;
        deleteItem.target = self;
        [menu addItem:deleteItem];
    }
}

- (void)contextNewFile:(NSMenuItem *)sender
{
    MPFileNode *node = sender.representedObject;
    [self createNewFileInDirectory:node.url];
}

- (void)contextOpen:(NSMenuItem *)sender
{
    MPFileNode *node = sender.representedObject;
    [self openFileAtURL:node.url];
}

- (void)contextReveal:(NSMenuItem *)sender
{
    MPFileNode *node = sender.representedObject;
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[node.url]];
}

- (void)contextDelete:(NSMenuItem *)sender
{
    MPFileNode *node = sender.representedObject;
    [self deleteFileAtURL:node.url];
}

@end
```

**Step 3: Add files to Xcode project and verify compilation**

Run: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add MacDown/Code/FileBrowser/
git commit -m "feat: add MPFileBrowserController with outline view, FSEvents, and context menus"
```

---

### Task 4: Add Notification Name Constant

**Files:**
- Modify: `MacDown/Code/Utility/MPGlobals.h`

**Step 1: Add the notification constant**

At the end of `MPGlobals.h` (after line 29), add:

```objc
static NSString * const kMPFileBrowserDirectoryName = @"FileBrowser";
```

**Step 2: Commit**

```bash
git add MacDown/Code/Utility/MPGlobals.h
git commit -m "feat: add file browser directory constant"
```

---

### Task 5: Integrate File Browser into MPDocument

This is the core integration task. We modify `MPDocument` to embed the file browser in a new outer split view.

**Files:**
- Modify: `MacDown/Code/Document/MPDocument.h`
- Modify: `MacDown/Code/Document/MPDocument.m`

**Step 1: Add public interface**

In `MPDocument.h`, add after the `editorVisible` property (line 17):

```objc
@property (readonly) BOOL fileBrowserVisible;
- (IBAction)toggleFileBrowser:(id)sender;
- (IBAction)openFolderInBrowser:(id)sender;
```

**Step 2: Add private properties and imports**

In `MPDocument.m`, add import at the top (after `#import "MPToolbarController.h"` on line 32):

```objc
#import "MPFileBrowserController.h"
```

In the `@interface MPDocument ()` private section (after the `loadedString` property, around line 220), add:

```objc
@property (nonatomic, strong) NSSplitView *outerSplitView;
@property (nonatomic, strong) NSView *fileBrowserContainer;
@property (nonatomic, strong) MPFileBrowserController *fileBrowserController;
@property (nonatomic) CGFloat previousFileBrowserWidth;
```

**Step 3: Add file browser setup in windowControllerDidLoadNib:**

In `windowControllerDidLoadNib:`, after `[super windowControllerDidLoadNib:controller];` (line 361) and before the autosave name code, add:

```objc
    // Set up tabbing mode for tab support
    if (@available(macOS 10.12, *)) {
        controller.window.tabbingMode = NSWindowTabbingModePreferred;
    }

    // Set up the file browser sidebar
    [self setupFileBrowser];
```

**Step 4: Implement setupFileBrowser**

Add this new method in the `#pragma mark - Private` section (before `toggleSplitterCollapsingEditorPane:`, around line 1494):

```objc
- (void)setupFileBrowser
{
    // Create the file browser controller
    self.fileBrowserController = [[MPFileBrowserController alloc] init];
    [self.fileBrowserController loadView]; // Trigger view creation

    // Create a container for the file browser
    NSView *browserView = self.fileBrowserController.view;
    browserView.translatesAutoresizingMaskIntoConstraints = NO;

    // Get the existing split view and its superview (the window's content view)
    NSView *contentView = self.splitView.superview;
    NSView *existingSplitView = self.splitView;

    // Create the outer split view
    NSSplitView *outerSplit = [[NSSplitView alloc] initWithFrame:contentView.bounds];
    outerSplit.vertical = YES;
    outerSplit.dividerStyle = NSSplitViewDividerStyleThin;
    outerSplit.translatesAutoresizingMaskIntoConstraints = NO;
    outerSplit.autosaveName = @"MPFileBrowserSplit";
    outerSplit.delegate = self;
    self.outerSplitView = outerSplit;

    // Create the sidebar container
    NSView *sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 500)];
    sidebarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.fileBrowserContainer = sidebarContainer;

    // Add browser view to container
    [sidebarContainer addSubview:browserView];
    [NSLayoutConstraint activateConstraints:@[
        [browserView.topAnchor constraintEqualToAnchor:sidebarContainer.topAnchor],
        [browserView.leadingAnchor constraintEqualToAnchor:sidebarContainer.leadingAnchor],
        [browserView.trailingAnchor constraintEqualToAnchor:sidebarContainer.trailingAnchor],
        [browserView.bottomAnchor constraintEqualToAnchor:sidebarContainer.bottomAnchor],
    ]];

    // Remove existing split view from content view
    [existingSplitView removeFromSuperview];

    // Remove existing constraints on content view that were for the old split view
    for (NSLayoutConstraint *constraint in [contentView.constraints copy])
    {
        if (constraint.firstItem == existingSplitView || constraint.secondItem == existingSplitView)
            [contentView removeConstraint:constraint];
    }

    // Add sidebar and existing split to the outer split
    [outerSplit addSubview:sidebarContainer];
    [outerSplit addSubview:existingSplitView];

    // Add outer split to content view
    [contentView addSubview:outerSplit];
    [NSLayoutConstraint activateConstraints:@[
        [outerSplit.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [outerSplit.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [outerSplit.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [outerSplit.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];

    // Set holding priorities — sidebar should collapse, not the editor
    [outerSplit setHoldingPriority:200 forSubviewAtIndex:0]; // sidebar
    [outerSplit setHoldingPriority:260 forSubviewAtIndex:1]; // editor+preview

    // Set initial sidebar width
    MPPreferences *prefs = self.preferences;
    CGFloat sidebarWidth = prefs.fileBrowserWidth > 0 ? prefs.fileBrowserWidth : 220;
    [outerSplit setPosition:sidebarWidth ofDividerAtIndex:0];

    // Restore root URL from preferences
    NSString *rootPath = prefs.fileBrowserRootPath;
    if (rootPath && [[NSFileManager defaultManager] fileExistsAtPath:rootPath])
    {
        self.fileBrowserController.rootURL = [NSURL fileURLWithPath:rootPath];
    }

    // Handle visibility
    if (!prefs.fileBrowserVisible)
    {
        self.previousFileBrowserWidth = sidebarWidth;
        [outerSplit setPosition:0 ofDividerAtIndex:0];
    }
}
```

**Step 5: Implement toggle and open folder actions**

Add these methods after the `toggleEditorPane:` action (around line 1484):

```objc
- (IBAction)toggleFileBrowser:(id)sender
{
    if (!self.outerSplitView)
        return;

    BOOL isVisible = self.fileBrowserContainer.frame.size.width > 0;

    if (isVisible)
    {
        // Collapse: save current width, then set to 0
        self.previousFileBrowserWidth = self.fileBrowserContainer.frame.size.width;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            [self.outerSplitView.animator setPosition:0 ofDividerAtIndex:0];
        }];
        self.preferences.fileBrowserVisible = NO;
    }
    else
    {
        // Expand: restore to previous width
        CGFloat width = self.previousFileBrowserWidth > 0 ? self.previousFileBrowserWidth : 220;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            [self.outerSplitView.animator setPosition:width ofDividerAtIndex:0];
        }];
        self.preferences.fileBrowserVisible = YES;
    }
}

- (IBAction)openFolderInBrowser:(id)sender
{
    // Make sidebar visible first
    if (self.fileBrowserContainer.frame.size.width == 0)
    {
        [self toggleFileBrowser:nil];
    }
    [self.fileBrowserController openFolder:sender];
}

- (BOOL)fileBrowserVisible
{
    return self.fileBrowserContainer.frame.size.width > 0;
}
```

**Step 6: Handle NSSplitViewDelegate for the outer split view**

The existing `splitViewDidResizeSubviews:` in MPDocument currently only handles the inner split view. We need to also handle the outer. Modify the existing delegate method (around line 693):

Find the existing `splitViewDidResizeSubviews:` and add a check at the start:

```objc
- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    NSSplitView *splitView = notification.object;

    // Handle outer split (file browser) resize
    if (splitView == self.outerSplitView)
    {
        CGFloat browserWidth = self.fileBrowserContainer.frame.size.width;
        if (browserWidth > 0)
            self.preferences.fileBrowserWidth = browserWidth;
        return;
    }

    // Existing inner split view handling continues below...
    [self redrawDivider];
    ...existing code...
}
```

Also add `splitView:constrainMinCoordinate:ofSubviewAt:` for the outer split:

```objc
- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposedMinimumPosition
             ofSubviewAt:(NSInteger)dividerIndex
{
    if (splitView == self.outerSplitView)
        return 120; // Minimum sidebar width
    return proposedMinimumPosition;
}
```

**Step 7: Verify compilation**

Run: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 8: Commit**

```bash
git add MacDown/Code/Document/MPDocument.h MacDown/Code/Document/MPDocument.m
git commit -m "feat: integrate file browser sidebar into document window"
```

---

### Task 6: Add Menu Items

**Files:**
- Modify: `MacDown/Localization/Base.lproj/MainMenu.xib` (or programmatically in MPMainController)
- Modify: `MacDown/Code/Application/MPMainController.m`

Since XIB editing without Xcode is fragile, we'll add menu items programmatically.

**Step 1: Add menu items in MPMainController**

In `MPMainController.m`, in `applicationDidFinishLaunching:`, add after the Apple Events handler (after line 123):

```objc
    // Add File Browser menu items
    [self addFileBrowserMenuItems];
```

Then add the method:

```objc
- (void)addFileBrowserMenuItems
{
    NSMenu *mainMenu = [NSApp mainMenu];

    // Add to View menu
    NSMenuItem *viewMenuItem = nil;
    for (NSMenuItem *item in mainMenu.itemArray)
    {
        if ([item.title isEqualToString:@"View"])
        {
            viewMenuItem = item;
            break;
        }
    }

    if (viewMenuItem && viewMenuItem.submenu)
    {
        NSMenu *viewMenu = viewMenuItem.submenu;
        [viewMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *toggleBrowser = [[NSMenuItem alloc]
            initWithTitle:NSLocalizedString(@"Toggle File Browser", @"Menu item to toggle file browser")
                   action:@selector(toggleFileBrowser:)
            keyEquivalent:@"b"];
        toggleBrowser.keyEquivalentModifierMask =
            NSEventModifierFlagCommand | NSEventModifierFlagShift;
        [viewMenu addItem:toggleBrowser];
    }

    // Add to File menu
    NSMenuItem *fileMenuItem = nil;
    for (NSMenuItem *item in mainMenu.itemArray)
    {
        if ([item.title isEqualToString:@"File"])
        {
            fileMenuItem = item;
            break;
        }
    }

    if (fileMenuItem && fileMenuItem.submenu)
    {
        NSMenu *fileMenu = fileMenuItem.submenu;

        // Find the "Open" item and insert after it
        NSInteger openIndex = [fileMenu indexOfItemWithTitle:@"Open\u2026"];
        if (openIndex < 0)
            openIndex = [fileMenu indexOfItemWithTitle:@"Open..."];
        if (openIndex < 0)
            openIndex = 1; // fallback

        NSMenuItem *openFolder = [[NSMenuItem alloc]
            initWithTitle:NSLocalizedString(@"Open Folder\u2026", @"Menu item to open folder in browser")
                   action:@selector(openFolderInBrowser:)
            keyEquivalent:@"o"];
        openFolder.keyEquivalentModifierMask =
            NSEventModifierFlagCommand | NSEventModifierFlagShift;
        [fileMenu insertItem:openFolder atIndex:openIndex + 1];
    }
}
```

**Step 2: Verify compilation**

Run: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacDown/Code/Application/MPMainController.m
git commit -m "feat: add File Browser menu items (Cmd+Shift+B, Cmd+Shift+O)"
```

---

### Task 7: Add Sidebar Toggle Toolbar Button

**Files:**
- Modify: `MacDown/Code/Application/MPToolbarController.m`

**Step 1: Add the sidebar toggle button**

In `setupToolbarItems` (around line 48 of `MPToolbarController.m`), add as the first item in the `toolbarItems` array:

```objc
    self->toolbarItems = @[
        [self toolbarItemWithIdentifier:@"toggle-sidebar" label:NSLocalizedString(@"Sidebar", @"Toggle sidebar toolbar button") icon:@"NSImageNameListViewTemplate" action:@selector(toggleFileBrowser:)],
        // ... rest of existing items
```

Note: We need to use a system image name. Since `toolbarItemWithIdentifier:` calls `[NSImage imageNamed:]`, we should use `NSImageNameListViewTemplate` string or create a custom icon image. Actually, let's use a built-in sidebar icon:

Replace the icon parameter. For the sidebar icon, macOS provides `NSImageNameTouchBarSidebarTemplate` (10.12.2+) or we can use `@"NSSidebar"`. Safest approach: use `NSImageNameListViewTemplate`.

Actually, the simplest approach that's compatible: change the toolbarItemWithIdentifier factory to handle system images. But to avoid modifying the factory, let's use a named image that already exists:

In `setupToolbarItems`, add before the `indent-group` entry:

```objc
        [self toolbarItemWithIdentifier:@"toggle-sidebar"
            label:NSLocalizedString(@"Sidebar", @"Toggle sidebar toolbar button")
            icon:@"NSListViewTemplate"
            action:@selector(toggleFileBrowser:)],
```

If `NSListViewTemplate` doesn't work, create a simple icon or use the SF Symbols approach. We'll test during build.

**Step 2: Fix toolbar button target**

The toolbar buttons currently target `self.document`. The `toggleFileBrowser:` action is on `MPDocument`, which IS `self.document`, so this should work.

**Step 3: Verify compilation**

Run: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add MacDown/Code/Application/MPToolbarController.m
git commit -m "feat: add sidebar toggle toolbar button"
```

---

### Task 8: Add Source Files to Xcode Project

**Files:**
- Modify: `MacDown.xcodeproj/project.pbxproj`

Since we've created new `.h` and `.m` files, they need to be registered in the Xcode project file. This can be done using a Ruby script with the `xcodeproj` gem, or manually.

**Step 1: Add files using xcodeproj gem or manually**

The safest approach is to use the `xcodeproj` Ruby gem:

```bash
gem install xcodeproj
```

Then run a script:

```ruby
#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MacDown.xcodeproj')
target = project.targets.find { |t| t.name == 'MacDown' }

# Create group
code_group = project.main_group.find_subpath('MacDown/Code', false)
fb_group = code_group.new_group('FileBrowser', 'Code/FileBrowser')

# Add files
['MPFileNode.h', 'MPFileNode.m', 'MPFileBrowserController.h', 'MPFileBrowserController.m'].each do |f|
  ref = fb_group.new_file("Code/FileBrowser/#{f}")
  target.source_build_phase.add_file_reference(ref) if f.end_with?('.m')
end

project.save
```

Alternatively, open Xcode and drag the files in.

**Step 2: Verify full build**

Run: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacDown.xcodeproj/project.pbxproj
git commit -m "chore: add file browser source files to Xcode project"
```

---

### Task 9: Final Integration Testing

**Step 1: Build and run the app**

Run: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build`

**Step 2: Manual testing checklist**

- [ ] App launches without crashes
- [ ] File browser sidebar is visible on the left
- [ ] "Open Folder" button works, shows directory picker
- [ ] After selecting a folder, tree populates with markdown files and folders
- [ ] Folders are expandable with disclosure triangles
- [ ] Double-clicking a markdown file opens it as a new tab
- [ ] Already-open files are brought to front instead of duplicated
- [ ] Right-click context menu works on files and folders
- [ ] "New Markdown File Here" creates a file and opens it
- [ ] "Delete" moves file to Trash with confirmation
- [ ] "Reveal in Finder" works
- [ ] Cmd+Shift+B toggles sidebar visibility with animation
- [ ] Cmd+Shift+O opens the folder picker
- [ ] Sidebar collapse/expand is smooth
- [ ] Adding/removing files externally updates the tree (FSEvents)
- [ ] Sidebar width is remembered between window opens
- [ ] Root folder is remembered between app launches
- [ ] Multiple document windows share the same root folder

**Step 3: Commit final state**

```bash
git add -A
git commit -m "feat: complete file browser sidebar implementation"
```

---

## Dependency Graph

```
Task 1 (Preferences) ─┐
Task 2 (MPFileNode) ───┤
Task 4 (Constants) ────┼── Task 5 (Integration into MPDocument)
Task 3 (Controller) ───┘         │
                                 ├── Task 6 (Menu Items)
                                 ├── Task 7 (Toolbar Button)
                                 └── Task 8 (Xcode Project)
                                          │
                                          └── Task 9 (Testing)
```

Tasks 1, 2, 3, and 4 can all be done in parallel.
Tasks 6, 7 can be done in parallel after Task 5.
Task 8 should be done last (after all files are created).
Task 9 depends on everything.

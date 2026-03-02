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
@property (nonatomic, strong) NSButton *addFileButton;
@property (nonatomic, strong) NSTextField *pathLabel;
@property (nonatomic, strong) NSView *emptyStateView;
@property (nonatomic, strong) MPFileNode *rootNode;
@property (nonatomic) FSEventStreamRef fsEventStream;
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

    NSButton *openBtn = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameFolder]
                                           target:self
                                           action:@selector(openFolder:)];
    openBtn.bezelStyle = NSBezelStyleInline;
    openBtn.bordered = NO;
    openBtn.toolTip = @"Open Folder";
    openBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:openBtn];
    self.openFolderButton = openBtn;

    NSButton *newBtn = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameAddTemplate]
                                          target:self
                                          action:@selector(newFile:)];
    newBtn.bezelStyle = NSBezelStyleInline;
    newBtn.bordered = NO;
    newBtn.toolTip = @"New Markdown File";
    newBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:newBtn];
    self.addFileButton = newBtn;

    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:10];
    label.textColor = [NSColor secondaryLabelColor];
    label.lineBreakMode = NSLineBreakByTruncatingHead;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:label];
    self.pathLabel = label;

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
    if (self.delegate)
    {
        [self.delegate fileBrowser:self didRequestOpenURL:url];
    }
}

- (void)createNewFileInDirectory:(NSURL *)directoryURL
{
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

    [fm createFileAtPath:fileURL.path contents:[NSData data] attributes:nil];

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
    if (!self.rootURL || self.fsEventStream)
        return;

    FSEventStreamContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    CFArrayRef paths = (__bridge CFArrayRef)@[self.rootURL.path];

    self.fsEventStream = FSEventStreamCreate(
        NULL, &MPFSEventsCallback, &context,
        paths, kFSEventStreamEventIdSinceNow, 1.0,
        kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
    );

    FSEventStreamScheduleWithRunLoop(
        self.fsEventStream, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    FSEventStreamStart(self.fsEventStream);
}

- (void)stopWatching
{
    if (self.fsEventStream)
    {
        FSEventStreamStop(self.fsEventStream);
        FSEventStreamInvalidate(self.fsEventStream);
        FSEventStreamRelease(self.fsEventStream);
        self.fsEventStream = NULL;
    }
}

#pragma mark - Notifications

- (void)rootDidChange:(NSNotification *)notification
{
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

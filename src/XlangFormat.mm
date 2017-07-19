//
//  XlangFormat.mm
//    XcodeClangFormat
//
//  Created by jermainedupris on 7/17/17.
//

#import <Cocoa/Cocoa.h>

namespace {

struct Row {
  Row(NSTableRowView* R) : row(R) {
    NSTableCellView* C = [row viewAtColumn:0];
    name = C.textField;
    path = [[[row viewAtColumn:1] subviews] objectAtIndex:0];
  }
  Row(NSTableView* tableView, NSUInteger row)
      : Row([tableView rowViewAtRow:row makeIfNecessary:FALSE]) {}

  __unsafe_unretained NSTableRowView* row;
  __unsafe_unretained NSTextField* name;
  __unsafe_unretained NSPathControl* path;
};

} // namespace

@interface XlangFormat : NSObject <NSApplicationDelegate, NSPathControlDelegate, NSTableViewDataSource> {
  NSUserDefaults* defaults;
  NSArray* custom;
}
@end

@interface XlangFormat ()

@property (weak) IBOutlet NSWindow *window;
@property(weak) IBOutlet NSButton* llvmStyle;
@property(weak) IBOutlet NSButton* googleStyle;
@property(weak) IBOutlet NSButton* chromiumStyle;
@property(weak) IBOutlet NSButton* mozillaStyle;
@property(weak) IBOutlet NSButton* webkitStyle;
@property(weak) IBOutlet NSTableView* tableView;

@end

@implementation XlangFormat

+ (NSString*) uuid {
    CFUUIDRef uuidRef = CFUUIDCreate(NULL);
    CFStringRef uuidStringRef = CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    return (__bridge_transfer NSString *)uuidStringRef;
}

- (XlangFormat*)init {
    if ((self = [super init])) {
        defaults = nil;
        custom = nil;
    }
    return self;
}

- (NSUInteger)reload {
    if (!defaults) {
        defaults = [[NSUserDefaults alloc] initWithSuiteName:PROJECT_IDENTIFIER];
        NSData* data = [defaults dataForKey: @"custom"];
        if (data)
            custom = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    return custom ? custom.count : 0;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)App {
  return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
}

- (void)applicationWillTerminate:(NSNotification *)notification {
}

- (void)setupRow:(Row&) Row {
    //[Row.name setTarget:self];
    //[Row.name setAction:@selector(nameChanged:)];

    [Row.path setDelegate:self];
    //Row.path.doubleAction = @selector(pathDoubleClick:);
    [Row.path setTarget:self];
    [Row.path setAction:@selector(pathChanged:)];
}

- (NSData*)getSecurityBookmark: (NSURL*) url withOptions:(NSURLBookmarkCreationOptions) options {
    if (!url)
        return nil;

    NSError* error;
    NSData* mark = [url bookmarkDataWithOptions:options
                        includingResourceValuesForKeys:nil
                        relativeToURL:nil
                        error:&error];
    return mark;
}

- (NSURL*) getClangFormatFile:(NSURL*)url {
    NSNumber* isDirectory;
    BOOL success = [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    if (success && [isDirectory boolValue]) {
        NSURL* clang_format = [url URLByAppendingPathComponent:@".clang-format"];
        if ([clang_format checkResourceIsReachableAndReturnError: nil])
            return clang_format;
    }
    return url;
}

- (NSString*)addUUID: (NSMutableDictionary*) uuids from:(NSDictionary*) prev {
    NSString* uuid = prev ? [prev objectForKey:@"id"] : nil;
    if (!uuid) uuid = [XlangFormat uuid];
    [uuids setObject:[NSNumber numberWithInteger:uuids.count] forKey:uuid];
    return uuid;
}

- (void)synchronize: (NSRange) range {
    assert(defaults != nil && "No defaults.");
    assert(self.tableView.numberOfRows >= 0 && "Overflow.");
    range.length += range.location;
    const NSUInteger N = self.tableView.numberOfRows;
    NSMutableArray* array = [NSMutableArray arrayWithCapacity: N];
    NSMutableDictionary* uuids = [[NSMutableDictionary alloc] init];
    for (NSUInteger row = 0; row < N; ++row) {
        NSDictionary* prev  = nil;
        if (row < range.location || row > range.length) {
            prev = [custom objectAtIndex:row];
            [self addUUID: uuids from: prev];
            [array addObject: prev];
            continue;
        }

        Row R(self.tableView, row);

        NSURL* clang_format = [self getClangFormatFile: R.path.URL];
        const NSURLBookmarkResolutionOptions options = NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
        NSData* file = [self getSecurityBookmark: clang_format withOptions: options];
        NSData* bookmark = [self getSecurityBookmark: clang_format withOptions: 0];
        NSData* security = nil;
        if (row < custom.count) {
            prev = [custom objectAtIndex:row];
            // Copy the old bookmarks in
            security = [prev objectForKey:@"security"];
            if (!file)
                file = [prev objectForKey:@"file"];
            if (!bookmark)
                bookmark = [prev objectForKey:@"bookmark"];
        }

        [array addObject: [[NSDictionary alloc] initWithObjectsAndKeys:
                                                R.name.stringValue, @"name",
                                                file, @"file",
                                                bookmark, @"bookmark",
                                                [self addUUID: uuids from: prev], @"id",
                                                security, @"security",
                                                nil]];
        [self setupRow: R];
    }

    custom = array;
    [defaults setObject:[NSKeyedArchiver archivedDataWithRootObject: array]
              forKey: @"custom"];

    [defaults setObject:uuids
              forKey: @"uuids"];

    [defaults synchronize];
}

- (void)synchronize {
    [self synchronize: NSMakeRange(0, self.tableView.numberOfRows)];
}

- (IBAction)pathChanged:(id)sender {
    NSTableRowView* row = (NSTableRowView*) [[((NSView*) sender) superview] superview];
    Row R(row);
    // [R.path.URL.path isEqualToString:R.path.clickedPathItem.URL.path])
    NSString* name = [R.path.URL lastPathComponent];
    NSURL* parent = R.path.URL;
    NSURL* clang_format = [self getClangFormatFile: parent];
    if (clang_format == parent) {
        if ([name hasPrefix: @"."]) {
            parent = [clang_format URLByDeletingLastPathComponent];
            name = [parent lastPathComponent];
        }
    }

    if (!R.path.clickedPathItem.URL || strcmp([R.path.URL fileSystemRepresentation], [R.path.clickedPathItem.URL fileSystemRepresentation]) == 0)
        name = [parent lastPathComponent];
    else if ([R.name.stringValue isEqualToString: [R.path.URL lastPathComponent]])
        name = [R.path.clickedPathItem.URL lastPathComponent];

    [R.name setStringValue: name];
    if (R.path.clickedPathItem.URL)
        R.path.URL = R.path.clickedPathItem.URL;
    NSUInteger Idx = [self.tableView rowForView:row];
    [self synchronize:NSMakeRange(Idx, 1)];
}

- (void)pathControl:(NSPathControl*)pathControl willDisplayOpenPanel:(NSOpenPanel*)openPanel {
    openPanel.title = @"Choose .clang-format file, or directory that contains \".clang-format\"";
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = YES;
    openPanel.showsHiddenFiles = YES;
    openPanel.treatsFilePackagesAsDirectories = YES;
    openPanel.allowsMultipleSelection = NO;
}

- (BOOL) chooseFile:(NSPathControl*)sender {
   NSOpenPanel* panel = [NSOpenPanel openPanel];
   [self pathControl: sender willDisplayOpenPanel: panel];
   panel.canChooseFiles = TRUE;
   panel.canChooseDirectories = TRUE;
   if ([panel runModal] != NSFileHandlingPanelOKButton)
       return FALSE;

   sender.URL = [[panel URLs] objectAtIndex:0];
   [self pathChanged: sender];
   return TRUE;
}

- (IBAction)enableStyle:(id)sender {
    [defaults setBool:!((NSButton*) sender).state forKey:[sender identifier]];
    [defaults synchronize];
}

- (IBAction)addRemoveColumn:(id)sender {
    NSIndexSet* selection = [self.tableView selectedRowIndexes];
    NSView* tableCell = nil;
    NSPathControl* path = nil;
    switch ([sender selectedSegment]) {
        case 0:
            if (!selection.count)
                selection = [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(self.tableView.numberOfRows,1)];
            else
                selection = [NSIndexSet indexSetWithIndex: selection.firstIndex+1];
            [self.tableView insertRowsAtIndexes: selection
                            withAnimation:NSTableViewAnimationSlideUp];
            tableCell = [self.tableView viewAtColumn:1 row:selection.firstIndex makeIfNecessary:TRUE];
            path = [[tableCell subviews] objectAtIndex:0];
            if (![self chooseFile: path]) {
                [self.tableView removeRowsAtIndexes:selection
                                withAnimation:NSTableViewAnimationSlideDown];
            } else
                [self synchronize];
            break;
        case 1:
            if (!selection.count)
                selection = [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(self.tableView.numberOfRows-1,1)];
            [self.tableView removeRowsAtIndexes:selection
                            withAnimation:NSTableViewAnimationSlideDown];
            if (custom) {
                NSMutableArray* copy = [NSMutableArray arrayWithArray:custom];
                [copy removeObjectsInRange:
                      NSMakeRange(selection.firstIndex, selection.count)];
                custom = [copy copy];
            }
            [self synchronize];
            break;
        default:
            break;
    }
}

- (void)editingDidEnd:(NSNotification *)notification {
    [self synchronize];
}

- (void)applicationWillFinishLaunching:(NSNotification*)notification {
    [self reload];
    self.llvmStyle.state = ![defaults boolForKey: @"llvm"];
    self.googleStyle.state = ![defaults boolForKey: @"google"];
    self.chromiumStyle.state = ![defaults boolForKey: @"chromium"];
    self.mozillaStyle.state = ![defaults boolForKey: @"mozilla"];
    self.webkitStyle.state = ![defaults boolForKey: @"webkit"];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(editingDidEnd:)
                                                 name:NSControlTextDidEndEditingNotification
                                               object:nil];

    //[self.tableView setDataSource: self];
    if (!custom)
        return;

    const NSURLBookmarkResolutionOptions options = NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutUI;

    [self.tableView insertRowsAtIndexes: [NSIndexSet indexSetWithIndexesInRange:
                                                    NSMakeRange(0,custom.count)]
                    withAnimation:NSTableViewAnimationEffectNone];
    for (NSUInteger row = 0, N = custom.count; row < N; ++row) {
        NSMutableDictionary* dict = [custom objectAtIndex:row];
        if (!dict || ![dict isKindOfClass: [NSDictionary class]])
            continue;

        Row R(self.tableView, row);
        [self setupRow: R];
        NSData* bookmark = [dict objectForKey:@"file"];
        if (bookmark) {
            // Regenerate the bookmark, so that the extension can read a
            // valid bookmark after a system restart.
            NSError* error = nil;
            BOOL stale = NO;
            NSURL* url = [NSURL URLByResolvingBookmarkData:bookmark
                                                   options:options
                                             relativeToURL:nil
                                       bookmarkDataIsStale:&stale
                                                     error:&error];
#if 1
            if (![dict isKindOfClass: [NSMutableDictionary class]])
                dict = [dict mutableCopy];
            if (url) {
                [url startAccessingSecurityScopedResource];
                NSURL* cf = url = [self getClangFormatFile: url];
                NSData* bookmark = [self getSecurityBookmark: cf withOptions: 0];
                [url stopAccessingSecurityScopedResource];
                [dict setObject: bookmark forKey: @"bookmark"];
                R.path.URL = cf;
            }
            else
                [dict removeObjectForKey: @"bookmark"];
#else
            if (url)
                R.path.URL = url;
#endif
        }

        [R.name setStringValue: [dict objectForKey:@"name"]];
    }
}

@end

extern "C" int main(int argc, const char * argv[]) {
    return NSApplicationMain(argc, argv);
}


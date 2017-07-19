//
//  ClangFormatExtension.mm
//    clang-format
//
//  Created by jermainedupris on 7/17/17.
//

#import <XcodeKit/XcodeKit.h>

@interface ClangFormatExtension : NSObject <XCSourceEditorExtension> @end

@implementation ClangFormatExtension

- (void)addClangFormat: (NSString*) Class name: (NSString*) name id: (NSString*) ID commands:(NSMutableArray*) cmds {
    ID = [PROJECT_IDENTIFIER stringByAppendingString:ID];
    [cmds addObject:[[NSDictionary alloc] initWithObjectsAndKeys:
               ID, XCSourceEditorCommandIdentifierKey,
               name, XCSourceEditorCommandNameKey,
               Class, XCSourceEditorCommandClassNameKey,
               nil]
    ];
}

- (void)addBuiltinClangFormat: (NSUserDefaults*) defaults name:(NSString*) name commands:(NSMutableArray*) cmds {
    NSString* id = [name lowercaseString];
    if (!defaults || ![defaults boolForKey: id]) {
        return [self addClangFormat:@"ClangFormatBuiltin" name:name
                     id:id commands:cmds];
    }
}

- (NSArray <NSDictionary <XCSourceEditorCommandDefinitionKey, id> *> *)commandDefinitions {
    NSMutableArray* commands = [[NSMutableArray alloc] init];
    NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:PROJECT_IDENTIFIER];
    NSString* B[5] = { @"LLVM", @"Chromium", @"Google", @"Mozilla", @"WebKit" };
    for (NSString* name : B)
        [self addBuiltinClangFormat: defaults name:name commands:commands];

    NSData* data = [defaults dataForKey: @"custom"];
    NSArray* items = data ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
    if (items) {
        for (NSDictionary* custom in items) {
            [self addClangFormat: @"ClangFormatCustom"
                  name:[custom objectForKey:@"name"]
                  id:[custom objectForKey:@"id"]
                  commands:commands];
        }
    }

    return [commands copy];
}

// - (void)extensionDidFinishLaunching { }

@end

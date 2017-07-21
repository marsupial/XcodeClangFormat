//
//  ClangFormatCommand.mm
//    clang-format
//
//  Created by jermainedupris on 7/17/17.
//

#import <XcodeKit/XcodeKit.h>
#include <clang/Format/Format.h>

typedef void (^CompletionHandler) (NSError* _NullableCompletionHandler);

class ClangFormatHelper {
  const XCSourceEditorCommandInvocation* const m_Invoke;
  const CompletionHandler m_Completion;
  const unsigned m_Overide;
  enum {
    kOverrideLanguage = 1,
    kOverrideTabs = 2,
    kOverrideIndent = 4,
    kOverrideTabForIndent = 8
  };

  // Generates a list of offsets for ever line in the array.
  static void updateOffsets(std::vector<size_t>& offsets,
                            NSMutableArray<NSString*>* lines) {
    offsets.clear();
    offsets.reserve(lines.count + 1);
    offsets.push_back(0);
    size_t offset = 0;
    for (NSString* line in lines)
      offsets.push_back(offset += line.length);
  }

  template <class T> static NSString* msgFmt(T*) { return @"%@: %@"; }
  static NSString* msgFmt(const char*) { return @"%@: %s"; }

public:
  ClangFormatHelper(XCSourceEditorCommandInvocation* I, CompletionHandler C,
                    unsigned Flags = kOverrideLanguage)
      : m_Invoke(I), m_Completion(C), m_Overide(Flags) {}

  static void error(NSString* Msg, CompletionHandler Complete) {
    Complete([NSError errorWithDomain:PROJECT_IDENTIFIER
                                 code:0
                             userInfo:@{NSLocalizedDescriptionKey : Msg}]);
  }

  template <class T=NSString> void error(NSString* Msg, T* Obj = nil) const {
    if (!Obj)
      return error(Msg, m_Completion);
    error([[NSString alloc] initWithFormat:msgFmt(Obj), Msg, Obj], m_Completion);
  }

  void operator()(clang::format::FormatStyle& format) const {
    if (m_Overide & kOverrideLanguage) {
      NSString* contentUTI = m_Invoke.buffer.contentUTI;
      if ([contentUTI isEqualToString:(__bridge NSString*)kUTTypeObjectiveCSource]) {
        format.Language = clang::format::FormatStyle::LK_ObjC;
      }
      else if ([contentUTI isEqualToString:(__bridge NSString*)kUTTypeCPlusPlusSource] ||
               [contentUTI isEqualToString:(__bridge NSString*)kUTTypeCPlusPlusHeader] ||
               [contentUTI isEqualToString:(__bridge NSString*)kUTTypeObjectiveCPlusPlusSource]) {
        format.Language = clang::format::FormatStyle::LK_Cpp;
      }
      else if ([contentUTI isEqualToString:(__bridge NSString*)kUTTypeCSource] ||
               [contentUTI isEqualToString:(__bridge NSString*)kUTTypeCHeader]) {
        format.Language = clang::format::FormatStyle::LK_Cpp;
      }
    }
    if (m_Overide & kOverrideTabs)
      format.TabWidth = m_Invoke.buffer.tabWidth;
    if (m_Overide & kOverrideIndent)
      format.IndentWidth = m_Invoke.buffer.indentationWidth;
    if (m_Overide & kOverrideTabForIndent && m_Invoke.buffer.usesTabsForIndentation)
      format.UseTab = clang::format::FormatStyle::UT_ForIndentation;

    NSData* buffer =
        [m_Invoke.buffer.completeBuffer dataUsingEncoding:NSUTF8StringEncoding];
    llvm::StringRef code(reinterpret_cast<const char*>(buffer.bytes),
                         buffer.length);

    std::vector<size_t> offsets;
    updateOffsets(offsets, m_Invoke.buffer.lines);

    std::vector<clang::tooling::Range> ranges;
    for (XCSourceTextRange* range in m_Invoke.buffer.selections) {
      const size_t start = offsets[range.start.line] + range.start.column;
      const size_t end = offsets[range.end.line] + range.end.column;
      ranges.emplace_back(start, end - start);
    }

    // Calculated replacements and apply them to the input buffer.
    auto replaces = clang::format::reformat(format, code, ranges);
    auto result = clang::tooling::applyAllReplacements(code, replaces);

    // Check if we could not apply the calculated replacements.
    if (!result)
      return error(@"Failed to apply formatting replacements.");

    // Remove all selections before replacing the completeBuffer, otherwise we
    // get crashes when changing the buffer contents because it tries to
    // automatically update the selections, which might be out of range now.
    [m_Invoke.buffer.selections removeAllObjects];

    // Update the entire text with the result we got after applying the
    // replacements.
    m_Invoke.buffer.completeBuffer =
        [[NSString alloc] initWithBytes:result->data()
                                 length:result->size()
                               encoding:NSUTF8StringEncoding];

    // Recalculate the line offsets.
    updateOffsets(offsets, m_Invoke.buffer.lines);

    // Update the selections with the shifted code positions.
    for (auto& range : ranges) {
      const size_t start = replaces.getShiftedCodePosition(range.getOffset());
      const size_t end = replaces.getShiftedCodePosition(range.getOffset() +
                                                         range.getLength());

      // In offsets, find the value that is smaller than start.
      auto start_it = std::lower_bound(offsets.begin(), offsets.end(), start);
      auto end_it = std::lower_bound(offsets.begin(), offsets.end(), end);
      if (start_it == offsets.end() || end_it == offsets.end())
        continue;

      // We need to go one line back unless we're at the beginning of the line.
      if (*start_it > start)
        --start_it;
      if (*end_it > end)
        --end_it;

      const size_t start_line = std::distance(offsets.begin(), start_it);
      const int64_t start_column = int64_t(start) - int64_t(*start_it);

      const size_t end_line = std::distance(offsets.begin(), end_it);
      const int64_t end_column = int64_t(end) - int64_t(*end_it);

      [m_Invoke.buffer.selections
          addObject:[[XCSourceTextRange alloc]
                        initWithStart:XCSourceTextPositionMake(start_line,
                                                               start_column)
                                  end:XCSourceTextPositionMake(end_line,
                                                               end_column)]];
    }

    // If we could not recover the selection, place the cursor at the beginning
    // of the file.
    if (!m_Invoke.buffer.selections.count) {
      [m_Invoke.buffer.selections
          addObject:[[XCSourceTextRange alloc]
                        initWithStart:XCSourceTextPositionMake(0, 0)
                                  end:XCSourceTextPositionMake(0, 0)]];
    }

    m_Completion(nil);
  }

  NSString* getStyleKey() const {
    return [m_Invoke.commandIdentifier
        substringFromIndex:[PROJECT_IDENTIFIER length]];
  }

  NSData* getCustomStyleForURL(NSURL* url) const {
    NSError* err = nil;
    BOOL Sec = [url startAccessingSecurityScopedResource];
    NSData* data =
        [NSData dataWithContentsOfFile:url.path options:0 error:&err];
    if (Sec) [url stopAccessingSecurityScopedResource];
    if (data && !err) return data;
    error(@"Error loading from security bookmark", err);
    return nil;
  }

  void operator()(NSString* style) const {
    clang::format::FormatStyle format = clang::format::getLLVMStyle();
    auto success = clang::format::getPredefinedStyle(
        llvm::StringRef([style cStringUsingEncoding:NSUTF8StringEncoding]),
        clang::format::FormatStyle::LanguageKind::LK_Cpp, &format);
    if (!success)
        return error(@"Could not parse custom default", style);
    return this->operator()(format);
  }

  void operator()(NSURL* url) const {
    assert(url != nil);
    NSData* config = getCustomStyleForURL(url);
    if (!config)
        return;

    // parse style
    clang::format::FormatStyle format = clang::format::getLLVMStyle();
    llvm::StringRef configString(reinterpret_cast<const char*>(config.bytes),
                                 config.length);
    auto err = clang::format::parseConfiguration(configString, &format);
    if (err)
      return error(@"Could not parse custom style", err.message().c_str());
    return this->operator()(format);
  }
};

@interface ClangFormatCommand : NSObject <XCSourceEditorCommand>
@end

@implementation ClangFormatCommand
- (void)performCommandWithInvocation:(XCSourceEditorCommandInvocation*)XCInvoke
                   completionHandler:(CompletionHandler)completion {
    ClangFormatHelper::error(@"Unimplemented", completion);
}
@end

@interface ClangFormatBuiltin : ClangFormatCommand
@end

@implementation ClangFormatBuiltin
  - (void)performCommandWithInvocation:(XCSourceEditorCommandInvocation*)I
                     completionHandler:(CompletionHandler)C {
    ClangFormatHelper helper(I,C);
    helper(helper.getStyleKey());
}
@end


@interface ClangFormatCustom : ClangFormatCommand @end

@implementation ClangFormatCustom

- (NSURL*)getSandboxedStyle: (ClangFormatHelper&)helper {
    const NSString* uuid = helper.getStyleKey();
    NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:PROJECT_IDENTIFIER];
    assert(defaults != nil);
    NSDictionary* map = [defaults objectForKey:@"uuids"];
    NSNumber* number = [map objectForKey:uuid];
    if (!number) {
        helper.error(@"Could not get custom style uuids.");
        return nil;
    }

    const NSUInteger index = number.unsignedIntegerValue;
    NSData* data = [defaults dataForKey: @"custom"];
    if (!data) {
        helper.error(@"Could not get custom style data.");
        return nil;
    }

    NSArray* custom = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    if (!custom || index >= custom.count){
        helper.error(@"Could not get custom style index.");
        return nil;
    }

    NSDictionary* entry = [custom objectAtIndex:index];

    NSURL* url = nil;
    BOOL stale = TRUE;
    NSError* error = nil;
    NSData* bookmark = [entry objectForKey:@"security"];
    if (bookmark) {
        url = [NSURL URLByResolvingBookmarkData:bookmark
                                        options:NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutUI
                                  relativeToURL:nil
                            bookmarkDataIsStale:&stale
                                          error:&error];
        if (url && !stale && !error)
            return url;
    }

    bookmark = [entry objectForKey: @"bookmark"];
    if (!bookmark) {
        helper.error(@"Could not get custom style bookmark.");
        return nil;
    }

    url = [NSURL URLByResolvingBookmarkData:bookmark
                                    options:NSURLBookmarkResolutionWithoutUI
                              relativeToURL:nil
                        bookmarkDataIsStale:&stale
                                      error:&error];
    if (!url || error) {
        helper.error(@"Could not get custom style url", error);
        return nil;
    }
    
    // Attempt to create new security URL from the regular URL to persist across system reboots.
    bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess
                          includingResourceValuesForKeys:nil
                                           relativeToURL:nil
                                                   error:&error];
   if (!bookmark || error) {
        helper.error(@"Could not create security url", error);
        return url;
    }

    NSMutableDictionary* edited = [entry mutableCopy];
    [edited setObject:bookmark forKey:@"security"];

    NSMutableArray* array = [custom mutableCopy];
    [array replaceObjectAtIndex:index withObject:edited];
    [defaults setObject:[NSKeyedArchiver archivedDataWithRootObject: array]
              forKey: @"custom"];

    [defaults synchronize];
    return url;
}

- (void)performCommandWithInvocation:(XCSourceEditorCommandInvocation*)I
                                     completionHandler:(CompletionHandler)C {
    ClangFormatHelper helper(I, C);
    NSURL* url = [self getSandboxedStyle:helper];
    if (url)
        return helper(url);
}
@end

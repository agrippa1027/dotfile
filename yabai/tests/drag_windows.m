// Disposable standard AppKit windows for the opt-in native drag check.
#import <Cocoa/Cocoa.h>

@interface DragCheckDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, retain) NSMutableArray *windows;
@end

@implementation DragCheckDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.windows = [NSMutableArray array];
  NSArray *colors = @[
    [NSColor colorWithSRGBRed:0.18 green:0.24 blue:0.32 alpha:1],
    [NSColor colorWithSRGBRed:0.28 green:0.20 blue:0.26 alpha:1],
    [NSColor colorWithSRGBRed:0.22 green:0.27 blue:0.20 alpha:1]
  ];
  for (NSUInteger i = 0; i < 3; i++) {
    NSString *name = [NSString stringWithFormat:@"WM Drag Check %c", (int)('A' + i)];
    NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(120 + 50*i, 150 + 50*i, 500, 360)
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
      backing:NSBackingStoreBuffered defer:NO];
    window.title = name;
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(160, 120);
    window.backgroundColor = colors[i];
    NSTextField *caption = [NSTextField labelWithString:name];
    caption.font = [NSFont systemFontOfSize:26 weight:NSFontWeightMedium];
    caption.textColor = NSColor.whiteColor;
    caption.alignment = NSTextAlignmentCenter;
    caption.frame = NSMakeRect(0, 0, 500, 360);
    caption.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = caption;
    [self.windows addObject:window];
    [window makeKeyAndOrderFront:nil];
    [window release];
  }
  [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES;
}
@end

int main(void) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    DragCheckDelegate *delegate = [[DragCheckDelegate alloc] init];
    app.delegate = delegate;
    [app run];
    [delegate release];
  }
  return 0;
}

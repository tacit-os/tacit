#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <QQuickWindow>

void installMacWindowMaterial(QQuickWindow &window, qreal radius)
{
    if (QGuiApplication::platformName() != QStringLiteral("cocoa"))
        return;

    auto *view = reinterpret_cast<NSView *>(window.winId());
    NSWindow *nativeWindow = view.window;
    if (!nativeWindow || !view.superview)
        return;

    nativeWindow.opaque = NO;
    nativeWindow.backgroundColor = NSColor.clearColor;
    nativeWindow.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    auto *blur = [[NSVisualEffectView alloc] initWithFrame:view.frame];
    blur.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    blur.material = NSVisualEffectMaterialUnderWindowBackground;
    blur.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    blur.state = NSVisualEffectStateFollowsWindowActiveState;
    blur.wantsLayer = YES;
    blur.layer.cornerRadius = radius;
    blur.layer.masksToBounds = YES;
    // Clip the Qt foreground too, so opaque content cannot fill a glass corner.
    view.wantsLayer = YES;
    view.layer.cornerRadius = radius;
    view.layer.masksToBounds = YES;
    // The blur must sit behind the entire Qt view, including its Metal layer.
    [view.superview addSubview:blur positioned:NSWindowBelow relativeTo:view];
    [blur release];
}

void dragMacWindow(QQuickWindow &window)
{
    if (QGuiApplication::platformName() != QStringLiteral("cocoa"))
        return;

    auto *view = reinterpret_cast<NSView *>(window.winId());
    NSEvent *event = NSApp.currentEvent;
    if (event.type == NSEventTypeLeftMouseDragged && event.window == view.window)
        [view.window performWindowDragWithEvent:event];
}

void setMacPointingCursor(bool pointing)
{
    if (QGuiApplication::platformName() != QStringLiteral("cocoa"))
        return;

    NSCursor *cursor = pointing ? NSCursor.pointingHandCursor : NSCursor.arrowCursor;
    [cursor set];
}

/* File: main-cocoa.m */

/*
 * Copyright (c) 2011 Peter Ammon
 *
 * This work is free software; you can redistribute it and/or modify it
 * under the terms of either:
 *
 * a) the GNU General Public License as published by the Free Software
 *    Foundation, version 2, or
 *
 * b) the "Angband licence":
 *    This software may be copied and distributed for educational, research,
 *    and not for profit purposes provided that this copyright and statement
 *    are included in all such copies.  Other copyrights may also apply.
 */

#include "angband.h"
////#include "cmds.h"
////#include "dungeon.h"
////#include "files.h"
////#include "init.h"
////#include "grafmode.h"

#if defined(SAFE_DIRECTORY)
#import "buildid.h"
#endif

//#define NSLog(...) ;

#if BORG
#include "borg1.h"
#include "borg9.h"
#endif

#if defined(MACH_O_CARBON)

/* Default creator signature */
//// Sil-y: changed ANGBAND_CREATOR to SIL_CREATOR throughout
////        change with new version
#ifndef SIL_CREATOR
# define SIL_CREATOR 'Sil1'
#endif

/* Mac headers */
#include <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h> // For keycodes

static NSSize const AngbandScaleIdentity = {1.0, 1.0};
static NSString * const AngbandDirectoryNameLib = @"lib";
////static NSString * const AngbandDirectoryNameBase = @"Angband";

static NSString * const AngbandTerminalsDefaultsKey = @"Terminals";
static NSString * const AngbandTerminalRowsDefaultsKey = @"Rows";
static NSString * const AngbandTerminalColumnsDefaultsKey = @"Columns";
static NSString * const AngbandTerminalVisibleDefaultsKey = @"Visible";
static NSInteger const AngbandWindowMenuItemTagBase = 1000;
static NSInteger const AngbandCommandMenuItemTagBase = 2000;

/* We can blit to a large layer or image and then scale it down during live resize, which makes resizing much faster, at the cost of some image quality during resizing */
#ifndef USE_LIVE_RESIZE_CACHE
////# define USE_LIVE_RESIZE_CACHE 1
# define USE_LIVE_RESIZE_CACHE 0
#endif

/*
 * Support the improved game command handling
 */
////#include "textui.h"
////static game_command cmd = { CMD_NULL, 0 };


/* Our command-fetching function */
////static errr cocoa_get_cmd(cmd_context context, bool wait);


/* Application defined event numbers */
enum
{
    AngbandEventWakeup = 1
};

/* Redeclare some 10.7 constants and methods so we can build on 10.6 */
enum
{
    Angband_NSWindowCollectionBehaviorFullScreenPrimary = 1 << 7,
    Angband_NSWindowCollectionBehaviorFullScreenAuxiliary = 1 << 8
};

@interface NSWindow (AngbandLionRedeclares)
- (void)setRestorable:(BOOL)flag;
@end

/* Delay handling of pre-emptive "quit" event */
static BOOL quit_when_ready = FALSE;

/* Whether or not we allow sounds (only relevant for the screensaver, where the user can't configure it in-game) */
static BOOL allow_sounds = YES;

/* Set to indicate the game is over and we can quit without delay */
static Boolean game_is_finished = FALSE;

/* Our frames per second (e.g. 60). A value of 0 means unthrottled. */
static int frames_per_second;

/* Function to get the default font */
static NSFont *default_font;

@class AngbandView;

/* The max number of glyphs we support */
#define GLYPH_COUNT 256

/* An AngbandContext represents a logical Term (i.e. what Angband thinks is a window). This typically maps to one NSView, but may map to more than one NSView (e.g. the Test and real screen saver view). */
@interface AngbandContext : NSObject <NSWindowDelegate>
{
@public
    
    /* The Angband term */
    term *terminal;
    
    /* Column and row cont, by default 80 x 24 */
    size_t cols;
    size_t rows;
    
    /* The size of the border between the window edge and the contents */
    NSSize borderSize;
    
    /* Our array of views */
    NSMutableArray *angbandViews;
    
    /* The buffered image */
    CGLayerRef angbandLayer;
    
    /* The font of this context */
    NSFont *angbandViewFont;
    
    /* If this context owns a window, here it is */
    NSWindow *primaryWindow;
    
    /* "Glyph info": an array of the CGGlyphs and their widths corresponding to the above font. */
    CGGlyph glyphArray[GLYPH_COUNT];
    CGFloat glyphWidths[GLYPH_COUNT];
    
    /* The size of one tile */
    NSSize tileSize;
    
    /* Font's descender */
    CGFloat fontDescender;
    
    /* Whether we are currently in live resize, which affects how big we render our image */
    int inLiveResize;
    
    /* Last time we drew, so we can throttle drawing */
    CFAbsoluteTime lastRefreshTime;
    
    /* To address subpixel rendering overdraw problems, we cache all the characters and attributes we're told to draw */
    wchar_t *charOverdrawCache;
    int *attrOverdrawCache;

@private

    BOOL _hasSubwindowFlags;
    BOOL _windowVisibilityChecked;
}

@property (nonatomic, assign) BOOL hasSubwindowFlags;
@property (nonatomic, assign) BOOL windowVisibilityChecked;

- (void)drawRect:(NSRect)rect inView:(NSView *)view;

/* Called at initialization to set the term */
- (void)setTerm:(term *)t;

/* Called when the context is going down. */
- (void)dispose;

/* Returns the size of the image. */
- (NSSize)imageSize;

/* Return the rect for a tile at given coordinates. */
- (NSRect)rectInImageForTileAtX:(int)x Y:(int)y;

/* Draw the given wide character into the given tile rect. */
- (void)drawWChar:(wchar_t)wchar inRect:(NSRect)tile;

/* Locks focus on the Angband image, and scales the CTM appropriately. */
- (CGContextRef)lockFocus;

/* Locks focus on the Angband image but does NOT scale the CTM. Appropriate for drawing hairlines. */
- (CGContextRef)lockFocusUnscaled;

/* Unlocks focus. */
- (void)unlockFocus;

/* Returns the primary window for this angband context, creating it if necessary */
- (NSWindow *)makePrimaryWindow;

/* Called to add a new Angband view */
- (void)addAngbandView:(AngbandView *)view;

/* Make the context aware that one of its views changed size */
- (void)angbandViewDidScale:(AngbandView *)view;

/* Handle becoming the main window */
- (void)windowDidBecomeMain:(NSNotification *)notification;

/* Return whether the context's primary window is ordered in or not */
- (BOOL)isOrderedIn;

/* Return whether the context's primary window is key */
- (BOOL)isMainWindow;

/* Invalidate the whole image */
- (void)setNeedsDisplay:(BOOL)val;

/* Invalidate part of the image, with the rect expressed in base coordinates */
- (void)setNeedsDisplayInBaseRect:(NSRect)rect;

/* Display (flush) our Angband views */
- (void)displayIfNeeded;

/* Resize context to size of contentRect, and optionally save size to
 * defaults */
- (void)resizeTerminalWithContentRect: (NSRect)contentRect saveToDefaults: (BOOL)saveToDefaults;

/* Called from the view to indicate that it is starting or ending live resize */
- (void)viewWillStartLiveResize:(AngbandView *)view;
- (void)viewDidEndLiveResize:(AngbandView *)view;
- (void)saveWindowVisibleToDefaults: (BOOL)windowVisible;
- (BOOL)windowVisibleUsingDefaults;

/* Class methods */

/* Begins an Angband game. This is the entry point for starting off. */
+ (void)beginGame;

/* Ends an Angband game. */
+ (void)endGame;

/* Internal method */
- (AngbandView *)activeView;

@end

/**
 *  Generate a mask for the subwindow flags. The mask is just a safety check to make sure that our windows show and hide as expected.
 *  This function allows for future changes to the set of flags without needed to update it here (unless the underlying types change).
 */
u32b AngbandMaskForValidSubwindowFlags(void)
{
    int windowFlagBits = sizeof(*(op_ptr->window_flag)) * CHAR_BIT;
    int maxBits = MIN( PW_MAX_FLAGS, windowFlagBits );
    u32b mask = 0;

    for( int i = 0; i < maxBits; i++ )
    {
        if( window_flag_desc[i] != NULL )
        {
            mask |= (1 << i);
        }
    }

    return mask;
}

/**
 *  Check for changes in the subwindow flags and update window visibility. This seems to be called for every user event, so we don't
 *  want to do any unnecessary hiding or showing of windows.
 */
static void AngbandUpdateWindowVisibility(void)
{
    // because this function is called frequently, we'll make the mask static. it doesn't change between calls, since the flags themselves are hardcoded.
    static u32b validWindowFlagsMask = 0;

    if( validWindowFlagsMask == 0 )
    {
        validWindowFlagsMask = AngbandMaskForValidSubwindowFlags();
    }

    // loop through all of the subwindows and see if there is a change in the flags. if so, show or hide the corresponding window.
    // we don't care about the flags themselves; we just want to know if any are set.
    for( int i = 1; i < ANGBAND_TERM_MAX; i++ )
    {
        AngbandContext *angbandContext = angband_term[i]->data;

        if( angbandContext == nil )
        {
            continue;
        }

        // this horrible mess of flags is so that we can try to maintain some user visibility preference. this should allow the user
        // a window and have it stay closed between application launches. however, this means that when a subwindow is turned on, 
        // it will no longer appear automatically. angband has no concept of user control over window visibility, other than the
        // subwindow flags.
        if( !angbandContext.windowVisibilityChecked )
        {
            if( [angbandContext windowVisibleUsingDefaults] )
            {
                [angbandContext->primaryWindow orderFront: nil];
                angbandContext.windowVisibilityChecked = YES;
            }
            else
            {
                [angbandContext->primaryWindow close];
                angbandContext.windowVisibilityChecked = NO;
            }
        }
        else
        {
            BOOL termHasSubwindowFlags = ((op_ptr->window_flag[i] & validWindowFlagsMask) > 0);

            if( angbandContext.hasSubwindowFlags && !termHasSubwindowFlags )
            {
                [angbandContext->primaryWindow close];
                angbandContext.hasSubwindowFlags = NO;
                [angbandContext saveWindowVisibleToDefaults: NO];
            }
            else if( !angbandContext.hasSubwindowFlags && termHasSubwindowFlags )
            {
                [angbandContext->primaryWindow orderFront: nil];
                angbandContext.hasSubwindowFlags = YES;
                [angbandContext saveWindowVisibleToDefaults: YES];
            }
        }
    }

    // make the main window key so that user events go to the right spot
    AngbandContext *mainWindow = angband_term[0]->data;
    [mainWindow->primaryWindow makeKeyAndOrderFront: nil];
}

/* To indicate that a grid element contains a picture, we store 0xFFFF. */
#define NO_OVERDRAW ((wchar_t)(0xFFFF))


/* Here is some support for rounding to pixels in a scaled context */
static double push_pixel(double pixel, double scale, BOOL increase)
{
    double scaledPixel = pixel * scale;
    /* Have some tolerance! */
    double roundedPixel = round(scaledPixel);
    if (fabs(roundedPixel - scaledPixel) <= .0001)
    {
        scaledPixel = roundedPixel;
    }
    else
    {
        scaledPixel = (increase ? ceil : floor)(scaledPixel);
    }
    return scaledPixel / scale;
}

/* Descriptions of how to "push pixels" in a given rect to integralize. For example, PUSH_LEFT means that we round expand the left edge if set, otherwise we shrink it. */
enum
{
    PUSH_LEFT = 0x1,
    PUSH_RIGHT = 0x2,
    PUSH_BOTTOM = 0x4,
    PUSH_TOP = 0x8
};

/* Return a rect whose border is in the "cracks" between tiles */
static NSRect crack_rect(NSRect rect, NSSize scale, unsigned pushOptions)
{
    double rightPixel = push_pixel(NSMaxX(rect), scale.width, !! (pushOptions & PUSH_RIGHT));
    double topPixel = push_pixel(NSMaxY(rect), scale.height, !! (pushOptions & PUSH_TOP));
    double leftPixel = push_pixel(NSMinX(rect), scale.width, ! (pushOptions & PUSH_LEFT));
    double bottomPixel = push_pixel(NSMinY(rect), scale.height, ! (pushOptions & PUSH_BOTTOM));
    return NSMakeRect(leftPixel, bottomPixel, rightPixel - leftPixel, topPixel - bottomPixel);    
}

/* Returns the pixel push options (describing how we round) for the tile at a given index. Currently it's pretty uniform! */
static unsigned push_options(unsigned x, unsigned y)
{
    return PUSH_TOP | PUSH_LEFT;
}

/*
 * Graphics support
 */

/*
 * The tile image
 */
static CGImageRef pict_image;

/*
 * Numbers of rows and columns in a tileset,
 * calculated by the PICT/PNG loading code
 */
static int pict_cols = 0;
static int pict_rows = 0;

/*
 * Value used to signal that we using ASCII, not graphical tiles.
 */ 
#define GRAF_MODE_NONE 0

/*
 * Requested graphics mode (as a grafID).
 * The current mode is stored in current_graphics_mode.
 */
static int graf_mode_req = 0;

/*
 * Helper function to check the various ways that graphics can be enabled, guarding against NULL
 */
////static BOOL graphics_are_enabled(void)
////{
////    return current_graphics_mode && current_graphics_mode->grafID != GRAPHICS_NONE;
////}

/*
 * Hack -- game in progress
 */
static Boolean game_in_progress = FALSE;


/*
 * Indicate if the user chooses "new" to start a game
 */
static Boolean new_game = FALSE; ////


#pragma mark Prototypes
static void wakeup_event_loop(void);
static void hook_plog(const char *str);
static void hook_quit(const char * str);
static void load_prefs(void);
static void load_sounds(void);
static void init_windows(void);
static void open_game(void); ////half
static void open_tutorial(void); ////half
static void handle_open_when_ready(void);
static void play_sound(int event);
static BOOL check_events(int wait);
////static void cocoa_file_open_hook(const char *path, file_type ftype);
static bool cocoa_get_file(const char *suggested_name, char *path, size_t len);
static BOOL send_event(NSEvent *event);
static void record_current_savefile(void);

/*
 * Available values for 'wait'
 */
#define CHECK_EVENTS_DRAIN -1
#define CHECK_EVENTS_NO_WAIT	0
#define CHECK_EVENTS_WAIT 1


/*
 * Note when "open"/"new" become valid
 */
static bool initialized = FALSE;

/* Methods for getting the appropriate NSUserDefaults */
@interface NSUserDefaults (AngbandDefaults)
+ (NSUserDefaults *)angbandDefaults;
@end

@implementation NSUserDefaults (AngbandDefaults)
+ (NSUserDefaults *)angbandDefaults
{
    return [NSUserDefaults standardUserDefaults];
}
@end

/* Methods for pulling images out of the Angband bundle (which may be separate from the current bundle in the case of a screensaver */
@interface NSImage (AngbandImages)
+ (NSImage *)angbandImage:(NSString *)name;
@end

/* The NSView subclass that draws our Angband image */
@interface AngbandView : NSView
{
    IBOutlet AngbandContext *angbandContext;
}

- (void)setAngbandContext:(AngbandContext *)context;
- (AngbandContext *)angbandContext;

@end

@implementation NSImage (AngbandImages)

/* Returns an image in the resource directoy of the bundle containing the Angband view class. */
+ (NSImage *)angbandImage:(NSString *)name
{
    NSBundle *bundle = [NSBundle bundleForClass:[AngbandView class]];
    NSString *path = [bundle pathForImageResource:name];
    NSImage *result;
    if (path) result = [[[NSImage alloc] initByReferencingFile:path] autorelease];
    else result = nil;
    return result;
}

@end


@implementation AngbandContext

@synthesize hasSubwindowFlags=_hasSubwindowFlags;
@synthesize windowVisibilityChecked=_windowVisibilityChecked;

- (NSFont *)selectionFont
{
    return angbandViewFont;
}

- (BOOL)useLiveResizeOptimization
{
    /* If we have graphics turned off, text rendering is fast enough that we don't need to use a live resize optimization. Note here we are depending on current_graphics_mode being NULL when in text mode. */
////    return inLiveResize && graphics_are_enabled();
    return inLiveResize; ////
}

- (NSSize)baseSize
{
    /* We round the base size down. If we round it up, I believe we may end up with pixels that nobody "owns" that may accumulate garbage. In general rounding down is harmless, because any lost pixels may be sopped up by the border. */
    return NSMakeSize(floor(cols * tileSize.width + 2 * borderSize.width), floor(rows * tileSize.height + 2 * borderSize.height));
}

// qsort-compatible compare function for CGSizes
static int compare_advances(const void *ap, const void *bp)
{
    const CGSize *a = ap, *b = bp;
    return (a->width > b->width) - (a->width < b->width);
}

- (void)updateGlyphInfo
{
    // Update glyphArray and glyphWidths
    NSFont *screenFont = [angbandViewFont screenFont];

    // Generate a string containing each MacRoman character
    unsigned char latinString[GLYPH_COUNT];
    size_t i;
    for (i=0; i < GLYPH_COUNT; i++) latinString[i] = (unsigned char)i;
    
    // Turn that into unichar. Angband uses ISO Latin 1.
    unichar unicharString[GLYPH_COUNT] = {0};
    NSString *allCharsString = [[NSString alloc] initWithBytes:latinString length:sizeof latinString encoding:NSISOLatin1StringEncoding];
    [allCharsString getCharacters:unicharString range:NSMakeRange(0, MIN(GLYPH_COUNT, [allCharsString length]))];
    [allCharsString autorelease];
    
    // Get glyphs
    memset(glyphArray, 0, sizeof glyphArray);
    CTFontGetGlyphsForCharacters((CTFontRef)screenFont, unicharString, glyphArray, GLYPH_COUNT);
    
    // Get advances. Record the max advance.
    CGSize advances[GLYPH_COUNT] = {};
    CTFontGetAdvancesForGlyphs((CTFontRef)screenFont, kCTFontHorizontalOrientation, glyphArray, advances, GLYPH_COUNT);
    for (i=0; i < GLYPH_COUNT; i++) {
        glyphWidths[i] = advances[i].width;
    }
    
    // For good non-mono-font support, use the median advance. Start by sorting all advances.
    qsort(advances, GLYPH_COUNT, sizeof *advances, compare_advances);
    
    // Skip over any initially empty run
    size_t startIdx;
    for (startIdx = 0; startIdx < GLYPH_COUNT; startIdx++)
    {
        if (advances[startIdx].width > 0) break;
    }
    
    // Pick the center to find the median
    CGFloat medianAdvance = 0;
    if (startIdx < GLYPH_COUNT)
    { // In case we have all zero advances for some reason
        medianAdvance = advances[(startIdx + GLYPH_COUNT)/2].width;
    }
    
    // Record the descender
    fontDescender = [screenFont descender];
    
    // Record the tile size. Note that these are typically fractional values - which seems sketchy, but we end up scaling the heck out of our view anyways, so it seems to not matter.
    ////half tileSize.width = medianAdvance;
    tileSize.width = medianAdvance + 2; ////half (this additional 2 is needed to avoid subpixel rendering artefacts)
    tileSize.height = [screenFont ascender] - [screenFont descender];
}

- (void)updateImage
{
    NSSize size = NSMakeSize(1, 1);
    
    AngbandView *activeView = [self activeView];
    if (activeView)
    {
        /* If we are in live resize, draw as big as the screen, so we can scale nicely to any size. If we are not in live resize, then use the bounds of the active view. */
        NSScreen *screen;
        if ([self useLiveResizeOptimization] && (screen = [[activeView window] screen]) != NULL)
        {
            size = [screen frame].size;
        }
        else
        {
            size = [activeView bounds].size;
        }
    }
    
    size.width = fmax(1, ceil(size.width));
    size.height = fmax(1, ceil(size.height));
    
    CGLayerRelease(angbandLayer);
    
    // make a bitmap context as an example for our layer
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef exampleCtx = CGBitmapContextCreate(NULL, 1, 1, 8 /* bits per component */, 48 /* bytesPerRow */, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(cs);
    angbandLayer = CGLayerCreateWithContext(exampleCtx, *(CGSize *)&size, NULL);
    CFRelease(exampleCtx);

    [self lockFocus];
    [[NSColor blackColor] set];
    NSRectFill((NSRect){NSZeroPoint, [self baseSize]});
    [self unlockFocus];
}

- (void)requestRedraw
{
    if (! self->terminal) return;
    
    term *old = Term;
    
    /* Activate the term */
    Term_activate(self->terminal);
    
    /* Redraw the contents */
    Term_redraw();
    
    /* Flush the output */
    Term_fresh();
    
    /* Restore the old term */
    Term_activate(old);
}

- (void)setTerm:(term *)t
{
    terminal = t;
}

- (void)viewWillStartLiveResize:(AngbandView *)view
{
#if USE_LIVE_RESIZE_CACHE
    if (inLiveResize < INT_MAX) inLiveResize++;
    else [NSException raise:NSInternalInconsistencyException format:@"inLiveResize overflow"];
    
////    if (inLiveResize == 1 && graphics_are_enabled())
    if (inLiveResize == 1) ////
    {
        [self updateImage];
        
        [self setNeedsDisplay:YES]; //we'll need to redisplay everything anyways, so avoid creating all those little redisplay rects
        [self requestRedraw];
    }
#endif
}

- (void)viewDidEndLiveResize:(AngbandView *)view
{
#if USE_LIVE_RESIZE_CACHE
    if (inLiveResize > 0) inLiveResize--;
    else [NSException raise:NSInternalInconsistencyException format:@"inLiveResize underflow"];
    
////    if (inLiveResize == 0 && graphics_are_enabled())
    if (inLiveResize == 0) ////
    {
        [self updateImage];
        
        [self setNeedsDisplay:YES]; //we'll need to redisplay everything anyways, so avoid creating all those little redisplay rects
        [self requestRedraw];
    }
#endif
}

/* If we're trying to limit ourselves to a certain number of frames per second, then compute how long it's been since we last drew, and then wait until the next frame has passed. */
- (void)throttle
{
    if (frames_per_second > 0)
    {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        CFTimeInterval timeSinceLastRefresh = now - lastRefreshTime;
        CFTimeInterval timeUntilNextRefresh = (1. / (double)frames_per_second) - timeSinceLastRefresh;
        
        if (timeUntilNextRefresh > 0)
        {
            usleep((unsigned long)(timeUntilNextRefresh * 1000000.));
        }
    }
    lastRefreshTime = CFAbsoluteTimeGetCurrent();
}

- (void)drawWChar:(wchar_t)wchar inRect:(NSRect)tile
{
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGFloat tileOffsetY = CTFontGetAscent( (CTFontRef)[angbandViewFont screenFont] );
    CGFloat tileOffsetX = 0.0;
    NSFont *screenFont = [angbandViewFont screenFont];
    UniChar unicharString[2] = {(UniChar)wchar, 0};

    // Get glyph and advance
    CGGlyph thisGlyphArray[1] = { 0 };
    CGSize advances[1] = { { 0, 0 } };
    CTFontGetGlyphsForCharacters((CTFontRef)screenFont, unicharString, thisGlyphArray, 1);
    CGGlyph glyph = thisGlyphArray[0];
    CTFontGetAdvancesForGlyphs((CTFontRef)screenFont, kCTFontHorizontalOrientation, thisGlyphArray, advances, 1);
    CGSize advance = advances[0];
    
    /* If our font is not monospaced, our tile width is deliberately not big enough for every character. In that event, if our glyph is too wide, we need to compress it horizontally. Compute the compression ratio. 1.0 means no compression. */
    double compressionRatio;
    if (advance.width <= NSWidth(tile))
    {
        /* Our glyph fits, so we can just draw it, possibly with an offset */
        compressionRatio = 1.0;
        tileOffsetX = (NSWidth(tile) - advance.width)/2;
    }
    else
    {
        /* Our glyph doesn't fit, so we'll have to compress it */
        compressionRatio = NSWidth(tile) / advance.width;
        tileOffsetX = 0;
    }

    
    /* Now draw it */
    CGAffineTransform textMatrix = CGContextGetTextMatrix(ctx);
    CGFloat savedA = textMatrix.a;

    /* Set the position */
    textMatrix.tx = tile.origin.x + tileOffsetX;
    textMatrix.ty = tile.origin.y + tileOffsetY;

    /* Maybe squish it horizontally. */
    if (compressionRatio != 1.)
    {
        textMatrix.a *= compressionRatio;
    }

    textMatrix = CGAffineTransformScale( textMatrix, 1.0, -1.0 );
    CGContextSetTextMatrix(ctx, textMatrix);
    CGContextShowGlyphsWithAdvances(ctx, &glyph, &CGSizeZero, 1);
    
    /* Restore the text matrix if we messed with the compression ratio */
    if (compressionRatio != 1.)
    {
        textMatrix.a = savedA;
        CGContextSetTextMatrix(ctx, textMatrix);
    }

    textMatrix = CGAffineTransformScale( textMatrix, 1.0, -1.0 );
    CGContextSetTextMatrix(ctx, textMatrix);
}

/* Indication that we're redrawing everything, so get rid of the overdraw cache. */
- (void)clearOverdrawCache
{
    memset(charOverdrawCache, 0, self->cols * self->rows * sizeof *charOverdrawCache);
    memset(attrOverdrawCache, 0, self->cols * self->rows * sizeof *attrOverdrawCache);
}

/* Lock and unlock focus on our image or layer, setting up the CTM appropriately. */
- (CGContextRef)lockFocusUnscaled
{
    /* Create an NSGraphicsContext representing this CGLayer */
    CGContextRef ctx = CGLayerGetContext(angbandLayer);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithGraphicsPort:ctx flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    CGContextSaveGState(ctx);
    return ctx;
}

- (void)unlockFocus
{
    /* Restore the graphics state */
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextRestoreGState(ctx);
    [NSGraphicsContext restoreGraphicsState];
}

- (NSSize)imageSize
{
    /* Return the size of our layer */
    CGSize result = CGLayerGetSize(angbandLayer);
    return NSMakeSize(result.width, result.height);
}

- (CGContextRef)lockFocus
{
    return [self lockFocusUnscaled];
}


- (NSRect)rectInImageForTileAtX:(int)x Y:(int)y
{
    int flippedY = y;
    return NSMakeRect(x * tileSize.width + borderSize.width, flippedY * tileSize.height + borderSize.height, tileSize.width, tileSize.height);
}

- (void)setSelectionFont:(NSFont*)font adjustTerminal: (BOOL)adjustTerminal
{
    /* Record the new font */
    [font retain];
    [angbandViewFont release];
    angbandViewFont = font;
    
    /* Update our glyph info */
    [self updateGlyphInfo];

    if( adjustTerminal )
    {
        // adjust terminal to fit window with new font; save the new columns and rows since they could be changed
        NSRect contentRect = [self->primaryWindow contentRectForFrameRect: [self->primaryWindow frame]];
        [self resizeTerminalWithContentRect: contentRect saveToDefaults: YES];
    }

    /* Update our image */
    [self updateImage];
    
    /* Clear our overdraw cache */
    [self clearOverdrawCache];
    
    /* Get redrawn */
    [self requestRedraw];
}

- (id)init
{
    if ((self = [super init]))
    {
        /* Default rows and cols */
        self->cols = 80;
        self->rows = 24;

        /* Default border size */
        self->borderSize = NSMakeSize(2, 2);

        /* Allocate overdraw cache, unscanned and collectable. */
        self->charOverdrawCache = NSAllocateCollectable(self->cols * self->rows *sizeof *charOverdrawCache, 0);
        self->attrOverdrawCache = NSAllocateCollectable(self->cols * self->rows *sizeof *attrOverdrawCache, 0);
        
        /* Allocate our array of views */
        angbandViews = [[NSMutableArray alloc] init];
        
        /* Make the image. Since we have no views, it'll just be a puny 1x1 image. */
        [self updateImage];

        _windowVisibilityChecked = NO;
    }
    return self;
}

/* Destroy all the receiver's stuff. This is intended to be callable more than once. */
- (void)dispose
{
    terminal = NULL;
    
    /* Disassociate ourselves from our angbandViews */
    [angbandViews makeObjectsPerformSelector:@selector(setAngbandContext:) withObject:nil];
    [angbandViews release];
    angbandViews = nil;
    
    /* Destroy the layer/image */
    CGLayerRelease(angbandLayer);
    angbandLayer = NULL;

    /* Font */
    [angbandViewFont release];
    angbandViewFont = nil;
    
    /* Window */
    [primaryWindow setDelegate:nil];
    [primaryWindow close];
    [primaryWindow release];
    primaryWindow = nil;
    
    /* Free overdraw cache (unless we're GC, in which case it was allocated collectable) */
    if (! [NSGarbageCollector defaultCollector]) free(self->charOverdrawCache);
    self->charOverdrawCache = NULL;
    if (! [NSGarbageCollector defaultCollector]) free(self->attrOverdrawCache);
    self->attrOverdrawCache = NULL;
}

/* Usual Cocoa fare */
- (void)dealloc
{
    [self dispose];
    [super dealloc];
}



#pragma mark -
#pragma mark Directories and Paths Setup

/**
 *  Return the path for Angband's lib directory and bail if it isn't found. The lib directory should be in the bundle's resources directory, since it's copied when built.
 */
+ (NSString *)libDirectoryPath
{
    ////half NSString *bundleLibPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: AngbandDirectoryNameLib];
    NSString *bundleLibPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"../../../lib"]; ////half
    BOOL isDirectory = NO;
    BOOL libExists = [[NSFileManager defaultManager] fileExistsAtPath: bundleLibPath isDirectory: &isDirectory];

    if( !libExists || !isDirectory )
    {
        NSLog( @"[%@ %@]: can't find %@/ in bundle: isDirectory: %d libExists: %d", NSStringFromClass( [self class] ), NSStringFromSelector( _cmd ), AngbandDirectoryNameLib, isDirectory, libExists );
        ////half NSRunAlertPanel( @"Missing Resources", @"Angband was unable to find required resources and must quit. Please report a bug on the Angband forums.", @"Quit", nil, nil );
        NSRunAlertPanel( @"Missing Resources", @"Sil was unable to find the 'lib' folder, which should be in the same folder as the application, so must quit. Please report a bug on the Angband forums.", @"Quit", nil, nil ); ////half
        exit( 0 );
    }

    // angband requires the trailing slash for the directory path
    return [bundleLibPath stringByAppendingString: @"/"];
}

/**
 *  Return the path for the directory where Angband should look for its standard user file tree.
 */
////half + (NSString *)angbandDocumentsPath
////half {
    // angband requires the trailing slash, so we'll just add it here; NSString won't care about it when we use the base path for other things
////half     NSString *documents = [NSSearchPathForDirectoriesInDomains( NSDocumentDirectory, NSUserDomainMask, YES ) lastObject];

////half #if defined(SAFE_DIRECTORY)
////half     NSString *versionedDirectory = [NSString stringWithFormat: @"%@-%s", AngbandDirectoryNameBase, VERSION_STRING];
////half     return [[documents stringByAppendingPathComponent: versionedDirectory] stringByAppendingString: @"/"];
////half #else
////half     return [[documents stringByAppendingPathComponent: AngbandDirectoryNameBase] stringByAppendingString: @"/"];
////half #endif
////half }

/**
 *  Give Angband the base paths that should be used for the various directories it needs. It will create any needed directories.
 */
+ (void)prepareFilePathsAndDirectories
{
    char libpath[PATH_MAX + 1] = "\0";
    ////half char basepath[PATH_MAX + 1] = "\0";

    [[self libDirectoryPath] getFileSystemRepresentation: libpath maxLength: sizeof(libpath)];
    ////half [[self angbandDocumentsPath] getFileSystemRepresentation: basepath maxLength: sizeof(basepath)];

    ////init_file_paths( libpath, libpath, basepath );
    init_file_paths( libpath ); ////
    ////create_needed_dirs();
}



#pragma mark -

/* Entry point for initializing Angband */
+ (void)beginGame
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    //set the command hook
////    cmd_get_hook = cocoa_get_cmd;
    
    /* Hooks in some "z-util.c" hooks */
    plog_aux = hook_plog;
    quit_aux = hook_quit;
    
	/* Hook in to the file_open routine */
////	file_open_hook = cocoa_file_open_hook;

    /* Hook into file saving dialogue routine */
////half    get_file = cocoa_get_file;

    // initialize file paths
    [self prepareFilePathsAndDirectories];

    // load preferences
    load_prefs();
    
	/* Load possible graphics modes */
////	init_graphics_modes("graphics.txt");
    
    // load sounds
    load_sounds();
    
    /* Prepare the windows */
    init_windows();
    
    /* Set up game event handlers */
////    init_display();
    
	/* Register the sound hook */
////	sound_hook = play_sound;
    
    /* Note the "system" */
    ANGBAND_SYS = "mac";
    
    /* Initialize some save file stuff */
    player_egid = getegid();
    
    /* We are now initialized */
    initialized = TRUE;
    
    /* Handle "open_when_ready" */
    handle_open_when_ready();
    
    /* Handle pending events (most notably update) and flush input */
    Term_flush();

////half Sil-y: begin inserted block

    /* Mark ourself as the file creator */
	_fcreator = SIL_CREATOR;
    
	/* Default to saving a "text" file */
	_ftype = 'TEXT';
    
	init_angband();

    use_background_colors = TRUE;

    while (1)
	{
		/* Let the player choose a savefile or start a new game */
		if (!game_in_progress)
		{
			int choice = 0;
			int highlight = 1;
			
			if (p_ptr->is_dead) highlight = 4;
            
			/* Process Events until "new" or "open" is selected */
			while (!game_in_progress)
			{
				choice = initial_menu(&highlight);
				
				switch (choice)
				{
					case 1:
                        open_tutorial();
						break;
					case 2:
                        game_in_progress = TRUE;
                        new_game = TRUE;
						break;
					case 3:
                        open_game();
						break;
					case 4:
						quit(NULL);
						break;
				}
			}
		}
        
		/* Handle pending events (most notably update) and flush input */
		Term_flush();
        
        [pool drain];

		/*
		 * Play a game -- "new_game" is set by "new", "open" or the open document
		 * even handler as appropriate
		 */
		play_game(new_game);
        
		// rerun the first initialization routine
		//init_stuff();
		
		// do some more between-games initialization
		re_init_some_things();
		
		// game no longer in progress
		game_in_progress = FALSE;
	}
    
////half Sil-y: end inserted block
    
////    [pool drain];
////    play_game();
    
}

+ (void)endGame
{    
    /* Hack -- Forget messages */
    msg_flag = FALSE;
    
    p_ptr->playing = FALSE;
    p_ptr->leaving = TRUE;
    quit_when_ready = TRUE;
}


- (IBAction)setGraphicsMode:(NSMenuItem *)sender
{
    /* We stashed the graphics mode ID in the menu item's tag */
    graf_mode_req = [sender tag];

    /* Stash it in UserDefaults */
    [[NSUserDefaults angbandDefaults] setInteger:graf_mode_req forKey:@"GraphicsID"];
    [[NSUserDefaults angbandDefaults] synchronize];
    
    if (game_in_progress)
    {
        /* Hack -- Force redraw */
        do_cmd_redraw();
        
        /* Wake up the event loop so it notices the change */
        wakeup_event_loop();
    }
}

- (void)addAngbandView:(AngbandView *)view
{
    if (! [angbandViews containsObject:view])
    {
        [angbandViews addObject:view];
        [self updateImage];
        [self setNeedsDisplay:YES]; //we'll need to redisplay everything anyways, so avoid creating all those little redisplay rects
        [self requestRedraw];
    }
}

/* We have this notion of an "active" AngbandView, which is the largest - the idea being that in the screen saver, when the user hits Test in System Preferences, we don't want to keep driving the AngbandView in the background.  Our active AngbandView is the widest - that's a hack all right. Mercifully when we're just playing the game there's only one view. */
- (AngbandView *)activeView
{
    if ([angbandViews count] == 1)
        return [angbandViews objectAtIndex:0];
    
    AngbandView *result = nil;
    float maxWidth = 0;
    for (AngbandView *angbandView in angbandViews)
    {
        float width = [angbandView frame].size.width;
        if (width > maxWidth)
        {
            maxWidth = width;
            result = angbandView;
        }
    }
    return result;
}

- (void)angbandViewDidScale:(AngbandView *)view
{
    /* If we're live-resizing with graphics, we're using the live resize optimization, so don't update the image. Otherwise do it. */
////    if (! (inLiveResize && graphics_are_enabled()) && view == [self activeView])
    if (! (inLiveResize) && view == [self activeView])
    {
        [self updateImage];
        
        [self setNeedsDisplay:YES]; //we'll need to redisplay everything anyways, so avoid creating all those little redisplay rects
        [self requestRedraw];
    }
}


- (void)removeAngbandView:(AngbandView *)view
{
    if ([angbandViews containsObject:view])
    {
        [angbandViews removeObject:view];
        [self updateImage];
        [self setNeedsDisplay:YES]; //we'll need to redisplay everything anyways, so avoid creating all those little redisplay rects
        if ([angbandViews count]) [self requestRedraw];
    }
}


static NSMenuItem *superitem(NSMenuItem *self)
{
    NSMenu *supermenu = [[self menu] supermenu];
    int index = [supermenu indexOfItemWithSubmenu:[self menu]];
    if (index == -1) return nil;
    else return [supermenu itemAtIndex:index];
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    int tag = [menuItem tag];
    SEL sel = [menuItem action];
    if (sel == @selector(setGraphicsMode:))
    {
        [menuItem setState: (tag == graf_mode_req)];
        return YES;
    }
    else
    {
        return YES;
    }
}

- (NSWindow *)makePrimaryWindow
{
    if (! primaryWindow)
    {
        // this has to be done after the font is set, which it already is in term_init_cocoa()
        CGFloat width = self->cols * tileSize.width + borderSize.width * 2.0;
        CGFloat height = self->rows * tileSize.height + borderSize.height * 2.0;
        NSRect contentRect = NSMakeRect( 0.0, 0.0, width, height );

        NSUInteger styleMask = NSTitledWindowMask | NSResizableWindowMask | NSMiniaturizableWindowMask;

        // make every window other than the main window closable
        if( angband_term[0]->data != self )
        {
            styleMask |= NSClosableWindowMask;
        }

        primaryWindow = [[NSWindow alloc] initWithContentRect:contentRect styleMask: styleMask backing:NSBackingStoreBuffered defer:YES];

        /* Not to be released when closed */
        [primaryWindow setReleasedWhenClosed:NO];
        [primaryWindow setExcludedFromWindowsMenu: YES]; // we're using custom window menu handling

        /* Make the view */
        AngbandView *angbandView = [[AngbandView alloc] initWithFrame:contentRect];
        [angbandView setAngbandContext:self];
        [angbandViews addObject:angbandView];
        [primaryWindow setContentView:angbandView];
        [angbandView release];

        /* We are its delegate */
        [primaryWindow setDelegate:self];

        /* Update our image, since this is probably the first angband view we've gotten. */
        [self updateImage];
    }
    return primaryWindow;
}



#pragma mark View/Window Passthrough

/* This is what our views call to get us to draw to the window */
- (void)drawRect:(NSRect)rect inView:(NSView *)view
{
    /* Take this opportunity to throttle so we don't flush faster than desird. */
    BOOL viewInLiveResize = [view inLiveResize];
    if (! viewInLiveResize) [self throttle];

    /* With a GLayer, use CGContextDrawLayerInRect */
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    NSRect bounds = [view bounds];
    if (viewInLiveResize) CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawLayerInRect(context, *(CGRect *)&bounds, angbandLayer);
    if (viewInLiveResize) CGContextSetInterpolationQuality(context, kCGInterpolationDefault);
}

- (BOOL)isOrderedIn
{
    return [[[angbandViews lastObject] window] isVisible];
}

- (BOOL)isMainWindow
{
    return [[[angbandViews lastObject] window] isMainWindow];
}

- (void)setNeedsDisplay:(BOOL)val
{
    for (NSView *angbandView in angbandViews)
    {
        [angbandView setNeedsDisplay:val];
    }
}

- (void)setNeedsDisplayInBaseRect:(NSRect)rect
{
    for (NSView *angbandView in angbandViews)
    {
        [angbandView setNeedsDisplayInRect: rect];
    }
}

- (void)displayIfNeeded
{
    [[self activeView] displayIfNeeded];
}

- (void)resizeOverdrawCache
{
    /* Free overdraw cache (unless we're GC, in which case it was allocated collectable) */
    if (! [NSGarbageCollector defaultCollector]) free(self->charOverdrawCache);
    self->charOverdrawCache = NULL;
    if (! [NSGarbageCollector defaultCollector]) free(self->attrOverdrawCache);
    self->attrOverdrawCache = NULL;

    /* Allocate overdraw cache, unscanned and collectable. */
    self->charOverdrawCache = NSAllocateCollectable(self->cols * self->rows *sizeof *charOverdrawCache, 0);
    self->attrOverdrawCache = NSAllocateCollectable(self->cols * self->rows *sizeof *attrOverdrawCache, 0);
}

- (int)terminalIndex
{
	int termIndex = 0;

	for( termIndex = 0; termIndex < ANGBAND_TERM_MAX; termIndex++ )
	{
		if( angband_term[termIndex] == self->terminal )
		{
			break;
		}
	}

	return termIndex;
}

- (void)resizeTerminalWithContentRect: (NSRect)contentRect saveToDefaults: (BOOL)saveToDefaults
{
    CGFloat newRows = floor( (contentRect.size.height - (borderSize.height * 2.0)) / tileSize.height );
    CGFloat newColumns = ceil( (contentRect.size.width - (borderSize.width * 2.0)) / tileSize.width );

    self->cols = newColumns;
    self->rows = newRows;
    [self resizeOverdrawCache];

    if( saveToDefaults )
    {
        int termIndex = [self terminalIndex];
        NSArray *terminals = [[NSUserDefaults standardUserDefaults] valueForKey: AngbandTerminalsDefaultsKey];

        if( termIndex < (int)[terminals count] )
        {
            NSMutableDictionary *mutableTerm = [[NSMutableDictionary alloc] initWithDictionary: [terminals objectAtIndex: termIndex]];
            [mutableTerm setValue: [NSNumber numberWithUnsignedInt: self->cols] forKey: AngbandTerminalColumnsDefaultsKey];
            [mutableTerm setValue: [NSNumber numberWithUnsignedInt: self->rows] forKey: AngbandTerminalRowsDefaultsKey];

            NSMutableArray *mutableTerminals = [[NSMutableArray alloc] initWithArray: terminals];
            [mutableTerminals replaceObjectAtIndex: termIndex withObject: mutableTerm];

            [[NSUserDefaults standardUserDefaults] setValue: mutableTerminals forKey: AngbandTerminalsDefaultsKey];
            [mutableTerminals release];
            [mutableTerm release];
        }
    }

    term *old = Term;
    Term_activate( self->terminal );
    Term_resize( (int)newColumns, (int)newRows);
    Term_redraw();
    Term_activate( old );
}

- (void)saveWindowVisibleToDefaults: (BOOL)windowVisible
{
	int termIndex = [self terminalIndex];
	BOOL safeVisibility = (termIndex == 0) ? YES : windowVisible; // ensure main term doesn't go away because of these defaults
	NSArray *terminals = [[NSUserDefaults standardUserDefaults] valueForKey: AngbandTerminalsDefaultsKey];

	if( termIndex < (int)[terminals count] )
	{
		NSMutableDictionary *mutableTerm = [[NSMutableDictionary alloc] initWithDictionary: [terminals objectAtIndex: termIndex]];
		[mutableTerm setValue: [NSNumber numberWithBool: safeVisibility] forKey: AngbandTerminalVisibleDefaultsKey];

		NSMutableArray *mutableTerminals = [[NSMutableArray alloc] initWithArray: terminals];
		[mutableTerminals replaceObjectAtIndex: termIndex withObject: mutableTerm];

		[[NSUserDefaults standardUserDefaults] setValue: mutableTerminals forKey: AngbandTerminalsDefaultsKey];
		[mutableTerminals release];
		[mutableTerm release];
	}
}

- (BOOL)windowVisibleUsingDefaults
{
	int termIndex = [self terminalIndex];

	if( termIndex == 0 )
	{
		return YES;
	}

	NSArray *terminals = [[NSUserDefaults standardUserDefaults] valueForKey: AngbandTerminalsDefaultsKey];
	BOOL visible = NO;

	if( termIndex < (int)[terminals count] )
	{
		NSDictionary *term = [terminals objectAtIndex: termIndex];
		NSNumber *visibleValue = [term valueForKey: AngbandTerminalVisibleDefaultsKey];

		if( visibleValue != nil )
		{
			visible = [visibleValue boolValue];
		}
	}

	return visible;
}

#pragma mark -
#pragma mark NSWindowDelegate Methods

//- (void)windowWillStartLiveResize: (NSNotification *)notification
//{
//}

- (void)windowDidEndLiveResize: (NSNotification *)notification
{
    NSWindow *window = [notification object];
    NSRect contentRect = [window contentRectForFrameRect: [window frame]];
    [self resizeTerminalWithContentRect: contentRect saveToDefaults: YES];
}

//- (NSSize)windowWillResize: (NSWindow *)sender toSize: (NSSize)frameSize
//{
//}

- (void)windowDidEnterFullScreen: (NSNotification *)notification
{
    NSWindow *window = [notification object];
    NSRect contentRect = [window contentRectForFrameRect: [window frame]];
    [self resizeTerminalWithContentRect: contentRect saveToDefaults: NO];
}

- (void)windowDidExitFullScreen: (NSNotification *)notification
{
    NSWindow *window = [notification object];
    NSRect contentRect = [window contentRectForFrameRect: [window frame]];
    [self resizeTerminalWithContentRect: contentRect saveToDefaults: NO];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
    NSWindow *window = [notification object];

    if( window != self->primaryWindow )
    {
        return;
    }

    int termIndex = 0;

    for( termIndex = 0; termIndex < ANGBAND_TERM_MAX; termIndex++ )
    {
        if( angband_term[termIndex] == self->terminal )
        {
            break;
        }
    }

    NSMenuItem *item = [[[NSApplication sharedApplication] windowsMenu] itemWithTag: AngbandWindowMenuItemTagBase + termIndex];
    [item setState: NSOnState];

    if( [[NSFontPanel sharedFontPanel] isVisible] )
    {
        [[NSFontPanel sharedFontPanel] setPanelFont: [self selectionFont] isMultiple: NO];
    }
}

- (void)windowDidResignMain: (NSNotification *)notification
{
    NSWindow *window = [notification object];

    if( window != self->primaryWindow )
    {
        return;
    }

    int termIndex = 0;

    for( termIndex = 0; termIndex < ANGBAND_TERM_MAX; termIndex++ )
    {
        if( angband_term[termIndex] == self->terminal )
        {
            break;
        }
    }

    NSMenuItem *item = [[[NSApplication sharedApplication] windowsMenu] itemWithTag: AngbandWindowMenuItemTagBase + termIndex];
    [item setState: NSOffState];
}

- (void)windowWillClose: (NSNotification *)notification
{
	[self saveWindowVisibleToDefaults: NO];
}

@end


@implementation AngbandView

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)rect
{
    if (! angbandContext)
    {
        /* Draw bright orange, 'cause this ain't right */
        [[NSColor orangeColor] set];
        NSRectFill([self bounds]);
    }
    else
    {
        /* Tell the Angband context to draw into us */
        [angbandContext drawRect:rect inView:self];
    }
}

- (void)setAngbandContext:(AngbandContext *)context
{
    angbandContext = context;
}

- (AngbandContext *)angbandContext
{
    return angbandContext;
}

- (void)setFrameSize:(NSSize)size
{
    BOOL changed = ! NSEqualSizes(size, [self frame].size);
    [super setFrameSize:size];
    if (changed) [angbandContext angbandViewDidScale:self];
}

- (void)viewWillStartLiveResize
{
    [angbandContext viewWillStartLiveResize:self];
}

- (void)viewDidEndLiveResize
{
    [angbandContext viewDidEndLiveResize:self];
}

@end

/*
 * Delay handling of double-clicked savefiles
 */
Boolean open_when_ready = FALSE;



/*** Some generic functions ***/

/* Sets an Angband color at a given index */
static void set_color_for_index(int idx)
{
    u16b rv, gv, bv;
    
    /* Extract the R,G,B data */
    rv = angband_color_table[idx][1];
    gv = angband_color_table[idx][2];
    bv = angband_color_table[idx][3];
    
    CGContextSetRGBFillColor([[NSGraphicsContext currentContext] graphicsPort], rv/255., gv/255., bv/255., 1.);
}

/* Remember the current character in UserDefaults so we can select it by default next time. */
static void record_current_savefile(void)
{
    NSString *savefileString = [[NSString stringWithCString:savefile encoding:NSMacOSRomanStringEncoding] lastPathComponent];
    if (savefileString)
    {
        NSUserDefaults *angbandDefs = [NSUserDefaults angbandDefaults];
        [angbandDefs setObject:savefileString forKey:@"SaveFile"];
        [angbandDefs synchronize];        
    }
}


/*** Support for the "z-term.c" package ***/

/*
 * Initialize a new Term
 *
 */
static void Term_init_cocoa(term *t)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    AngbandContext *context = [[AngbandContext alloc] init];
    
    /* Give the term a hard retain on context (for GC) */
    t->data = (void *)CFRetain(context);
    [context release];
    
    /* Handle graphics */
    t->higher_pict = !! use_graphics;
    t->always_pict = FALSE;
    
    NSDisableScreenUpdates();
    
    /* Figure out the frame autosave name based on the index of this term */
    NSString *autosaveName = nil;
    int termIdx;
    for (termIdx = 0; termIdx < ANGBAND_TERM_MAX; termIdx++)
    {
        if (angband_term[termIdx] == t)
        {
            autosaveName = [NSString stringWithFormat:@"AngbandTerm-%d", termIdx];
            break;
        }
    }

    /* Set its font. */
    NSString *fontName = [[NSUserDefaults angbandDefaults] stringForKey:[NSString stringWithFormat:@"FontName-%d", termIdx]];
    if (! fontName) fontName = [default_font fontName];

    // use a smaller default font for the other windows, but only if the font hasn't been explicitly set
    ////half float fontSize = (termIdx > 0) ? 10.0 : [default_font pointSize];
    float fontSize = (termIdx > 0) ? 9.0 : [default_font pointSize]; ////half
    if (termIdx == WINDOW_MONSTER) fontSize = 11.0; ////half
    
    NSNumber *fontSizeNumber = [[NSUserDefaults angbandDefaults] valueForKey: [NSString stringWithFormat: @"FontSize-%d", termIdx]];

    if( fontSizeNumber != nil )
    {
        fontSize = [fontSizeNumber floatValue];
    }

    [context setSelectionFont:[NSFont fontWithName:fontName size:fontSize] adjustTerminal: NO];

    NSArray *terminalDefaults = [[NSUserDefaults standardUserDefaults] valueForKey: AngbandTerminalsDefaultsKey];
    NSInteger rows = 24;
    NSInteger columns = 80;

    if( termIdx < (int)[terminalDefaults count] )
    {
        NSDictionary *term = [terminalDefaults objectAtIndex: termIdx];
        rows = [[term valueForKey: AngbandTerminalRowsDefaultsKey] integerValue];
        columns = [[term valueForKey: AngbandTerminalColumnsDefaultsKey] integerValue];
    }

    context->cols = columns;
    context->rows = rows;
    [context resizeOverdrawCache];

    /* Get the window */
    NSWindow *window = [context makePrimaryWindow];
    
    /* Set its title and, for auxiliary terms, tentative size */
    if (termIdx == 0)
    {
        [window setTitle:@"Sil"]; ////half
    }
    else
    {
        ////half [window setTitle:[NSString stringWithFormat:@"Term %d", termIdx]];
        [window setTitle:[NSString stringWithUTF8String: angband_term_name[termIdx]]]; ////half
    }
    
    
    /* If this is the first term, and we support full screen (Mac OS X Lion or later), then allow it to go full screen (sweet). Allow other terms to be FullScreenAuxilliary, so they can at least show up. Unfortunately in Lion they don't get brought to the full screen space; but they would only make sense on multiple displays anyways so it's not a big loss. */
    if ([window respondsToSelector:@selector(toggleFullScreen:)])
    {
        NSWindowCollectionBehavior behavior = [window collectionBehavior];
        behavior |= (termIdx == 0 ? Angband_NSWindowCollectionBehaviorFullScreenPrimary : Angband_NSWindowCollectionBehaviorFullScreenAuxiliary);
        [window setCollectionBehavior:behavior];
    }
    
    /* No Resume support yet, though it would not be hard to add */
    if ([window respondsToSelector:@selector(setRestorable:)])
    {
        [window setRestorable:NO];
    }

	/* default window placement */
    {
        ////half: commented out this block to replace it with my defaults
        /*
		static NSRect overallBoundingRect;

		if( termIdx == 0 )
		{
			// this is a bit of a trick to allow us to display multiple windows in the "standard default" window position in OS X: the upper center of the screen.
			// the term sizes set in load_prefs() are based on a 5-wide by 3-high grid, with the main term being 4/5 wide by 2/3 high (hence the scaling to find
			// what the containing rect would be).
			NSRect originalMainTermFrame = [window frame];
			NSRect scaledFrame = originalMainTermFrame;
			scaledFrame.size.width *= 5.0 / 4.0;
			scaledFrame.size.height *= 3.0 / 2.0;
			scaledFrame.size.width += 1.0; // spacing between window columns
			scaledFrame.size.height += 1.0; // spacing between window rows
			[window setFrame: scaledFrame  display: NO];
			[window center];
			overallBoundingRect = [window frame];
			[window setFrame: originalMainTermFrame display: NO];
		}

		static NSRect mainTermBaseRect;
		NSRect windowFrame = [window frame];

		if( termIdx == 0 )
		{
			// the height and width adjustments were determined experimentally, so that the rest of the windows line up nicely without overlapping
            windowFrame.size.width += 7.0;
			windowFrame.size.height += 9.0;
			windowFrame.origin.x = NSMinX( overallBoundingRect );
			windowFrame.origin.y = NSMaxY( overallBoundingRect ) - NSHeight( windowFrame );
			mainTermBaseRect = windowFrame;
		}
		else if( termIdx == 1 )
		{
			windowFrame.origin.x = NSMinX( mainTermBaseRect );
			windowFrame.origin.y = NSMinY( mainTermBaseRect ) - NSHeight( windowFrame ) - 1.0;
		}
		else if( termIdx == 2 )
		{
			windowFrame.origin.x = NSMaxX( mainTermBaseRect ) + 1.0;
			windowFrame.origin.y = NSMaxY( mainTermBaseRect ) - NSHeight( windowFrame );
		}
		else if( termIdx == 3 )
		{
			windowFrame.origin.x = NSMaxX( mainTermBaseRect ) + 1.0;
			windowFrame.origin.y = NSMinY( mainTermBaseRect ) - NSHeight( windowFrame ) - 1.0;
		}
		else if( termIdx == 4 )
		{
			windowFrame.origin.x = NSMaxX( mainTermBaseRect ) + 1.0;
			windowFrame.origin.y = NSMinY( mainTermBaseRect );
		}
		else if( termIdx == 5 )
		{
			windowFrame.origin.x = NSMinX( mainTermBaseRect ) + NSWidth( windowFrame ) + 1.0;
			windowFrame.origin.y = NSMinY( mainTermBaseRect ) - NSHeight( windowFrame ) - 1.0;
		}
        */

        ////half: here are the new window placement defaults
		NSRect windowFrame = [window frame];

        NSRect screen = [[NSScreen mainScreen] frame];

        int left = 45;
        int bottom = (int)screen.size.height - 795; //285;
        int main_w = 808;
        int main_h = 600;
        int recall_h = 173;
        int side_w = 425;
        int inventory_h = 310;
        int equipment_h = 207;
        int combat_rolls_h = 256;

        if( termIdx == WINDOW_MAIN )
		{
            windowFrame.size.width = main_w;
			windowFrame.size.height = main_h;
			windowFrame.origin.x = left;
			windowFrame.origin.y = bottom + recall_h;
		}
		else if( termIdx == WINDOW_INVEN )
		{
            windowFrame.size.width = side_w;
			windowFrame.size.height = inventory_h;
			windowFrame.origin.x = left + main_w + 2;
			windowFrame.origin.y = bottom + combat_rolls_h + equipment_h;
		}
		else if( termIdx == WINDOW_EQUIP )
		{
            windowFrame.size.width = side_w;
			windowFrame.size.height = equipment_h;
			windowFrame.origin.x = left + main_w + 2;
			windowFrame.origin.y = bottom + combat_rolls_h;
		}
		else if( termIdx == WINDOW_COMBAT_ROLLS )
		{
            windowFrame.size.width = side_w;
			windowFrame.size.height = combat_rolls_h;
			windowFrame.origin.x = left + main_w + 2;
			windowFrame.origin.y = bottom;
		}
		else if( termIdx == WINDOW_MONSTER )
		{
            windowFrame.size.width = main_w;
			windowFrame.size.height = recall_h;
			windowFrame.origin.x = left;
			windowFrame.origin.y = bottom;
		}
		else
		{
            windowFrame.size.width = side_w;
			windowFrame.size.height = inventory_h;
			windowFrame.origin.x = left + (termIdx * 10) - 40;
			windowFrame.origin.y = bottom + recall_h + 200 - (termIdx * 10) + 40;
		}
        ////half: this ends the new window placement defaults
        
		[window setFrame: windowFrame display: NO];
	}

	// override the default frame above if the user has adjusted windows in the past
	if (autosaveName) [window setFrameAutosaveName:autosaveName];

    /* Tell it about its term. Do this after we've sized it so that the sizing doesn't trigger redrawing and such. */
    [context setTerm:t];
    
    /* Only order front if it's the first term. Other terms will be ordered front from AngbandUpdateWindowVisibility(). This is to work around a problem where Angband aggressively tells us to initialize terms that don't do anything! */
    if (t == angband_term[0]) [context->primaryWindow makeKeyAndOrderFront: nil];
    
    NSEnableScreenUpdates();
    
    /* Set "mapped" flag */
    t->mapped_flag = true;
    [pool drain];
}



/*
 * Nuke an old Term
 */
static void Term_nuke_cocoa(term *t)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AngbandContext *context = t->data;
    if (context)
    {
        /* Tell the context to get rid of its windows, etc. */
        [context dispose];
        
        /* Balance our CFRetain from when we created it */
        CFRelease(context);
        
        /* Done with it */
        t->data = NULL;
    }
    
    [pool drain];
}

/* Returns the CGImageRef corresponding to an image with the given name in the resource directory, transferring ownership to the caller */
static CGImageRef create_angband_image(NSString *name)
{
    CGImageRef decodedImage = NULL, result = NULL;
    
    /* Get the path to the image */
    NSBundle *bundle = [NSBundle bundleForClass:[AngbandView class]];
    NSString *path = [bundle pathForImageResource:name];
    
    /* Try using ImageIO to load it */
    if (path)
    {
        NSURL *url = [[NSURL alloc] initFileURLWithPath:path isDirectory:NO];
        if (url)
        {
            NSDictionary *options = [[NSDictionary alloc] initWithObjectsAndKeys:(id)kCFBooleanTrue, kCGImageSourceShouldCache, nil];
            CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, (CFDictionaryRef)options);
            if (source)
            {
                /* We really want the largest image, but in practice there's only going to be one */
                decodedImage = CGImageSourceCreateImageAtIndex(source, 0, (CFDictionaryRef)options);
                CFRelease(source);
            }
            [options release];
            [url release];
        }
    }
    
    /* Draw the sucker to defeat ImageIO's weird desire to cache and decode on demand. Our images aren't that big! */
    if (decodedImage)
    {
        size_t width = CGImageGetWidth(decodedImage), height = CGImageGetHeight(decodedImage);
        
        /* Compute our own bitmap info */
        CGBitmapInfo imageBitmapInfo = CGImageGetBitmapInfo(decodedImage);
        CGBitmapInfo contextBitmapInfo = kCGBitmapByteOrderDefault;
        
        switch (imageBitmapInfo & kCGBitmapAlphaInfoMask) {
            case kCGImageAlphaNone:
            case kCGImageAlphaNoneSkipLast:
            case kCGImageAlphaNoneSkipFirst:
                /* No alpha */
                contextBitmapInfo |= kCGImageAlphaNone;
                break;
            default:
                /* Some alpha, use premultiplied last which is most efficient. */
                contextBitmapInfo |= kCGImageAlphaPremultipliedLast;
                break;
        }

        // draw the source image flipped, since the view is flipped
        CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, CGImageGetBitsPerComponent(decodedImage), CGImageGetBytesPerRow(decodedImage), CGImageGetColorSpace(decodedImage), contextBitmapInfo);
        CGContextSetBlendMode(ctx, kCGBlendModeCopy);
        CGContextTranslateCTM(ctx, 0.0, height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), decodedImage);
        result = CGBitmapContextCreateImage(ctx);

        /* Done with these things */
        CFRelease(ctx);
        CGImageRelease(decodedImage);
    }
    return result;
}

/*
 * React to changes
 */
static errr Term_xtra_cocoa_react(void)
{
    /* Don't actually switch graphics until the game is running */
    if (!initialized || !game_in_progress) return (-1);

#if 0 ////
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    AngbandContext *angbandContext = Term->data;
    
    /* Handle graphics */
    ////int expected_graf_mode = (current_graphics_mode ? current_graphics_mode->grafID : GRAF_MODE_NONE);
    if (graf_mode_req != expected_graf_mode)
    {
        graphics_mode *new_mode;
		if (graf_mode_req != GRAF_MODE_NONE) {
			new_mode = get_graphics_mode(graf_mode_req);
		} else {
			new_mode = NULL;
        }
        
        /* Get rid of the old image. CGImageRelease is NULL-safe. */
        CGImageRelease(pict_image);
        pict_image = NULL;
        
        /* Try creating the image if we want one */
        if (new_mode != NULL)
        {
            NSString *img_name = [NSString stringWithCString:new_mode->file 
                                                encoding:NSMacOSRomanStringEncoding];
            pict_image = create_angband_image(img_name);

            /* If we failed to create the image, set the new desired mode to NULL */
            if (! pict_image)
                new_mode = NULL;
        }
        
        /* Record what we did */
        use_graphics = (new_mode != NULL);
        use_transparency = (new_mode != NULL);
        ANGBAND_GRAF = (new_mode ? new_mode->pref : NULL);
        current_graphics_mode = new_mode;
        
        /* Enable or disable higher picts. Note: this should be done for all terms. */
        angbandContext->terminal->higher_pict = !! use_graphics;
        
        if (pict_image && current_graphics_mode)
        {
            /* Compute the row and column count via the image height and width. */
            pict_rows = (int)(CGImageGetHeight(pict_image) / current_graphics_mode->cell_height);
            pict_cols = (int)(CGImageGetWidth(pict_image) / current_graphics_mode->cell_width);
        }
        else
        {
            pict_rows = 0;
            pict_cols = 0;
        }
        
        /* Reset visuals */
        if (initialized && game_in_progress)
        {
            reset_visuals(TRUE);
        }
    }
    
    [pool drain];

#endif ////
    
    /* Success */
    return (0);
}


/*
 * Do a "special thing"
 */
static errr Term_xtra_cocoa(int n, int v)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    AngbandContext* angbandContext = Term->data;
    
    errr result = 0;
    
    /* Analyze */
    switch (n)
    {
            /* Make a noise */
        case TERM_XTRA_NOISE:
        {
            /* Make a noise */
            NSBeep();
            
            /* Success */
            break;
        }
            
            /* Process random events */
        case TERM_XTRA_BORED:
        {
            // show or hide cocoa windows based on the subwindow flags set by the user
            AngbandUpdateWindowVisibility();

            /* Process an event */
            (void)check_events(CHECK_EVENTS_NO_WAIT);
            
            /* Success */
            break;
        }
            
            /* Process pending events */
        case TERM_XTRA_EVENT:
        {
            /* Process an event */
            (void)check_events(v);
            
            /* Success */
            break;
        }
            
            /* Flush all pending events (if any) */
        case TERM_XTRA_FLUSH:
        {
            /* Hack -- flush all events */
            while (check_events(CHECK_EVENTS_DRAIN)) /* loop */;
            
            /* Success */
            break;
        }
            
            /* Hack -- Change the "soft level" */
        case TERM_XTRA_LEVEL:
        {
            /* Here we could activate (if requested), but I don't think Angband should be telling us our window order (the user should decide that), so do nothing. */            
            break;
        }
            
            /* Clear the screen */
        case TERM_XTRA_CLEAR:
        {        
            [angbandContext lockFocus];
            [[NSColor blackColor] set];
            NSRect imageRect = {NSZeroPoint, [angbandContext imageSize]};
            NSRectFillUsingOperation(imageRect, NSCompositeCopy);
            [angbandContext unlockFocus];
            [angbandContext clearOverdrawCache];
            [angbandContext setNeedsDisplay:YES];
            /* Success */
            break;
        }
            
            /* React to changes */
        case TERM_XTRA_REACT:
        {
            /* React to changes */
            return (Term_xtra_cocoa_react());
        }
            
            /* Delay (milliseconds) */
        case TERM_XTRA_DELAY:
        {
            /* If needed */
            if (v > 0)
            {
                
                double seconds = v / 1000.;
                NSDate* date = [NSDate dateWithTimeIntervalSinceNow:seconds];
                do
                {
                    NSEvent* event;
                    do
                    {
                        event = [NSApp nextEventMatchingMask:-1 untilDate:date inMode:NSDefaultRunLoopMode dequeue:YES];
                        if (event) send_event(event);
                    } while (event);
                } while ([date timeIntervalSinceNow] >= 0);
                
            }
            
            /* Success */
            break;
        }
            
        case TERM_XTRA_FRESH:
        {
            /* No-op -- see #1669 
             * [angbandContext displayIfNeeded]; */
            break;
        }
            
        default:
            /* Oops */
            result = 1;
            break;
    }
    
    [pool drain];
    
    /* Oops */
    return result;
}

static errr Term_curs_cocoa(int x, int y)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    AngbandContext *angbandContext = Term->data;
    
    /* Get the tile */
    NSRect rect = [angbandContext rectInImageForTileAtX:x Y:y];
    
    /* We'll need to redisplay in that rect */
    NSRect redisplayRect = rect;

    /* Go to the pixel boundaries corresponding to this tile */
    rect = crack_rect(rect, AngbandScaleIdentity, push_options(x, y));
    
    /* Lock focus and draw it */
    [angbandContext lockFocus];
////half    [[NSColor yellowColor] set];
    [[NSColor blueColor] set]; ////half
    NSFrameRectWithWidth(rect, 1);
    [angbandContext unlockFocus];
    
    /* Invalidate that rect */
    [angbandContext setNeedsDisplayInBaseRect:redisplayRect];
    
    /* Success */
    [pool drain];
    return 0;
}

/*
 * Low level graphics (Assumes valid input)
 *
 * Erase "n" characters starting at (x,y)
 */
static errr Term_wipe_cocoa(int x, int y, int n)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    AngbandContext *angbandContext = Term->data;
    
    /* clear our overdraw cache for subpixel rendering */
    [angbandContext clearOverdrawCache];
    
    /* Erase the block of characters */
    NSRect rect = [angbandContext rectInImageForTileAtX:x Y:y];
    
    /* Maybe there's more than one */
    if (n > 1) rect = NSUnionRect(rect, [angbandContext rectInImageForTileAtX:x + n-1 Y:y]);
    
    /* Lock focus and clear */
    [angbandContext lockFocus];
    [[NSColor blackColor] set];
    NSRectFill(rect);
    [angbandContext unlockFocus];    
    [angbandContext setNeedsDisplayInBaseRect:rect];
    
    [pool drain];
    
    /* Success */
    return (0);
}

static void draw_image_tile(CGImageRef image, NSRect srcRect, NSRect dstRect, NSCompositingOperation op)
{
    // flip the source rect since the source image is flipped
    CGAffineTransform flip = CGAffineTransformIdentity;
    flip = CGAffineTransformTranslate(flip, 0.0, CGImageGetHeight(image));
    flip = CGAffineTransformScale(flip, 1.0, -1.0);
    CGRect flippedSourceRect = CGRectApplyAffineTransform(NSRectToCGRect(srcRect), flip);

    /* When we use high-quality resampling to draw a tile, pixels from outside the tile may bleed in, causing graphics artifacts. Work around that. */
    CGImageRef subimage = CGImageCreateWithImageInRect(image, flippedSourceRect);
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context setCompositingOperation:op];
    CGContextDrawImage([context graphicsPort], NSRectToCGRect(dstRect), subimage);
    CGImageRelease(subimage);
}

////static errr Term_pict_cocoa(int x, int y, int n, const int *ap, const wchar_t *cp, const int *tap, const wchar_t *tcp)
static errr Term_pict_cocoa(int x, int y, int n, const byte_hack *ap, const char *cp, const byte_hack *tap, const char *tcp) ////half
{

#if 0 ////
    
    /* Paranoia: Bail if we don't have a current graphics mode */
    if (! current_graphics_mode) return -1;
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    AngbandContext* angbandContext = Term->data;

    /* Indicate that we have a picture here (and hence this should not be overdrawn by Term_text_cocoa) */
    angbandContext->charOverdrawCache[y * angbandContext->cols + x] = NO_OVERDRAW;
    
    /* Lock focus */
    [angbandContext lockFocus];
    
    NSRect destinationRect = [angbandContext rectInImageForTileAtX:x Y:y];

    /* Expand the rect to every touching pixel to figure out what to redisplay */
    NSRect redisplayRect = crack_rect(destinationRect, AngbandScaleIdentity, PUSH_RIGHT | PUSH_TOP | PUSH_BOTTOM | PUSH_LEFT);
    
    /* Expand our destinationRect */
    destinationRect = crack_rect(destinationRect, AngbandScaleIdentity, push_options(x, y));
    
    /* Scan the input */
    int i;
    int graf_width = current_graphics_mode->cell_width;
    int graf_height = current_graphics_mode->cell_height;

    for (i = 0; i < n; i++)
    {
        
        int a = *ap++;
        wchar_t c = *cp++;
        
        int ta = *tap++;
        wchar_t tc = *tcp++;
        
        
        /* Graphics -- if Available and Needed */
        if (use_graphics && (a & 0x80) && (c & 0x80))
        {
            int col, row;
            int t_col, t_row;
            

            /* Primary Row and Col */
            row = ((byte)a & 0x7F) % pict_rows;
            col = ((byte)c & 0x7F) % pict_cols;
            
            NSRect sourceRect;
            sourceRect.origin.x = col * graf_width;
            sourceRect.origin.y = row * graf_height;
            sourceRect.size.width = graf_width;
            sourceRect.size.height = graf_height;
            
            /* Terrain Row and Col */
            t_row = ((byte)ta & 0x7F) % pict_rows;
            t_col = ((byte)tc & 0x7F) % pict_cols;
            
            NSRect terrainRect;
            terrainRect.origin.x = t_col * graf_width;
            terrainRect.origin.y = t_row * graf_height;
            terrainRect.size.width = graf_width;
            terrainRect.size.height = graf_height;
            
            /* Transparency effect. We really want to check current_graphics_mode->alphablend, but as of this writing that's never set, so we do something lame.  */
            //if (current_graphics_mode->alphablend)
            if (graf_width > 8 || graf_height > 8)
            {
                draw_image_tile(pict_image, terrainRect, destinationRect, NSCompositeCopy);
                draw_image_tile(pict_image, sourceRect, destinationRect, NSCompositeSourceOver); 
            }
            else
            {
                draw_image_tile(pict_image, sourceRect, destinationRect, NSCompositeCopy);
            }
        }        
    }
    
    [angbandContext unlockFocus];
    [angbandContext setNeedsDisplayInBaseRect:redisplayRect];
    
    [pool drain];

#endif ////
    
    /* Success */
    return (0);
}

/*
 * Low level graphics.  Assumes valid input.
 *
 * Draw several ("n") chars, with an attr, at a given location.
 */
////static errr Term_text_cocoa(int x, int y, int n, int a, const wchar_t *cp)
static errr Term_text_cocoa(int x, int y, int n, byte_hack a, const char *cp) ////half
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    ////half: I've simply removed the 'draw either side' code from this function
    ////half  This involved removing the two blocks below
    ////half  This probably means I can remove angbandContext->charOverdrawCache
    
    NSRect redisplayRect = NSZeroRect;
    AngbandContext* angbandContext = Term->data;
    
    ////half: Removed this block
    /* record our data in our cache */
    /*
    int start = y * angbandContext->cols + x;
    int location;
    for (location = 0; location < n; location++) {
        angbandContext->charOverdrawCache[start + location] = cp[location];
        angbandContext->attrOverdrawCache[start + location] = a;
    }
    */

    /* Focus on our layer */
    [angbandContext lockFocus];

    /* Starting pixel */
    NSRect charRect = [angbandContext rectInImageForTileAtX:x Y:y];
    
    const CGFloat tileWidth = angbandContext->tileSize.width;
    
    /* erase behind us */
    unsigned leftPushOptions = push_options(x, y);
    unsigned rightPushOptions = push_options(x + n - 1, y);
    leftPushOptions &= ~ PUSH_RIGHT;
    rightPushOptions &= ~ PUSH_LEFT;
    
    ////half: I think I added this block, but am not sure
    switch (a / MAX_COLORS) {
    case BG_BLACK:
	    [[NSColor blackColor] set];
	    break;
    case BG_SAME:
	    set_color_for_index(a % MAX_COLORS);
	    break;
    case BG_DARK:
	    set_color_for_index(TERM_SHADE);
	    break;
    }
    
    NSRect rectToClear = charRect;
    rectToClear.size.width = tileWidth * n;
    NSRectFill(crack_rect(rectToClear, AngbandScaleIdentity, leftPushOptions | rightPushOptions));
    
    NSFont *selectionFont = [[angbandContext selectionFont] screenFont];
    [selectionFont set];

    ////half: Removed this block
    /* Handle overdraws */
    /*
    const int overdraws[2] = {x-1, x+n}; //left, right
    int i;
    for (i=0; i < 2; i++) {
        int overdrawX = overdraws[i];
        
        // Nothing to overdraw if we're at an edge
        if (overdrawX >= 0 && (size_t)overdrawX < angbandContext->cols)
        {
            wchar_t previouslyDrawnVal = angbandContext->charOverdrawCache[y * angbandContext->cols + overdrawX];
            int previouslyDrawnAttr = angbandContext->attrOverdrawCache[y * angbandContext->cols + overdrawX];
            // Don't overdraw if it's not text
            if (previouslyDrawnVal != NO_OVERDRAW)
            {
                NSRect overdrawRect = [angbandContext rectInImageForTileAtX:overdrawX Y:y];
                NSRect expandedRect = crack_rect(overdrawRect, AngbandScaleIdentity, push_options(overdrawX, y));
                
                // Make sure we redisplay it
                switch (previouslyDrawnAttr / MAX_COLORS) {
                    case BG_BLACK:
                        [[NSColor blackColor] set];
                        break;
                    case BG_SAME:
                        set_color_for_index(previouslyDrawnAttr % MAX_COLORS);
                        break;
                    case BG_DARK:
                        set_color_for_index(TERM_SHADE);
                        break;
                }
                NSRectFill(expandedRect);
                redisplayRect = NSUnionRect(redisplayRect, expandedRect);
                
                // Redraw text if we have any
                if (previouslyDrawnVal != 0)
                {
                    byte color = angbandContext->attrOverdrawCache[y * angbandContext->cols + overdrawX];
                    
                    set_color_for_index(color);
                    [angbandContext drawWChar:previouslyDrawnVal inRect:overdrawRect];
                }
            }
        }
    }
    */
    
    
    /* Set the color */
    set_color_for_index(a % MAX_COLORS);
    
    /* Draw each */
    NSRect rectToDraw = charRect;
    int i;
    for (i=0; i < n; i++) {
        [angbandContext drawWChar:cp[i] inRect:rectToDraw];
        rectToDraw.origin.x += tileWidth;
    }
    
    // Invalidate what we just drew
    NSRect drawnRect = charRect;
    drawnRect.size.width = tileWidth * n;
    redisplayRect = NSUnionRect(redisplayRect, drawnRect);
    
    [angbandContext unlockFocus];    
    [angbandContext setNeedsDisplayInBaseRect:redisplayRect];
    
    [pool drain];
    
    /* Success */
    return (0);
}

/* From the Linux mbstowcs(3) man page:
 *   If dest is NULL, n is ignored, and the conversion  proceeds  as  above,
 *   except  that  the converted wide characters are not written out to mem???
 *   ory, and that no length limit exists.
 */
static size_t Term_mbcs_cocoa(wchar_t *dest, const char *src, int n)
{
    int i;
    int count = 0;

    /* Unicode code point to UTF-8
     *  0x0000-0x007f:   0xxxxxxx
     *  0x0080-0x07ff:   110xxxxx 10xxxxxx
     *  0x0800-0xffff:   1110xxxx 10xxxxxx 10xxxxxx
     * 0x10000-0x1fffff: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
     * Note that UTF-16 limits Unicode to 0x10ffff. This code is not
     * endian-agnostic.
     */
    for (i = 0; i < n || dest == NULL; i++) {
        if ((src[i] & 0x80) == 0) {
            if (dest != NULL) dest[count] = src[i];
            if (src[i] == 0) break;
        } else if ((src[i] & 0xe0) == 0xc0) {
            if (dest != NULL) dest[count] = 
                            (((unsigned char)src[i] & 0x1f) << 6)| 
                            ((unsigned char)src[i+1] & 0x3f);
            i++;
        } else if ((src[i] & 0xf0) == 0xe0) {
            if (dest != NULL) dest[count] = 
                            (((unsigned char)src[i] & 0x0f) << 12) | 
                            (((unsigned char)src[i+1] & 0x3f) << 6) |
                            ((unsigned char)src[i+2] & 0x3f);
            i += 2;
        } else if ((src[i] & 0xf8) == 0xf0) {
            if (dest != NULL) dest[count] = 
                            (((unsigned char)src[i] & 0x0f) << 18) | 
                            (((unsigned char)src[i+1] & 0x3f) << 12) |
                            (((unsigned char)src[i+2] & 0x3f) << 6) |
                            ((unsigned char)src[i+3] & 0x3f);
            i += 3;
        } else {
            /* Found an invalid multibyte sequence */
            return (size_t)-1;
        }
        count++;
    }
    return count;
}

/* Post a nonsense event so that our event loop wakes up */
static void wakeup_event_loop(void)
{
    /* Big hack - send a nonsense event to make us update */
    NSEvent *event = [NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:NULL subtype:AngbandEventWakeup data1:0 data2:0];
    [NSApp postEvent:event atStart:NO];
}


/*
 * Create and initialize window number "i"
 */
static term *term_data_link(int i)
{
    NSArray *terminalDefaults = [[NSUserDefaults standardUserDefaults] valueForKey: AngbandTerminalsDefaultsKey];
    NSInteger rows = 24;
    NSInteger columns = 80;

    if( i < (int)[terminalDefaults count] )
    {
        NSDictionary *term = [terminalDefaults objectAtIndex: i];
        rows = [[term valueForKey: AngbandTerminalRowsDefaultsKey] integerValue];
        columns = [[term valueForKey: AngbandTerminalColumnsDefaultsKey] integerValue];
    }

    /* Allocate */
    term *newterm = ZNEW(term);

    /* Initialize the term */
    term_init(newterm, columns, rows, 256 /* keypresses, for some reason? */);
    
    /* Differentiate between BS/^h, Tab/^i, etc. */
    ////newterm->complex_input = TRUE;

    /* Use a "software" cursor */
    newterm->soft_cursor = TRUE;
    
    /* Erase with "white space" */
    newterm->attr_blank = TERM_WHITE;
    newterm->char_blank = ' ';
    
    /* Prepare the init/nuke hooks */
    newterm->init_hook = Term_init_cocoa;
    newterm->nuke_hook = Term_nuke_cocoa;
    
    /* Prepare the function hooks */
    newterm->xtra_hook = Term_xtra_cocoa;
    newterm->wipe_hook = Term_wipe_cocoa;
    newterm->curs_hook = Term_curs_cocoa;
    newterm->text_hook = Term_text_cocoa;
    newterm->pict_hook = Term_pict_cocoa;
    ////newterm->mbcs_hook = Term_mbcs_cocoa;
    
    /* Global pointer */
    angband_term[i] = newterm;
    
    return newterm;
}

/*
 * Load preferences from preferences file for current host+current user+
 * current application.
 */
static void load_prefs()
{
    NSUserDefaults *defs = [NSUserDefaults angbandDefaults];
    
    /* Make some default defaults */
    NSMutableArray *defaultTerms = [[NSMutableArray alloc] init];

    // the following default rows/cols were determined experimentally by first finding the ideal window/font size combinations.
    // but because of awful temporal coupling in Term_init_cocoa(), it's impossible to set up the defaults there, so we do it
    // this way.
    for( NSUInteger i = 0; i < ANGBAND_TERM_MAX; i++ )
    {
		int columns, rows;
		BOOL visible = YES;

        ////half: changed this block of code that shows window sizes
		switch( i )
		{
			case WINDOW_MAIN:
				columns = 104;
				rows = 35;
				break;
			case WINDOW_INVEN:
				columns = 79;
				rows = 25;
				break;
			case WINDOW_EQUIP:
				columns = 79;
				rows = 16;
				break;
			case WINDOW_COMBAT_ROLLS:
				columns = 79;
				rows = 20;
				break;
			case WINDOW_MONSTER:
				columns = 122;
				rows = 10;
				break;
			default:
				columns = 80;
				rows = 24;
				visible = NO;
				break;
		}

		NSDictionary *standardTerm = [NSDictionary dictionaryWithObjectsAndKeys:
									  [NSNumber numberWithInt: rows], AngbandTerminalRowsDefaultsKey,
									  [NSNumber numberWithInt: columns], AngbandTerminalColumnsDefaultsKey,
									  [NSNumber numberWithBool: visible], AngbandTerminalVisibleDefaultsKey,
									  nil];
        [defaultTerms addObject: standardTerm];
    }

    NSDictionary *defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
                              ////half @"Menlo", @"FontName",
                              @"Monaco", @"FontName", ////half
                              [NSNumber numberWithFloat:12.f], @"FontSize",
                              [NSNumber numberWithInt:60], @"FramesPerSecond",
                              [NSNumber numberWithBool:YES], @"AllowSound",
                              [NSNumber numberWithInt:GRAPHICS_NONE], @"GraphicsID",
                              defaultTerms, AngbandTerminalsDefaultsKey,
                              nil];
    [defs registerDefaults:defaults];
    [defaults release];
    [defaultTerms release];
    
    /* preferred graphics mode */
    graf_mode_req = [defs integerForKey:@"GraphicsID"];
    
    /* use sounds */
    allow_sounds = [defs boolForKey:@"AllowSound"];
    
    /* fps */
    frames_per_second = [[NSUserDefaults angbandDefaults] integerForKey:@"FramesPerSecond"];
    
    /* font */
    default_font = [[NSFont fontWithName:[defs valueForKey:@"FontName-0"] size:[defs floatForKey:@"FontSize-0"]] retain];
////half    if (! default_font) default_font = [[NSFont fontWithName:@"Menlo" size:13.] retain];
    if (! default_font) default_font = [[NSFont fontWithName:@"Monaco" size:12.] retain]; ////half
}

/* Arbitary limit on number of possible samples per event */
#define MAX_SAMPLES            16

/* Struct representing all data for a set of event samples */
typedef struct
{
	int num;        /* Number of available samples for this event */
	NSSound *sound[MAX_SAMPLES];
} sound_sample_list;

/* Array of event sound structs */
static sound_sample_list samples[MSG_MAX];


/*
 * Load sound effects based on sound.cfg within the xtra/sound directory;
 * bridge to Cocoa to use NSSound for simple loading and playback, avoiding
 * I/O latency by cacheing all sounds at the start.  Inherits full sound
 * format support from Quicktime base/plugins.
 * pelpel favoured a plist-based parser for the future but .cfg support
 * improves cross-platform compatibility.
 */
static void load_sounds(void)
{

#if 0 ////
    
	char path[2048];
	char buffer[2048];
	ang_file *fff;
    
	/* Build the "sound" path */
	path_build(path, sizeof(path), ANGBAND_DIR_XTRA, "sound");
	ANGBAND_DIR_XTRA_SOUND = string_make(path);
    
	/* Find and open the config file */
	path_build(path, sizeof(path), ANGBAND_DIR_XTRA_SOUND, "sound.cfg");
	fff = file_open(path, MODE_READ, -1);
    
	/* Handle errors */
	if (!fff)
	{
		NSLog(@"The sound configuration file could not be opened.");
		return;
	}
	
	/* Instantiate an autorelease pool for use by NSSound */
	NSAutoreleasePool *autorelease_pool;
	autorelease_pool = [[NSAutoreleasePool alloc] init];
    
    /* Use a dictionary to unique sounds, so we can share NSSounds across multiple events */
    NSMutableDictionary *sound_dict = [NSMutableDictionary dictionary];
    
	/*
	 * This loop may take a while depending on the count and size of samples
	 * to load.
	 */
    
	/* Parse the file */
	/* Lines are always of the form "name = sample [sample ...]" */
	while (file_getl(fff, buffer, sizeof(buffer)))
	{
		char *msg_name;
		char *cfg_sample_list;
		char *search;
		char *cur_token;
		char *next_token;
		int event;
        
		/* Skip anything not beginning with an alphabetic character */
		if (!buffer[0] || !isalpha((unsigned char)buffer[0])) continue;
        
		/* Split the line into two: message name, and the rest */
		search = strchr(buffer, ' ');
		cfg_sample_list = strchr(search + 1, ' ');
		if (!search) continue;
		if (!cfg_sample_list) continue;
        
		/* Set the message name, and terminate at first space */
		msg_name = buffer;
		search[0] = '\0';
        
		/* Make sure this is a valid event name */
		event = message_lookup_by_sound_name(msg_name);
		if (event < 0) continue;
        
		/* Advance the sample list pointer so it's at the beginning of text */
		cfg_sample_list++;
		if (!cfg_sample_list[0]) continue;
        
		/* Terminate the current token */
		cur_token = cfg_sample_list;
		search = strchr(cur_token, ' ');
		if (search)
		{
			search[0] = '\0';
			next_token = search + 1;
		}
		else
		{
			next_token = NULL;
		}
        
		/*
		 * Now we find all the sample names and add them one by one
		 */
		while (cur_token)
		{
			int num = samples[event].num;
            
			/* Don't allow too many samples */
			if (num >= MAX_SAMPLES) break;
            
            NSString *token_string = [NSString stringWithUTF8String:cur_token];
            NSSound *sound = [sound_dict objectForKey:token_string];
            
            if (! sound)
            {
                /* We have to load the sound. Build the path to the sample */
                path_build(path, sizeof(path), ANGBAND_DIR_XTRA_SOUND, cur_token);
                if (file_exists(path))
                {
                    
                    /* Load the sound into memory */
                    sound = [[[NSSound alloc] initWithContentsOfFile:[NSString stringWithUTF8String:path] byReference:YES] autorelease];
                    if (sound) [sound_dict setObject:sound forKey:token_string];
                }
            }
            
            /* Store it if we loaded it */
            if (sound)
            {
                samples[event].sound[num] = [sound retain];
                
                /* Imcrement the sample count */
                samples[event].num++;
            }
            
            
			/* Figure out next token */
			cur_token = next_token;
			if (next_token)
			{
				/* Try to find a space */
				search = strchr(cur_token, ' ');
                
				/* If we can find one, terminate, and set new "next" */
				if (search)
				{
					search[0] = '\0';
					next_token = search + 1;
				}
				else
				{
					/* Otherwise prevent infinite looping */
					next_token = NULL;
				}
			}
		}
	}
    
	/* Release the autorelease pool */
	[autorelease_pool release];
    
	/* Close the file */
	file_close(fff);

#endif ////
    
}

/*
 * Play sound effects asynchronously.  Select a sound from any available
 * for the required event, and bridge to Cocoa to play it.
 */
static void play_sound(int event)
{    
    /* Maybe block it */
    if (! allow_sounds) return;
    
	/* Paranoia */
	if (event < 0 || event >= MSG_MAX) return;
    
    /* Load sounds just-in-time (once) */
    static BOOL loaded = NO;
    if (! loaded)
    {
        loaded = YES;
        load_sounds();
    }
    
    /* Check there are samples for this event */
    if (!samples[event].num) return;
    
    /* Instantiate an autorelease pool for use by NSSound */
    NSAutoreleasePool *autorelease_pool;
    autorelease_pool = [[NSAutoreleasePool alloc] init];
    
    /* Choose a random event */
////    int s = randint0(samples[event].num);
    int s = rand_int(samples[event].num); ////
    
    /* Stop the sound if it's currently playing */
    if ([samples[event].sound[s] isPlaying])
        [samples[event].sound[s] stop];
    
    /* Play the sound */
    [samples[event].sound[s] play];
    
    /* Release the autorelease pool */
    [autorelease_pool drain];
}

/*
 * 
 */
static void init_windows(void)
{
    /* Create the main window */
    term *primary = term_data_link(0);
    
    /* Prepare to create any additional windows */
    int i;
    for (i=1; i < ANGBAND_TERM_MAX; i++) {
        term_data_link(i);
    }
    
    /* Activate the primary term */
    Term_activate(primary);
}


/*
 *    Run the event loop and return a gameplay status to init_angband
 */

#if 0 ////

static errr get_cmd_init(void)
{     
    if (cmd.command == CMD_NULL)
    {
        /* Prompt the user */ 
        prt("[Choose 'New' or 'Open' from the 'File' menu]", 23, 17);
        Term_fresh();
        
        while (cmd.command == CMD_NULL) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSEvent *event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event) [NSApp sendEvent:event];
            [pool drain];        
        }
    }
    
    /* Push the command to the game. */
    cmd_insert_s(&cmd);
    
    return 0; 
} 


/* Return a command */
static errr cocoa_get_cmd(cmd_context context, bool wait)
{
    if (context == CMD_INIT) 
        return get_cmd_init();
    else 
        return textui_get_cmd(context, wait);
}

#endif ////

/* Return the directory into which we put data (save and config) */
static NSString *get_data_directory(void)
{
    ////half return [@"~/Documents/Angband/" stringByExpandingTildeInPath];
    
    return [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"../../../lib/"]; ////half
}


//// Sil-y: begin inserted block
//// Sil-y: the code of this function open_game() is simply copied from
////        openGame, as I couldn't work out how to call openGame from within beginGame

static void open_game(void)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    BOOL selectedSomething = NO;
    int panelResult;
    NSString* startingDirectory;
    
    /* Get where we think the save files are */
    startingDirectory = [get_data_directory() stringByAppendingPathComponent:@"/save/"];
    
    /* Get what we think the default save file name is. Deafult to the empty string. */
    NSString *savefileName = [[NSUserDefaults angbandDefaults] stringForKey:@"SaveFile"];
    if (! savefileName) savefileName = @"";
    
    /* Set up an open panel */
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setResolvesAliases:YES];
    [panel setAllowsMultipleSelection:YES];
    [panel setTreatsFilePackagesAsDirectories:YES];
    
    /* Run it */
    panelResult = [panel runModalForDirectory:startingDirectory file:savefileName types:nil];
    if (panelResult == NSOKButton)
    {
        NSArray* filenames = [panel filenames];
        if ([filenames count] > 0)
        {
            selectedSomething = [[filenames objectAtIndex:0] getFileSystemRepresentation:savefile maxLength:sizeof savefile];
        }
    }
    
    if (selectedSomething)
    {
        
        /* Remember this so we can select it by default next time */
        record_current_savefile();
        
        /* Game is in progress */
        game_in_progress = TRUE;
        
        new_game = FALSE;
    }
    
    [pool drain];
}

/*
 * Open the tutorial savefile, stored in apex/
 */
static void open_tutorial(void)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    NSString* savefileName;
    
    /* Get the location of the tutorial savefile */
    savefileName = [get_data_directory() stringByAppendingPathComponent:@"/apex/tutorial"];
    
    /* Put it in savefile */
    [savefileName getFileSystemRepresentation:savefile maxLength:sizeof savefile];
    
    /* Game is in progress */
    game_in_progress = TRUE;
    
    new_game = FALSE;
    
    [pool drain];
}

//// Sil-y: end inserted block


/*
 * Handle the "open_when_ready" flag
 */
static void handle_open_when_ready(void)
{
    /* Check the flag XXX XXX XXX make a function for this */
    if (open_when_ready && initialized && !game_in_progress)
    {
        /* Forget */
        open_when_ready = FALSE;
        
        /* Game is in progress */
        game_in_progress = TRUE;

        /* Wait for a keypress */
        ////pause_line(Term);
        ////half pause_line(23); ////
    }
}


/*
 * Handle quit_when_ready, by Peter Ammon,
 * slightly modified to check inkey_flag.
 */
static void quit_calmly(void)
{
    /* Quit immediately if game's not started */
    if (!game_in_progress || !character_generated) quit(NULL);
    
    /* Save the game and Quit (if it's safe) */
    if (inkey_flag)
    {
        /* Hack -- Forget messages */
        msg_flag = FALSE;
        
        /* Save the game */
        ////do_cmd_save_game(FALSE, 0);
        do_cmd_save_game(); ////
        record_current_savefile();
        
        
        /* Quit */
        quit(NULL);
    }
    
    /* Wait until inkey_flag is set */
}



/* returns YES if we contain an AngbandView (and hence should direct our events to Angband) */
static BOOL contains_angband_view(NSView *view)
{
    if ([view isKindOfClass:[AngbandView class]]) return YES;
    for (NSView *subview in [view subviews]) {
        if (contains_angband_view(subview)) return YES;
    }
    return NO;
}


/**
 * Queue mouse presses if they occur in the map section of the main window.
 */
static void AngbandHandleEventMouseDown( NSEvent *event )
{
	AngbandContext *angbandContext = [[[event window] contentView] angbandContext];
	AngbandContext *mainAngbandContext = angband_term[0]->data;

	if (mainAngbandContext->primaryWindow && [[event window] windowNumber] == [mainAngbandContext->primaryWindow windowNumber])
	{
		int cols, rows, x, y;
		Term_get_size(&cols, &rows);
		NSSize tileSize = angbandContext->tileSize;
		NSSize border = angbandContext->borderSize;
		NSPoint windowPoint = [event locationInWindow];

		// adjust for border; add border height because window origin is at bottom
		windowPoint = NSMakePoint( windowPoint.x - border.width, windowPoint.y + border.height );

		NSPoint p = [[[event window] contentView] convertPoint: windowPoint fromView: nil];
		x = floor( p.x / tileSize.width );
		y = floor( p.y / tileSize.height );

		// being safe about this, since xcode doesn't seem to like the bool_hack stuff
		BOOL displayingMapInterface = ((int)inkey_flag != 0);

		// Sidebar plus border == thirteen characters; top row is reserved.
		// Coordinates run from (0,0) to (cols-1, rows-1).
		BOOL mouseInMapSection = (x > 13 && x <= cols - 1 && y > 0  && y <= rows - 2);

		// if we are displaying a menu, allow clicks anywhere; if we are displaying the main
		// game interface, only allow clicks in the map section
		if (!displayingMapInterface || (displayingMapInterface && mouseInMapSection))
		{
			// [event buttonNumber] will return 0 for left click, 1 for right click, but this is safer
			int button = ([event type] == NSLeftMouseDown) ? 1 : 2;

#ifdef KC_MOD_ALT
			NSUInteger eventModifiers = [event modifierFlags];
			byte angbandModifiers = 0;
			angbandModifiers |= (eventModifiers & NSShiftKeyMask) ? KC_MOD_SHIFT : 0;
			angbandModifiers |= (eventModifiers & NSControlKeyMask) ? KC_MOD_CONTROL : 0;
			angbandModifiers |= (eventModifiers & NSAlternateKeyMask) ? KC_MOD_ALT : 0;
			button |= (angbandModifiers & 0x0F) << 4; // encode modifiers in the button number (see Term_mousepress())
#endif

////half			Term_mousepress(x, y, button);
		}
	}

	/* Pass click through to permit focus change, resize, etc. */
	[NSApp sendEvent:event];
}



/* Encodes an NSEvent Angband-style, or forwards it along.  Returns YES if the event was sent to Angband, NO if Cocoa (or nothing) handled it */
static BOOL send_event(NSEvent *event)
{

    /* If the receiving window is not an Angband window, then do nothing */
    if (! contains_angband_view([[event window] contentView]))
    {
        [NSApp sendEvent:event];
        return NO;
    }

    /* Analyze the event */
    switch ([event type])
    {
        case NSKeyDown:
        {
            /* Try performing a key equivalent */
            if ([[NSApp mainMenu] performKeyEquivalent:event]) break;
            
            unsigned modifiers = [event modifierFlags];
            
            /* Send all NSCommandKeyMasks through */
            if (modifiers & NSCommandKeyMask)
            {
                [NSApp sendEvent:event];
                break;
            }
            
//// myshkin            if (! [[event characters] length]) break;
            
            /* Extract some modifiers and the keycode */
            int mc = !! (modifiers & NSControlKeyMask);
            int ms = !! (modifiers & NSShiftKeyMask);
            int mo = !! (modifiers & NSAlternateKeyMask);
            int mx = !! (modifiers & NSCommandKeyMask);
            int kp = !! (modifiers & NSNumericPadKeyMask);
            
            
#if 0 //// myshkin

            /* Get the Angband char corresponding to this unichar */
            unichar c = [[event characters] characterAtIndex:0];
            //// keycode_t ch;
            //// myshkin char ch = (char)c; ////

            switch (c) {
                /* Note that NSNumericPadKeyMask is set if any of the arrow
                 * keys are pressed. We don't want KC_MOD_KEYPAD set for
                 * those. See #1662 for more details. */
                case NSUpArrowFunctionKey: ch = ARROW_UP; kp = 0; break;
                case NSDownArrowFunctionKey: ch = ARROW_DOWN; kp = 0; break;
                case NSLeftArrowFunctionKey: ch = ARROW_LEFT; kp = 0; break;
                case NSRightArrowFunctionKey: ch = ARROW_RIGHT; kp = 0; break;
                case NSF1FunctionKey: ch = KC_F1; break;
                case NSF2FunctionKey: ch = KC_F2; break;
                case NSF3FunctionKey: ch = KC_F3; break;
                case NSF4FunctionKey: ch = KC_F4; break;
                case NSF5FunctionKey: ch = KC_F5; break;
                case NSF6FunctionKey: ch = KC_F6; break;
                case NSF7FunctionKey: ch = KC_F7; break;
                case NSF8FunctionKey: ch = KC_F8; break;
                case NSF9FunctionKey: ch = KC_F9; break;
                case NSF10FunctionKey: ch = KC_F10; break;
                case NSF11FunctionKey: ch = KC_F11; break;
                case NSF12FunctionKey: ch = KC_F12; break;
                case NSF13FunctionKey: ch = KC_F13; break;
                case NSF14FunctionKey: ch = KC_F14; break;
                case NSF15FunctionKey: ch = KC_F15; break;
                case NSHelpFunctionKey: ch = KC_HELP; break;
                case NSHomeFunctionKey: ch = KC_HOME; break;
                case NSPageUpFunctionKey: ch = KC_PGUP; break;
                case NSPageDownFunctionKey: ch = KC_PGDOWN; break;
                case NSBeginFunctionKey: ch = KC_BEGIN; break;
                case NSEndFunctionKey: ch = KC_END; break;
                case NSInsertFunctionKey: ch = KC_INSERT; break;
                case NSDeleteFunctionKey: ch = KC_DELETE; break;
                case NSPauseFunctionKey: ch = KC_PAUSE; break;
                case NSBreakFunctionKey: ch = KC_BREAK; break;
                    
                default:
                    if (c <= 0x7F)
                        ch = (char)c;
                    else
                        ch = '\0';
                    break;
            }
            
            /* override special keys */
            switch([event keyCode]) {
                case kVK_Return: ch = KC_ENTER; break;
                case kVK_Escape: ch = ESCAPE; break;
                case kVK_Tab: ch = KC_TAB; break;
                case kVK_Delete: ch = KC_BACKSPACE; break;
                case kVK_ANSI_KeypadEnter: ch = KC_ENTER; kp = TRUE; break;
            }
            
            /* Hide the mouse pointer */
            [NSCursor setHiddenUntilMouseMoves:YES];
            
            /* Enqueue it */
            if (ch != '\0')
            {
                
                /* Enqueue the keypress */
#ifdef KC_MOD_ALT
                byte mods = 0;
                if (mo) mods |= KC_MOD_ALT;
                if (mx) mods |= KC_MOD_META;
                if (mc && MODS_INCLUDE_CONTROL(ch)) mods |= KC_MOD_CONTROL;
                if (ms && MODS_INCLUDE_SHIFT(ch)) mods |= KC_MOD_SHIFT;
                if (kp) mods |= KC_MOD_KEYPAD;
                Term_keypress(ch, mods);
#else
                Term_keypress(ch);
#endif
            }

#endif //// myshkin
                   
            //// begin myshkin block
            int kc = [event keyCode];
            
            /* Hide the mouse pointer */
            [NSCursor setHiddenUntilMouseMoves:YES];

            /* Some combining characters will have length 0, e.g.
               option-E produces a COMBINING ACUTE ACCENT event. */
            if ([[event characters] length])
            {
                /* Get the Angband char corresponding to this unichar */
                unichar c = [[event characters] characterAtIndex:0];
                    
                /* handle special keys */
                switch(kc)
                {
                    case kVK_Return: c = '\r'; break;
                    case kVK_Escape: c = ESCAPE; break;
                    case kVK_Delete: c = '\010'; break;

                    /* Strip the keypad flag for arrow keys. */
                    case kVK_LeftArrow: case kVK_RightArrow:
                    case kVK_DownArrow: case kVK_UpArrow:
                        kp = FALSE;
                        break;
                }
                    
                /* Normal keys with at most control and shift modifiers
                   Note that e.g. control-shift-f should get converted
                   to macro trigger, unlike control-f */
                if (c <= 0x7F && !mo && !mx && !kp && !(c <= 0x20 && ms))
                {
                    /* Enqueue the keypress */
                    Term_keypress(c);
                    break;
                }
            }

            /* Enqueue these keys via macro trigger;
               compare main-win.c:AngbandWndProc() */

            /* Begin the macro trigger */
            Term_keypress(31);
            
            /* Send modifiers (but not keypad flag) */
            if (mc) Term_keypress('C');
            if (ms) Term_keypress('S');
            if (mo) Term_keypress('O');
            if (mx) Term_keypress('X');
            
            /* Introduce the key code */
            Term_keypress('x');
            
            /* Encode the key code */
            Term_keypress(hexsym[kc/16]);
            Term_keypress(hexsym[kc%16]);
            
            /* End the macro trigger */
            Term_keypress(13);

            //// end myshkin block

            
            break;
        }
            
        case NSLeftMouseDown:
		case NSRightMouseDown:
			AngbandHandleEventMouseDown(event);
            break;

        case NSApplicationDefined:
        {
            if ([event subtype] == AngbandEventWakeup)
            {
                return YES;
            }
            break;
        }
            
        default:
            [NSApp sendEvent:event];
            return YES;
    }
    return YES;
}

/*
 * Check for Events, return TRUE if we process any
 */
static BOOL check_events(int wait)
{ 
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    /* Handles the quit_when_ready flag */
    if (quit_when_ready) quit_calmly();
    
    NSDate* endDate;
    if (wait == CHECK_EVENTS_WAIT) endDate = [NSDate distantFuture];
    else endDate = [NSDate distantPast];
    
    NSEvent* event;
    for (;;) {
        if (quit_when_ready)
        {
            /* send escape events until we quit */
////            Term_keypress(0x1B, 0);
            Term_keypress(0x1B); ////
            [pool drain];
            return false;
        }
        else {
            event = [NSApp nextEventMatchingMask:-1 untilDate:endDate inMode:NSDefaultRunLoopMode dequeue:YES];

			static BOOL periodicStarted = NO;

			////half if (OPT(animate_flicker) && !periodicStarted) {
			if (!periodicStarted) { ////
				[NSEvent startPeriodicEventsAfterDelay: 0.0 withPeriod: 0.2];
				periodicStarted = YES;
			}
			////half else if (!OPT(animate_flicker) && periodicStarted) {
			else if (FALSE && periodicStarted) { ////
				[NSEvent stopPeriodicEvents];
				periodicStarted = NO;
			}

			////half if (OPT(animate_flicker) && wait && periodicStarted && [event type] == NSPeriodic)
			////half idle_update();

            if (! event)
            {
                [pool drain];
                return FALSE;
            }
            if (send_event(event)) break;
        }
    }
    
    [pool drain];
    
    /* Something happened */
    return YES;
    
}

/*
 * Hook to tell the user something important
 */
static void hook_plog(const char * str)
{
    if (str)
    {
        NSString *string = [NSString stringWithCString:str encoding:NSMacOSRomanStringEncoding];
        NSRunAlertPanel(@"Danger Will Robinson", @"%@", @"OK", nil, nil, string);
    }
}


/*
 * Hook to tell the user something, and then quit
 */
static void hook_quit(const char * str)
{
    plog(str);
    exit(0);
}

#if 0 ////

/* Set HFS file type and creator codes on a path */
static void cocoa_file_open_hook(const char *path, file_type ftype)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *pathString = [NSString stringWithUTF8String:path];
    if (pathString)
    {   
        u32b mac_type = 'TEXT';
        if (ftype == FTYPE_RAW)
            mac_type = 'DATA';
        else if (ftype == FTYPE_SAVE)
            mac_type = 'SAVE';
        
        NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:mac_type], NSFileHFSTypeCode, [NSNumber numberWithUnsignedLong:SIL_CREATOR], NSFileHFSCreatorCode, nil];
        [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:pathString error:NULL];
    }
    [pool drain];
}


/* A platform-native file save dialogue box, e.g. for saving character dumps */
static bool cocoa_get_file(const char *suggested_name, char *path, size_t len)
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *directory = [NSString stringWithCString:ANGBAND_DIR_USER encoding:NSASCIIStringEncoding];
    NSString *filename = [NSString stringWithCString:suggested_name encoding:NSASCIIStringEncoding];

    if ([panel runModalForDirectory:directory file:filename] == NSOKButton) {
        const char *p = [[[panel URL] path] UTF8String];
        my_strcpy(path, p, len);
        return TRUE;
    }

    return FALSE;
}

#endif ////

//// Sil-y: begin inserted block

u32b _fcreator;
u32b _ftype;

/*
 * (Carbon) [via path_to_spec]
 * Set creator and filetype of a file specified by POSIX-style pathname.
 * Returns 0 on success, -1 in case of errors.
 */
extern void fsetfileinfo(cptr pathname, u32b fcreator, u32b ftype)
{
    //OSErr err;
    //FSSpec spec;
    //FInfo info;
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *pathString = [NSString stringWithUTF8String:pathname];
    if (pathString)
    {
        NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:ftype], NSFileHFSTypeCode, [NSNumber numberWithUnsignedLong:SIL_CREATOR], NSFileHFSCreatorCode, nil];
        [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:pathString error:NULL];
    }
    [pool drain];
	/* Convert pathname to FSSpec */
	//if (path_to_spec(pathname, &spec) != noErr) return;
    
	/* Obtain current finder info of the file */
	//if (FSpGetFInfo(&spec, &info) != noErr) return;
    
	/* Overwrite creator and type */
	//info.fdCreator = fcreator;
	//info.fdType = ftype;
	//err = FSpSetFInfo(&spec, &info);
    
	/* Done */
	return;
}

//// Sil-y: end inserted block

/*** Main program ***/

@interface AngbandAppDelegate : NSObject {
    IBOutlet NSMenu *terminalsMenu;
    NSMenu *_commandMenu;
    NSDictionary *_commandMenuTagMap;
}

@property (nonatomic, retain) IBOutlet NSMenu *commandMenu;
@property (nonatomic, retain) NSDictionary *commandMenuTagMap;

- (IBAction)newGame:sender;
- (IBAction)editFont:sender;
- (IBAction)openGame:sender;

- (IBAction)selectWindow: (id)sender;

@end

@implementation AngbandAppDelegate

@synthesize commandMenu=_commandMenu;
@synthesize commandMenuTagMap=_commandMenuTagMap;

- (IBAction)newGame:sender
{
    /* Game is in progress */
    game_in_progress = TRUE;
    
    Term_keypress(ESCAPE); //// half: needed to break out of the text-based start menu
    
    ////cmd.command = CMD_NEWGAME;
}

- (IBAction)editFont:sender
{
    NSFontPanel *panel = [NSFontPanel sharedFontPanel];
    NSFont *termFont = default_font;

    int i;
    for (i=0; i < ANGBAND_TERM_MAX; i++) {
        if ([(id)angband_term[i]->data isMainWindow]) {
            termFont = [(id)angband_term[i]->data selectionFont];
            break;
        }
    }
    
    [panel setPanelFont:termFont isMultiple:NO];
    [panel orderFront:self];
}

- (void)changeFont:(id)sender
{
    int mainTerm;
    for (mainTerm=0; mainTerm < ANGBAND_TERM_MAX; mainTerm++) {
        if ([(id)angband_term[mainTerm]->data isMainWindow]) {
            break;
        }
    }

    /* Bug #1709: Only change font for angband windows */
    if (mainTerm == ANGBAND_TERM_MAX) return;
    
    NSFont *oldFont = default_font;
    NSFont *newFont = [sender convertFont:oldFont];
    if (! newFont) return; //paranoia
    
    /* Store as the default font if we changed the first term */
    if (mainTerm == 0) {
        [newFont retain];
        [default_font release];
        default_font = newFont;
    }
    
    /* Record it in the preferences */
    NSUserDefaults *defs = [NSUserDefaults angbandDefaults];
    [defs setValue:[newFont fontName] 
        forKey:[NSString stringWithFormat:@"FontName-%d", mainTerm]];
    [defs setFloat:[newFont pointSize]
        forKey:[NSString stringWithFormat:@"FontSize-%d", mainTerm]];
    [defs synchronize];
    
    NSDisableScreenUpdates();
    
    /* Update window */
    AngbandContext *angbandContext = angband_term[mainTerm]->data;
    [(id)angbandContext setSelectionFont:newFont adjustTerminal: YES];
    
    NSEnableScreenUpdates();
}

- (IBAction)openGame:sender
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    BOOL selectedSomething = NO;
    int panelResult;
    NSString* startingDirectory;
    
    /* Get where we think the save files are */
    startingDirectory = [get_data_directory() stringByAppendingPathComponent:@"/save/"];
    
    /* Get what we think the default save file name is. Deafult to the empty string. */
    NSString *savefileName = [[NSUserDefaults angbandDefaults] stringForKey:@"SaveFile"];
    if (! savefileName) savefileName = @"";
    
    /* Set up an open panel */
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setResolvesAliases:YES];
    [panel setAllowsMultipleSelection:YES];
    [panel setTreatsFilePackagesAsDirectories:YES];
    
    /* Run it */
    panelResult = [panel runModalForDirectory:startingDirectory file:savefileName types:nil];
    if (panelResult == NSOKButton)
    {
        NSArray* filenames = [panel filenames];
        if ([filenames count] > 0)
        {
            selectedSomething = [[filenames objectAtIndex:0] getFileSystemRepresentation:savefile maxLength:sizeof savefile];
        }
    }
    
    if (selectedSomething)
    {
        
        /* Remember this so we can select it by default next time */
        record_current_savefile();
        
        /* Game is in progress */
        game_in_progress = TRUE;
        ////cmd.command = CMD_LOADFILE;
        
        Term_keypress(ESCAPE); //// half: needed to break out of the text-based start menu

    }

    [pool drain];
}

- (IBAction)saveGame:sender
{
    /* Hack -- Forget messages */
    msg_flag = FALSE;
    
    /* Save the game */
    ////do_cmd_save_game(FALSE, 0);
    do_cmd_save_game(); ////
    
    /* Record the current save file so we can select it by default next time. It's a little sketchy that this only happens when we save through the menu; ideally game-triggered saves would trigger it too. */
    record_current_savefile();
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL sel = [menuItem action];
    NSInteger tag = [menuItem tag];

    if( tag >= AngbandWindowMenuItemTagBase && tag < AngbandWindowMenuItemTagBase + ANGBAND_TERM_MAX )
    {
        if( tag == AngbandWindowMenuItemTagBase )
        {
            // the main window should always be available and visible
            return YES;
        }
        else
        {
            NSInteger subwindowNumber = tag - AngbandWindowMenuItemTagBase;
            return (op_ptr->window_flag[subwindowNumber] > 0);
        }

        return NO;
    }

    if (sel == @selector(newGame:))
    {
        return ! game_in_progress;
    }
    else if (sel == @selector(editFont:))
    {
        return YES;
    }
    else if (sel == @selector(openGame:))
    {
        return ! game_in_progress;
    }
    else if (sel == @selector(saveGame:))   //// half
    {                                       //// half
        return (turn > 0);                  //// half
    }                                       //// half
    else if (sel == @selector(setRefreshRate:) && [superitem(menuItem) tag] == 150)
    {
        NSInteger fps = [[NSUserDefaults standardUserDefaults] integerForKey: @"FramesPerSecond"];
        [menuItem setState: ([menuItem tag] == fps)];
        return YES;
    }
    else if( sel == @selector(setGraphicsMode:) )
    {
        NSInteger requestedGraphicsMode = [[NSUserDefaults standardUserDefaults] integerForKey: @"GraphicsID"];
        [menuItem setState: (tag == requestedGraphicsMode)];
        return YES;
    }
    else if( sel == @selector(sendAngbandCommand:) )
    {
        // we only want to be able to send commands during an active game
        return !!game_in_progress;
    }
    else return YES;
}


- (IBAction)setRefreshRate:(NSMenuItem *)menuItem
{
    frames_per_second = [menuItem tag];
    [[NSUserDefaults angbandDefaults] setInteger:frames_per_second forKey:@"FramesPerSecond"];
}

- (IBAction)selectWindow: (id)sender
{
    NSInteger subwindowNumber = [(NSMenuItem *)sender tag] - AngbandWindowMenuItemTagBase;
    AngbandContext *context = angband_term[subwindowNumber]->data;
    [context->primaryWindow makeKeyAndOrderFront: self];
	[context saveWindowVisibleToDefaults: YES];
}

- (void)prepareWindowsMenu
{
    // get the window menu with default items and add a separator and item for the main window
    NSMenu *windowsMenu = [[NSApplication sharedApplication] windowsMenu];
    [windowsMenu addItem: [NSMenuItem separatorItem]];

    NSMenuItem *angbandItem = [[NSMenuItem alloc] initWithTitle: @"Sil" action: @selector(selectWindow:) keyEquivalent: @"0"];
    [angbandItem setTarget: self];
    [angbandItem setTag: AngbandWindowMenuItemTagBase];
    [windowsMenu addItem: angbandItem];
    [angbandItem release];

    // add items for the additional term windows
    for( NSInteger i = 1; i < ANGBAND_TERM_MAX; i++ )
    {
////half        NSString *title = [NSString stringWithFormat: @"Term %ld", (long)i];
        NSString *title = [NSString stringWithUTF8String: angband_term_name[i]]; ////half
        NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle: title action: @selector(selectWindow:) keyEquivalent: @""];
        [windowItem setTarget: self];
        [windowItem setTag: AngbandWindowMenuItemTagBase + i];
        [windowsMenu addItem: windowItem];
        [windowItem release];
    }
}

/**
 *  Send a command to Angband via a menu item. This places the appropriate key down events into the queue
 *  so that it seems like the user pressed them (instead of trying to use the term directly).
 */
- (void)sendAngbandCommand: (id)sender
{
    NSMenuItem *menuItem = (NSMenuItem *)sender;
    NSString *command = [self.commandMenuTagMap objectForKey: [NSNumber numberWithInteger: [menuItem tag]]];
    NSInteger windowNumber = [((AngbandContext *)angband_term[0]->data)->primaryWindow windowNumber];

    // send a \ to bypass keymaps
    NSEvent *escape = [NSEvent keyEventWithType: NSKeyDown
                                       location: NSZeroPoint
                                  modifierFlags: 0
                                      timestamp: 0.0
                                   windowNumber: windowNumber
                                        context: nil
                                     characters: @"\\"
                    charactersIgnoringModifiers: @"\\"
                                      isARepeat: NO
                                        keyCode: 0];
    [[NSApplication sharedApplication] postEvent: escape atStart: NO];

    // send the actual command (from the original command set)
    NSEvent *keyDown = [NSEvent keyEventWithType: NSKeyDown
                                        location: NSZeroPoint
                                   modifierFlags: 0
                                       timestamp: 0.0
                                    windowNumber: windowNumber
                                         context: nil
                                      characters: command
                     charactersIgnoringModifiers: command
                                       isARepeat: NO
                                         keyCode: 0];
    [[NSApplication sharedApplication] postEvent: keyDown atStart: NO];
}

/**
 *  Set up the command menu dynamically, based on CommandMenu.plist.
 */
- (void)prepareCommandMenu
{
    NSString *commandMenuPath = [[NSBundle mainBundle] pathForResource: @"CommandMenu" ofType: @"plist"];
    NSArray *commandMenuItems = [[NSArray alloc] initWithContentsOfFile: commandMenuPath];
    NSMutableDictionary *angbandCommands = [[NSMutableDictionary alloc] init];
    NSInteger tagOffset = 0;

    for( NSDictionary *item in commandMenuItems )
    {
        BOOL useShiftModifier = [[item valueForKey: @"ShiftModifier"] boolValue];
        BOOL useOptionModifier = [[item valueForKey: @"OptionModifier"] boolValue];
        NSUInteger keyModifiers = NSCommandKeyMask;
        keyModifiers |= (useShiftModifier) ? NSShiftKeyMask : 0;
        keyModifiers |= (useOptionModifier) ? NSAlternateKeyMask : 0;

        NSString *title = [item valueForKey: @"Title"];
        NSString *key = [item valueForKey: @"KeyEquivalent"];
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle: title action: @selector(sendAngbandCommand:) keyEquivalent: key];
        [menuItem setTarget: self];
        [menuItem setKeyEquivalentModifierMask: keyModifiers];
        [menuItem setTag: AngbandCommandMenuItemTagBase + tagOffset];
        [self.commandMenu addItem: menuItem];
        [menuItem release];

        NSString *angbandCommand = [item valueForKey: @"AngbandCommand"];
        [angbandCommands setObject: angbandCommand forKey: [NSNumber numberWithInteger: [menuItem tag]]];
        tagOffset++;
    }

    [commandMenuItems release];

    NSDictionary *safeCommands = [[NSDictionary alloc] initWithDictionary: angbandCommands];
    self.commandMenuTagMap = safeCommands;
    [safeCommands release];
    [angbandCommands release];
}

- (void)awakeFromNib
{
    [super awakeFromNib];

    [self prepareWindowsMenu];
    [self prepareCommandMenu];
}

- (void)applicationDidFinishLaunching:sender
{
    [AngbandContext beginGame];
    
    //once beginGame finished, the game is over - that's how Angband works, and we should quit
    game_is_finished = TRUE;
    [NSApp terminate:self];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if (p_ptr->playing == FALSE || game_is_finished == TRUE)
    {
        return NSTerminateNow;
    }
    else if (! inkey_flag)
    {
        /* For compatibility with other ports, do not quit in this case */
        return NSTerminateCancel;
    }
    else
    {
        ////cmd_insert(CMD_QUIT);
        /* Post an escape event so that we can return from our get-key-event function */
        wakeup_event_loop();
        quit_when_ready = true;
        // must return Cancel, not Later, because we need to get out of the run loop and back to Angband's loop
        return NSTerminateCancel;
    }
}

/* Dynamically build the Graphics menu */
- (void)menuNeedsUpdate:(NSMenu *)menu {
    
    /* Only the graphics menu is dynamic */
    if (! [[menu title] isEqualToString:@"Graphics"])
        return;
    
    /* If it's non-empty, then we've already built it. Currently graphics modes won't change once created; if they ever can we can remove this check.
       Note that the check mark does change, but that's handled in validateMenuItem: instead of menuNeedsUpdate: */
    if ([menu numberOfItems] > 0)
        return;
    
    /* This is the action for all these menu items */
    SEL action = @selector(setGraphicsMode:);
    
    /* Add an initial Classic ASCII menu item */
    NSMenuItem *item = [menu addItemWithTitle:@"Classic ASCII" action:action keyEquivalent:@""];
    [item setTag:GRAPHICS_NONE];
    
    /* Walk through the list of graphics modes */

#if 0 ////
    
    NSInteger i;
    for (i=0; graphics_modes[i].pNext; i++)
    {
        const graphics_mode *graf = &graphics_modes[i];
        
        /* Make the title. NSMenuItem throws on a nil title, so ensure it's not nil. */
        NSString *title = [[NSString alloc] initWithUTF8String:graf->menuname];
        if (! title) title = [@"(Unknown)" copy];
        
        /* Make the item */
        NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
        [item setTag:graf->grafID];
    }

#endif ////
    
}

/* Delegate method that gets called if we're asked to open a file. */
- (BOOL)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    /* Can't open a file once we've started */
    if (game_in_progress) return NO;
    
    /* We can only open one file. Use the last one. */
    NSString *file = [filenames lastObject];
    if (! file) return NO;
    
    /* Put it in savefile */
    if (! [file getFileSystemRepresentation:savefile maxLength:sizeof savefile]) return NO;
    
    /* Success, remember to load it */
    ////cmd.command = CMD_LOADFILE;
    
    /* Wake us up in case this arrives while we're sitting at the Welcome screen! */
    wakeup_event_loop();
    
    return YES;
}

@end

int main(int argc, char* argv[])
{
    NSApplicationMain(argc, (void*)argv);    
    return (0);
}

#endif /* MACINTOSH || MACH_O_CARBON */

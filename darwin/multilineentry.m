// 8 december 2015
#import "uipriv_darwin.h"

// TODO you actually have to click on parts with a line in them in order to start editing; clicking below the last line doesn't give focus

// NSTextView has no intrinsic content size by default, which wreaks havoc on a pure-Auto Layout system
// we'll have to take over to get it to work
// see also http://stackoverflow.com/questions/24210153/nstextview-not-properly-resizing-with-auto-layout and http://stackoverflow.com/questions/11237622/using-autolayout-with-expanding-nstextviews
@interface intrinsicSizeTextView : NSTextView
@end

@implementation intrinsicSizeTextView

- (NSSize)intrinsicContentSize
{
	NSTextContainer *textContainer;
	NSLayoutManager *layoutManager;
	NSRect rect;

	textContainer = [self textContainer];
	layoutManager = [self layoutManager];
	[layoutManager ensureLayoutForTextContainer:textContainer];
	rect = [layoutManager usedRectForTextContainer:textContainer];
	return rect.size;
}

- (void)didChangeText
{
	[super didChangeText];
	[self invalidateIntrinsicContentSize];
}

// TODO this doesn't call the above?
// TODO this also isn't perfect; play around with cpp-multithread
- (void)setString:(NSString *)str
{
	[super setString:str];
	[self didChangeText];
}

@end

struct uiMultilineEntry {
	uiDarwinControl c;
	NSScrollView *sv;
	intrinsicSizeTextView *tv;
	struct scrollViewData *d;
	void (*onChanged)(uiMultilineEntry *, void *);
	void *onChangedData;
};

// TODO events

uiDarwinControlAllDefaultsExceptDestroy(uiMultilineEntry, sv)

static void uiMultilineEntryDestroy(uiControl *c)
{
	uiMultilineEntry *e = uiMultilineEntry(c);

	scrollViewFreeData(e->sv, e->d);
	[e->tv release];
	[e->sv release];
	uiFreeControl(uiControl(e));
}

static void defaultOnChanged(uiMultilineEntry *e, void *data)
{
	// do nothing
}

char *uiMultilineEntryText(uiMultilineEntry *e)
{
	return uiDarwinNSStringToText([e->tv string]);
}

void uiMultilineEntrySetText(uiMultilineEntry *e, const char *text)
{
	// TODO does this send a changed signal?
	[e->tv setString:toNSString(text)];
}

// TODO scroll to end?
void uiMultilineEntryAppend(uiMultilineEntry *e, const char *text)
{
	// TODO better way?
	NSString *str;

	// TODO does this send a changed signal?
	str = [e->tv string];
	str = [str stringByAppendingString:toNSString(text)];
	[e->tv setString:str];
}

void uiMultilineEntryOnChanged(uiMultilineEntry *e, void (*f)(uiMultilineEntry *e, void *data), void *data)
{
	e->onChanged = f;
	e->onChangedData = data;
}

int uiMultilineEntryReadOnly(uiMultilineEntry *e)
{
	return [e->tv isEditable] == NO;
}

void uiMultilineEntrySetReadOnly(uiMultilineEntry *e, int readonly)
{
	BOOL editable;

	editable = YES;
	if (readonly)
		editable = NO;
	[e->tv setEditable:editable];
}

static uiMultilineEntry *finishMultilineEntry(BOOL hscroll)
{
	uiMultilineEntry *e;
	NSFont *font;
	struct scrollViewCreateParams p;

	uiDarwinNewControl(uiMultilineEntry, e);

	e->tv = [[intrinsicSizeTextView alloc] initWithFrame:NSZeroRect];
	// verified against Interface Builder, except for rich text options
	[e->tv setAllowsDocumentBackgroundColorChange:NO];
	[e->tv setBackgroundColor:[NSColor textBackgroundColor]];
	[e->tv setTextColor:[NSColor textColor]];
	[e->tv setAllowsUndo:YES];
	[e->tv setEditable:YES];
	[e->tv setSelectable:YES];
	[e->tv setRichText:NO];
	[e->tv setImportsGraphics:NO];
	[e->tv setBaseWritingDirection:NSWritingDirectionNatural];
	// TODO default paragraph format
	[e->tv setAllowsImageEditing:NO];
	[e->tv setAutomaticQuoteSubstitutionEnabled:NO];
	[e->tv setAutomaticLinkDetectionEnabled:NO];
	[e->tv setUsesRuler:NO];
	[e->tv setRulerVisible:NO];
	[e->tv setUsesInspectorBar:NO];
	[e->tv setSelectionGranularity:NSSelectByCharacter];
//TODO	[e->tv setInsertionPointColor:[NSColor insertionColor]];
	[e->tv setContinuousSpellCheckingEnabled:NO];
	[e->tv setGrammarCheckingEnabled:NO];
	[e->tv setUsesFontPanel:NO];
	[e->tv setEnabledTextCheckingTypes:0];
	[e->tv setAutomaticDashSubstitutionEnabled:NO];
	[e->tv setAutomaticSpellingCorrectionEnabled:NO];
	[e->tv setAutomaticTextReplacementEnabled:NO];
	[e->tv setSmartInsertDeleteEnabled:NO];
	[e->tv setLayoutOrientation:NSTextLayoutOrientationHorizontal];
	// TODO default find panel behavior
	// now just to be safe; this will do some of the above but whatever
	disableAutocorrect(e->tv);
	// this option is complex; just set it to the Interface Builder default
	[[e->tv layoutManager] setAllowsNonContiguousLayout:YES];
	if (hscroll) {
		// TODO this is a giant mess
		[e->tv setHorizontallyResizable:YES];
		[[e->tv textContainer] setWidthTracksTextView:NO];
		[[e->tv textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
	}
	// don't use uiDarwinSetControlFont() directly; we have to do a little extra work to set the font
	font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSRegularControlSize]];
	[e->tv setTypingAttributes:[NSDictionary
		dictionaryWithObject:font
		forKey:NSFontAttributeName]];
	// e->tv font from Interface Builder is nil, but setFont:nil throws an exception
	// let's just set it to the standard control font anyway, just to be safe
	[e->tv setFont:font];

	memset(&p, 0, sizeof (struct scrollViewCreateParams));
	p.DocumentView = e->tv;
	// this is what Interface Builder sets it to
	p.BackgroundColor = [NSColor colorWithCalibratedWhite:1.0 alpha:1.0];
	p.DrawsBackground = YES;
	p.Bordered = YES;
	p.HScroll = hscroll;
	p.VScroll = YES;
	e->sv = mkScrollView(&p, &(e->d));

	uiMultilineEntryOnChanged(e, defaultOnChanged, NULL);

	return e;
}

uiMultilineEntry *uiNewMultilineEntry(void)
{
	return finishMultilineEntry(NO);
}

uiMultilineEntry *uiNewNonWrappingMultilineEntry(void)
{
	return finishMultilineEntry(YES);
}

// TODO
#if 0

NSMutableString *s;
static void add(const char *fmt, ...)
{
	va_list ap;
	NSString *fmts;
	NSString *a;
	
	va_start(ap, fmt);
	fmts = [NSString stringWithUTF8String:fmt];
	a = [[NSString alloc] initWithFormat:fmts arguments:ap];
	[s appendString:a];
	[s appendString:@"\n"];
	va_end(ap);
}

static NSString *edgeInsetsStr(NSEdgeInsets i)
{
	return [NSString
		stringWithFormat:@"left:%g top:%g right:%g bottom:%g",
			i.left, i.top, i.right, i.bottom];
}

void printinfo(NSScrollView *sv, NSTextView *tv)
{
	s = [NSMutableString new];
	
#define self _s
struct {
NSScrollView *sv;
NSTextView *tv;
} _s;
_s.sv = sv;
_s.tv = tv;

	add("NSTextView");
	add(" textContainerInset %@",
		NSStringFromSize([self.tv textContainerInset]));
	add(" textContainerOrigin %@",
		NSStringFromPoint([self.tv textContainerOrigin]));
	add(" backgroundColor %@", [self.tv backgroundColor]);
	add(" drawsBackground %d", [self.tv drawsBackground]);
	add(" allowsDocumentBackgroundColorChange %d",
		[self.tv allowsDocumentBackgroundColorChange]);
	add(" allowedInputSourceLocales %@",
		[self.tv allowedInputSourceLocales]);
	add(" allowsUndo %d", [self.tv allowsUndo]);
	add(" isEditable %d", [self.tv isEditable]);
	add(" isSelectable %d", [self.tv isSelectable]);
	add(" isFieldEditor %d", [self.tv isFieldEditor]);
	add(" isRichText %d", [self.tv isRichText]);
	add(" importsGraphics %d", [self.tv importsGraphics]);
	add(" defaultParagraphStyle %@",
		[self.tv defaultParagraphStyle]);
	add(" allowsImageEditing %d", [self.tv allowsImageEditing]);
	add(" isAutomaticQuoteSubstitutionEnabled %d",
		[self.tv isAutomaticQuoteSubstitutionEnabled]);
	add(" isAutomaticLinkDetectionEnabled %d",
		[self.tv isAutomaticLinkDetectionEnabled]);
	add(" displaysLinkToolTips %d", [self.tv displaysLinkToolTips]);
	add(" usesRuler %d", [self.tv usesRuler]);
	add(" isRulerVisible %d", [self.tv isRulerVisible]);
	add(" usesInspectorBar %d", [self.tv usesInspectorBar]);
	add(" selectionAffinity %d", [self.tv selectionAffinity]);
	add(" selectionGranularity %d", [self.tv selectionGranularity]);
	add(" insertionPointColor %@", [self.tv insertionPointColor]);
	add(" selectedTextAttributes %@",
		[self.tv selectedTextAttributes]);
	add(" markedTextAttributes %@", [self.tv markedTextAttributes]);
	add(" linkTextAttributes %@", [self.tv linkTextAttributes]);
	add(" typingAttributes %@", [self.tv typingAttributes]);
	add(" smartInsertDeleteEnabled %d",
		[self.tv smartInsertDeleteEnabled]);
	add(" isContinuousSpellCheckingEnabled %d",
		[self.tv isContinuousSpellCheckingEnabled]);
	add(" isGrammarCheckingEnabled %d",
		[self.tv isGrammarCheckingEnabled]);
	add(" acceptsGlyphInfo %d", [self.tv acceptsGlyphInfo]);
	add(" usesFontPanel %d", [self.tv usesFontPanel]);
	add(" usesFindPanel %d", [self.tv usesFindPanel]);
	add(" enabledTextCheckingTypes %d",
		[self.tv enabledTextCheckingTypes]);
	add(" isAutomaticDashSubstitutionEnabled %d",
		[self.tv isAutomaticDashSubstitutionEnabled]);
	add(" isAutomaticDataDetectionEnabled %d",
		[self.tv isAutomaticDataDetectionEnabled]);
	add(" isAutomaticSpellingCorrectionEnabled %d",
		[self.tv isAutomaticSpellingCorrectionEnabled]);
	add(" isAutomaticTextReplacementEnabled %d",
		[self.tv isAutomaticTextReplacementEnabled]);
	add(" usesFindBar %d", [self.tv usesFindBar]);
	add(" isIncrementalSearchingEnabled %d",
		[self.tv isIncrementalSearchingEnabled]);
	add(" NSText:");
	add("  font %@", [self.tv font]);
	add("  textColor %@", [self.tv textColor]);
	add("  baseWritingDirection %d", [self.tv baseWritingDirection]);
	add("  maxSize %@",
		NSStringFromSize([self.tv maxSize]));
	add("  minSize %@",
		NSStringFromSize([self.tv minSize]));
	add("  isVerticallyResizable %d",
		[self.tv isVerticallyResizable]);
	add("  isHorizontallyResizable %d",
		[self.tv isHorizontallyResizable]);

#undef self
	
	fprintf(stdout, "%s", [s UTF8String]);
}

#endif

// 15 august 2015
#import "uipriv_darwin.h"

// TODOs to confirm
// - 10.8: if we switch to page 4, then switch back to page 1, check Spaced, and go back to page 4, some controls (progress bar, popup button) are clipped on the sides

@interface boxChild : NSObject
@property uiControl *c;
@property BOOL stretchy;
@property NSLayoutPriority oldPrimaryHuggingPri;
@property NSLayoutPriority oldSecondaryHuggingPri;
- (NSView *)view;
@end

@interface boxView : NSView {
	uiBox *b;
	NSMutableArray *children;
	BOOL vertical;
	int padded;
	uintmax_t nStretchy;

	NSLayoutConstraint *first;
	NSMutableArray *inBetweens;
	NSLayoutConstraint *last;
	NSMutableArray *otherConstraints;

	NSLayoutAttribute primaryStart;
	NSLayoutAttribute primaryEnd;
	NSLayoutAttribute secondaryStart;
	NSLayoutAttribute secondaryEnd;
	NSLayoutAttribute primarySize;
	NSLayoutConstraintOrientation primaryOrientation;
	NSLayoutConstraintOrientation secondaryOrientation;
}
- (id)initWithVertical:(BOOL)vert b:(uiBox *)bb;
- (void)onDestroy;
- (void)removeOurConstraints;
- (void)syncEnableStates:(int)enabled;
- (CGFloat)paddingAmount;
- (void)establishOurConstraints;
- (void)append:(uiControl *)c stretchy:(int)stretchy;
- (void)delete:(uintmax_t)n;
- (int)isPadded;
- (void)setPadded:(int)p;
- (BOOL)hugsTrailing;
- (BOOL)hugsBottom;
@end

struct uiBox {
	uiDarwinControl c;
	boxView *view;
};

@implementation boxChild

- (NSView *)view
{
	return (NSView *) uiControlHandle(self.c);
}

@end

@implementation boxView

- (id)initWithVertical:(BOOL)vert b:(uiBox *)bb
{
	self = [super initWithFrame:NSZeroRect];
	if (self != nil) {
		// the weird names vert and bb are to shut the compiler up about shadowing because implicit this/self is stupid
		self->b = bb;
		self->vertical = vert;
		self->padded = 0;
		self->children = [NSMutableArray new];
		self->nStretchy = 0;

		self->inBetweens = [NSMutableArray new];
		self->otherConstraints = [NSMutableArray new];

		if (self->vertical) {
			self->primaryStart = NSLayoutAttributeTop;
			self->primaryEnd = NSLayoutAttributeBottom;
			self->secondaryStart = NSLayoutAttributeLeading;
			self->secondaryEnd = NSLayoutAttributeTrailing;
			self->primarySize = NSLayoutAttributeHeight;
			self->primaryOrientation = NSLayoutConstraintOrientationVertical;
			self->secondaryOrientation = NSLayoutConstraintOrientationHorizontal;
		} else {
			self->primaryStart = NSLayoutAttributeLeading;
			self->primaryEnd = NSLayoutAttributeTrailing;
			self->secondaryStart = NSLayoutAttributeTop;
			self->secondaryEnd = NSLayoutAttributeBottom;
			self->primarySize = NSLayoutAttributeWidth;
			self->primaryOrientation = NSLayoutConstraintOrientationHorizontal;
			self->secondaryOrientation = NSLayoutConstraintOrientationVertical;
		}
	}
	return self;
}

- (void)onDestroy
{
	boxChild *bc;

	[self removeOurConstraints];
	[self->inBetweens release];
	[self->otherConstraints release];

	for (bc in self->children) {
		uiControlSetParent(bc.c, NULL);
		uiDarwinControlSetSuperview(uiDarwinControl(bc.c), nil);
		uiControlDestroy(bc.c);
	}
	[self->children release];
}

- (void)removeOurConstraints
{
	if (self->first != nil) {
		[self removeConstraint:self->first];
		[self->first release];
		self->first = nil;
	}
	if ([self->inBetweens count] != 0) {
		[self removeConstraints:self->inBetweens];
		[self->inBetweens removeAllObjects];
	}
	if (self->last != nil) {
		[self removeConstraint:self->last];
		[self->last release];
		self->last = nil;
	}
	if ([self->otherConstraints count] != 0) {
		[self removeConstraints:self->otherConstraints];
		[self->otherConstraints removeAllObjects];
	}
}

- (void)syncEnableStates:(int)enabled
{
	boxChild *bc;

	for (bc in self->children)
		uiDarwinControlSyncEnableState(uiDarwinControl(bc.c), enabled);
}

- (CGFloat)paddingAmount
{
	if (!self->padded)
		return 0.0;
	return uiDarwinPaddingAmount(NULL);
}

// TODO something about spinbox hugging
- (void)establishOurConstraints
{
	boxChild *bc;
	CGFloat padding;
	NSView *prev;
	NSLayoutConstraint *c;
	BOOL (*hugsSecondary)(uiDarwinControl *);

	[self removeOurConstraints];
	if ([self->children count] == 0)
		return;
	padding = [self paddingAmount];

	// first arrange in the primary direction
	prev = nil;
	for (bc in self->children) {
		if (prev == nil) {			// first view
			self->first = mkConstraint(self, self->primaryStart,
				NSLayoutRelationEqual,
				[bc view], self->primaryStart,
				1, 0,
				@"uiBox first primary constraint");
			[self addConstraint:self->first];
			[self->first retain];
			prev = [bc view];
			continue;
		}
		// not the first; link it
		c = mkConstraint(prev, self->primaryEnd,
			NSLayoutRelationEqual,
			[bc view], self->primaryStart,
			1, -padding,
			@"uiBox in-between primary constraint");
		[self addConstraint:c];
		[self->inBetweens addObject:c];
		prev = [bc view];
	}
	self->last = mkConstraint(prev, self->primaryEnd,
		NSLayoutRelationEqual,
		self, self->primaryEnd,
		1, 0,
		@"uiBox last primary constraint");
	[self addConstraint:self->last];
	[self->last retain];

	// then arrange in the secondary direction
	hugsSecondary = uiDarwinControlHugsTrailingEdge;
	if (!self->vertical)
		hugsSecondary = uiDarwinControlHugsBottom;
	for (bc in self->children) {
		c = mkConstraint(self, self->secondaryStart,
			NSLayoutRelationEqual,
			[bc view], self->secondaryStart,
			1, 0,
			@"uiBox secondary start constraint");
		[self addConstraint:c];
		[self->otherConstraints addObject:c];
		c = mkConstraint([bc view], self->secondaryEnd,
			NSLayoutRelationLessThanOrEqual,
			self, self->secondaryEnd,
			1, 0,
			@"uiBox secondary end <= constraint");
		if ((*hugsSecondary)(uiDarwinControl(bc.c)))
			[c setPriority:NSLayoutPriorityDefaultLow];
		[self addConstraint:c];
		[self->otherConstraints addObject:c];
		c = mkConstraint([bc view], self->secondaryEnd,
			NSLayoutRelationEqual,
			self, self->secondaryEnd,
			1, 0,
			@"uiBox secondary end == constraint");
		if (!(*hugsSecondary)(uiDarwinControl(bc.c)))
			[c setPriority:NSLayoutPriorityDefaultLow];
		[self addConstraint:c];
		[self->otherConstraints addObject:c];
	}

	// and make all stretchy controls the same size
	if (self->nStretchy == 0)
		return;
	prev = nil;		// first stretchy view
	for (bc in self->children) {
		if (!bc.stretchy)
			continue;
		if (prev == nil) {
			prev = [bc view];
			continue;
		}
		c = mkConstraint(prev, self->primarySize,
			NSLayoutRelationEqual,
			[bc view], self->primarySize,
			1, 0,
			@"uiBox stretchy size constraint");
		[self addConstraint:c];
		[self->otherConstraints addObject:c];
	}
}

- (void)append:(uiControl *)c stretchy:(int)stretchy
{
	boxChild *bc;
	NSLayoutPriority priority;
	uintmax_t oldnStretchy;

	bc = [boxChild new];
	bc.c = c;
	bc.stretchy = stretchy;
	bc.oldPrimaryHuggingPri = uiDarwinControlHuggingPriority(uiDarwinControl(bc.c), self->primaryOrientation);
	bc.oldSecondaryHuggingPri = uiDarwinControlHuggingPriority(uiDarwinControl(bc.c), self->secondaryOrientation);

	uiControlSetParent(bc.c, uiControl(self->b));
	uiDarwinControlSetSuperview(uiDarwinControl(bc.c), self);
	uiDarwinControlSyncEnableState(uiDarwinControl(bc.c), uiControlEnabledToUser(uiControl(self->b)));

	// if a control is stretchy, it should not hug in the primary direction
	// otherwise, it should *forcibly* hug
	if (bc.stretchy)
		priority = NSLayoutPriorityDefaultLow;
	else
		// TODO will default high work?
		priority = NSLayoutPriorityRequired;
	uiDarwinControlSetHuggingPriority(uiDarwinControl(bc.c), priority, self->primaryOrientation);
	// make sure controls don't hug their secondary direction so they fill the width of the view
	uiDarwinControlSetHuggingPriority(uiDarwinControl(bc.c), NSLayoutPriorityDefaultLow, self->secondaryOrientation);

	[self->children addObject:bc];

	[self establishOurConstraints];
	if (bc.stretchy) {
		oldnStretchy = self->nStretchy;
		self->nStretchy++;
		if (oldnStretchy == 0)
			uiDarwinNotifyEdgeHuggingChanged(uiDarwinControl(self->b));
	}

	[bc release];		// we don't need the initial reference now
}

- (void)delete:(uintmax_t)n
{
	boxChild *bc;
	int stretchy;

	// TODO separate into a method?
	bc = (boxChild *) [self->children objectAtIndex:n];
	stretchy = bc.stretchy;

	uiControlSetParent(bc.c, NULL);
	uiDarwinControlSetSuperview(uiDarwinControl(bc.c), nil);

	uiDarwinControlSetHuggingPriority(uiDarwinControl(bc.c), bc.oldPrimaryHuggingPri, self->primaryOrientation);
	uiDarwinControlSetHuggingPriority(uiDarwinControl(bc.c), bc.oldSecondaryHuggingPri, self->secondaryOrientation);

	[self->children removeObjectAtIndex:n];

	[self establishOurConstraints];
	if (stretchy) {
		self->nStretchy--;
		if (self->nStretchy == 0)
			uiDarwinNotifyEdgeHuggingChanged(uiDarwinControl(self->b));
	}
}

- (int)isPadded
{
	return self->padded;
}

- (void)setPadded:(int)p
{
	CGFloat padding;
	NSLayoutConstraint *c;

	self->padded = p;
	padding = [self paddingAmount];
	for (c in self->inBetweens)
		[c setConstant:-padding];
	// TODO call anything?
}

- (BOOL)hugsTrailing
{
	if (self->vertical)		// always hug if vertical
		return YES;
	return self->nStretchy != 0;
}

- (BOOL)hugsBottom
{
	if (!self->vertical)		// always hug if horizontal
		return YES;
	return self->nStretchy != 0;
}

@end

static void uiBoxDestroy(uiControl *c)
{
	uiBox *b = uiBox(c);

	[b->view onDestroy];
	[b->view release];
	uiFreeControl(uiControl(b));
}

uiDarwinControlDefaultHandle(uiBox, view)
uiDarwinControlDefaultParent(uiBox, view)
uiDarwinControlDefaultSetParent(uiBox, view)
uiDarwinControlDefaultToplevel(uiBox, view)
uiDarwinControlDefaultVisible(uiBox, view)
uiDarwinControlDefaultShow(uiBox, view)
uiDarwinControlDefaultHide(uiBox, view)
uiDarwinControlDefaultEnabled(uiBox, view)
uiDarwinControlDefaultEnable(uiBox, view)
uiDarwinControlDefaultDisable(uiBox, view)

static void uiBoxSyncEnableState(uiDarwinControl *c, int enabled)
{
	uiBox *b = uiBox(c);

	if (uiDarwinShouldStopSyncEnableState(uiDarwinControl(b), enabled))
		return;
	[b->view syncEnableStates:enabled];
}

uiDarwinControlDefaultSetSuperview(uiBox, view)

static BOOL uiBoxHugsTrailingEdge(uiDarwinControl *c)
{
	uiBox *b = uiBox(c);

	return [b->view hugsTrailing];
}

static BOOL uiBoxHugsBottom(uiDarwinControl *c)
{
	uiBox *b = uiBox(c);

	return [b->view hugsBottom];
}

static void uiBoxChildEdgeHuggingChanged(uiDarwinControl *c)
{
	uiBox *b = uiBox(c);

	[b->view establishOurConstraints];
}

uiDarwinControlDefaultHuggingPriority(uiBox, view)
uiDarwinControlDefaultSetHuggingPriority(uiBox, view)

void uiBoxAppend(uiBox *b, uiControl *c, int stretchy)
{
	// TODO on other platforms
	if (c == NULL)
		userbug("You cannot add NULL to a uiBox.");
	[b->view append:c stretchy:stretchy];
}

void uiBoxDelete(uiBox *b, uintmax_t n)
{
	[b->view delete:n];
}

int uiBoxPadded(uiBox *b)
{
	return [b->view isPadded];
}

void uiBoxSetPadded(uiBox *b, int padded)
{
	[b->view setPadded:padded];
}

static uiBox *finishNewBox(BOOL vertical)
{
	uiBox *b;

	uiDarwinNewControl(uiBox, b);

	b->view = [[boxView alloc] initWithVertical:vertical b:b];

	return b;
}

uiBox *uiNewHorizontalBox(void)
{
	return finishNewBox(NO);
}

uiBox *uiNewVerticalBox(void)
{
	return finishNewBox(YES);
}

#import "common.h"
#import "Protean.h"
#import "PRStatusApps.h"
#import <flipswitch/Flipswitch.h>
#import "PDFImage.h"
#import "PDFImageOptions.h"

extern "C" CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);
extern "C" CFPropertyListRef MGCopyAnswer(CFStringRef property);
extern const char *__progname; 
#define PLIST_NAME @"/var/mobile/Library/Preferences/com.efrederickson.protean.settings.plist"

NSObject *lockObject = [[NSObject alloc] init];

void updateItem(int key, NSString *identifier)
{
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.apple.springboard"])
    	return;
    //if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive)
    //	return;

    NSString *nKey = [NSString stringWithFormat:@"%d",key];

    NSMutableDictionary *prefs = [NSMutableDictionary
        dictionaryWithContentsOfFile:PLIST_NAME];
    if (prefs == nil)
        prefs = [NSMutableDictionary dictionary];

    NSMutableDictionary *properties = [prefs objectForKey:nKey];
    if (properties)
    	return;

    properties = [NSMutableDictionary dictionary];

    [properties setObject:identifier forKey:@"identifier"];
    [properties setObject:nKey forKey:@"key"];

    [prefs setObject:properties forKey:nKey];

    @synchronized (lockObject) {
        [prefs writeToFile:PLIST_NAME atomically:YES];
        [Protean reloadSettings];
    }
}

void updateItem2(int key, NSString *identifier)
{
    //NSLog(@"[Protean] %@", identifier);
    if (identifier == nil || key < 33)
        return;

    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive)
    	return;

    NSString *nKey = [NSString stringWithFormat:@"%d",key];

    NSMutableDictionary *prefs = [NSMutableDictionary
        dictionaryWithContentsOfFile:PLIST_NAME];
    if (prefs == nil)
        prefs = [NSMutableDictionary dictionary];
    
    int maxKey = 33;

    for (id key2 in prefs)
    {
        if ([prefs[key2] isKindOfClass:[NSDictionary class]] == NO)
            continue;

        if (prefs[key2][@"identifier"] == nil)
            continue;

        if ([prefs[key2][@"identifier"] isEqual:identifier] && key != [key2 intValue])
        {
            NSMutableDictionary *tmp = [prefs[key2] mutableCopy]; // same identifier
            tmp[@"key"] = nKey;
            
            NSMutableDictionary *tmp2 = [prefs[nKey] mutableCopy]; // different identifier?
            if (tmp2 == nil || [tmp2[@"identifier"] isEqual:identifier])
            {
                [prefs removeObjectForKey:key2];
            }
            else
            {
                tmp2[@"key"] = [key2 copy];
                prefs[key2] = tmp2;
            }

            [prefs setObject:tmp forKey:nKey];

            @synchronized (lockObject) {
                [prefs writeToFile:PLIST_NAME atomically:YES];
                [Protean reloadSettings];
            }
            return;
        }
        else if ([prefs[key2][@"identifier"] isEqual:identifier] && key == [key2 intValue])
            return;
            
        if (maxKey < [key2 intValue])
            maxKey = [key2 intValue];
    }

    NSMutableDictionary *properties = [prefs objectForKey:nKey];
    if (!properties)
        properties = [NSMutableDictionary dictionary];

    if ([properties[@"identifier"] isEqual:identifier] == NO)
    {
        id _key = [NSNumber numberWithInt:maxKey + 1];
        properties[@"key"] = _key;
        prefs[[NSString stringWithFormat:@"%d",maxKey+1]] = [properties mutableCopy];

        properties = [NSMutableDictionary dictionary];
    }

    properties[@"identifier"] = identifier;
    properties[@"key"] = nKey;
    prefs[nKey] = properties;

    @synchronized (lockObject) {
        [prefs writeToFile:PLIST_NAME atomically:YES];
        [Protean reloadSettings];
    }
}

NSString *nameFromItem(UIStatusBarItem *item)
{
	NSRange range = [[item description] rangeOfString:@"[" options:NSLiteralSearch];
    if (range.location == NSNotFound)
        return item.description;
	NSRange iconNameRange;
	iconNameRange.location = range.location + 1;
    iconNameRange.length =  ((NSString *)[item description]).length - range.location - 2;
	NSString *part1 = [[item description] substringWithRange:iconNameRange];

    NSRange range2 = [part1 rangeOfString:@"(" options:NSLiteralSearch];
    if (range2.location == NSNotFound || range2.location == 0)
        return part1;
    else
    {
        NSRange parenRange;
        parenRange.location = 0;
        parenRange.length = range2.location - 1;
        return [part1 substringWithRange:parenRange];
    }
}

NSDictionary *settingsForItem(UIStatusBarItem *item)
{
    int key = MSHookIvar<int>(item, "_type");
    NSString *nKey = [NSString stringWithFormat:@"%d", key];

    if (key < 33) // System item
    {

        NSDictionary *prefs = [Protean getOrLoadSettings];

        NSMutableDictionary *properties = [prefs objectForKey:nKey];
        if (!properties)
            properties = [NSMutableDictionary dictionary];

        return properties;
    }
    else // Custom Item
    {
        NSString *identifier = [Protean mappedIdentifierForItem:MSHookIvar<int>(item, "_type")];

        NSDictionary *prefs = [Protean getOrLoadSettings];
            
        for (id key in prefs)
        {
            if (prefs[key] && [prefs[key] isKindOfClass:[NSDictionary class]] && ([prefs[key][@"identifier"] isEqual:identifier] || [prefs[key][@"key"] isEqual:nKey]))
            {
                return prefs[key];
            }
        }

        return [NSMutableDictionary dictionary];
    }
}

%hook UIStatusBarItem
+ (UIStatusBarItem*)itemWithType:(int)arg1 idiom:(long long)arg2
{
    UIStatusBarItem* item = %orig;
 
    CHECK_ENABLED(item)

    NSString *name = @"";

    if ([item isKindOfClass:[%c(UIStatusBarCustomItem) class]])
    {
        //name = [%c(Protean) mappedIdentifierForItem:(arg1 - 33)]; // 32 is number of default items (LSB starts from there)
        name = nil;
    }
    else
        name = nameFromItem(item);

    if (name != nil)
        updateItem(arg1, name);

    return item;
}

- (_Bool)appearsInRegion:(int)arg1
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];

    if ([self type] == 0)
    {
        id _showLSTime = [Protean getOrLoadSettings][@"showLSTime"];
        BOOL showLSTime = _showLSTime ? [_showLSTime boolValue] : YES;
        BOOL isLSVisible = [[%c(SBLockScreenManager) sharedInstance] isUILocked];

        if (isLSVisible && !showLSTime)
            return NO;
    }

    if (alignment == arg1) // 0, 1, 2 :: left, right, ?center
        return YES;
    else if (alignment == 3) // hide
        return NO;
    else if (alignment == 4) // default
        return %orig;
    else
        return NO;
}

-(int) centerOrder
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];
    
    if (alignment != 2)
        return %orig;

    id _centerOrder = settingsForItem(self)[@"order"];
    int centerOrder = _centerOrder == nil ? %orig : [_centerOrder intValue];

    return centerOrder;
}

-(int) rightOrder
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];
    
    if (alignment != 1)
        return %orig;

    id _rightOrder = settingsForItem(self)[@"order"];
    int rightOrder = _rightOrder == nil ? %orig : [_rightOrder intValue];

    return rightOrder;
}
-(int) leftOrder
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];

    if (alignment != 0)
        return %orig;

    id _leftOrder = settingsForItem(self)[@"order"];
    int leftOrder = _leftOrder == nil ? %orig : [_leftOrder intValue];

    return leftOrder;
}

-(BOOL) appearsOnRight
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];
    if (alignment == 0 || alignment == 2 || alignment == 3) // left, center, hidden
        return NO;
    else if (alignment == 1)
        return YES;
    return %orig;
}

-(BOOL) appearsOnLeft
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];
    if (alignment == 1 || alignment == 2 || alignment == 3) // left, center, hidden
        return NO;
    else if (alignment == 0)
        return YES;
    return %orig;
}

- (int)priority
{
    CHECK_ENABLED(%orig);

    return 2;
}
%end

%hook UIStatusBarCustomItem
+ (UIStatusBarItem*)itemWithType:(int)arg1 idiom:(long long)arg2
{
    UIStatusBarItem* item = %orig;
 
    CHECK_ENABLED(item)

    NSString *name = @"";

    if ([item isKindOfClass:[%c(UIStatusBarCustomItem) class]])
    {
        //name = [%c(Protean) mappedIdentifierForItem:(arg1 - 33)]; // 32 is number of default items (LSB starts from there)
        name = nil;
    }
    else
        name = nameFromItem(item);

    if (name != nil)
        updateItem(arg1, name);

    return item;
}

- (_Bool)appearsInRegion:(int)arg1
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];

    if (alignment == arg1) // 0, 1, 2 :: left, right, ?center
        return YES;
    else if (alignment == 3) // hide
        return NO;
    else if (alignment == 4) // default
        return %orig;
    else
        return NO;
}

-(int) centerOrder
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];

    id _centerOrder = settingsForItem(self)[@"order"];
    
    if (alignment != 2)
        return %orig;

    int centerOrder = _centerOrder == nil ? %orig : [_centerOrder intValue];

    if (centerOrder == 0)
        centerOrder = 1;
    return centerOrder;
}

-(int) rightOrder
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];

    id _rightOrder = settingsForItem(self)[@"order"];
    
    if (alignment != 1)
        return %orig;

    int rightOrder = _rightOrder == nil ? %orig : [_rightOrder intValue];
    if (rightOrder == 0)
        rightOrder = 1;
    return rightOrder;
}
-(int) leftOrder
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];

    if (alignment != 0)
        return %orig;

    id _leftOrder = settingsForItem(self)[@"order"];
    int leftOrder = _leftOrder == nil ? %orig : [_leftOrder intValue];
    if (leftOrder == 0)
        leftOrder = 1;
    return leftOrder;
}

-(BOOL) appearsOnRight
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];
    if (alignment == 0 || alignment == 2 || alignment == 3) // left, center, hidden
        return NO;
    else if (alignment == 1)
        return YES;
    return %orig;
}

-(BOOL) appearsOnLeft
{
    CHECK_ENABLED(%orig);

    id _alignment = settingsForItem(self)[@"alignment"];
    int alignment = _alignment == nil ? 4 : [_alignment intValue];
    if (alignment == 1 || alignment == 2 || alignment == 3) // left, center, hidden
        return NO;
    else if (alignment == 0)
        return YES;
    return %orig;
}

- (int)priority
{
    CHECK_ENABLED(%orig);

    return 2;
}
%end

%hook LSStatusBarItem
- (id) initWithIdentifier:(NSString*) identifier alignment:(StatusBarAlignment) orig_alignment
{
    CHECK_ENABLED(%orig);
    StatusBarAlignment new_alignment = orig_alignment;

    NSDictionary *prefs = [Protean getOrLoadSettings];
    for (id key in prefs)
    {
        if (prefs[key] && [prefs[key] isKindOfClass:[NSDictionary class]] && [prefs[key][@"identifier"] isEqual:identifier])
        {
            id _alignment = prefs[key][@"alignment"];
            int alignment = _alignment == nil ? 4 : [_alignment intValue];
            if (alignment == 0)
                new_alignment = StatusBarAlignmentLeft;
            else if (alignment == 1)
                new_alignment = StatusBarAlignmentRight;
            else if (alignment == 2)
                new_alignment = StatusBarAlignmentCenter;

            break;
        }
    }

    // 0 = left, 1 = right
    //else if (alignment == 2) // wait can't have image LSB items in the center (WHY?!?!?!)
    //    new_alignment = orig_alignment;
    // 3 = hidden, 4 = default
    
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.apple.springboard"])
    {
        [Protean mapIdentifierToItem:identifier];
    }

    return %orig(identifier, new_alignment);
}

-(void) setVisible:(BOOL)visible
{
    CHECK_ENABLED2(%orig);

    int alignment;
    NSDictionary *prefs = [Protean getOrLoadSettings];

    for (id key in prefs)
    {
        if (prefs[key] && [prefs[key] isKindOfClass:[NSDictionary class]] && [prefs[key][@"identifier"] isEqual:MSHookIvar<NSString*>(self, "_identifier")])
        {
            id _alignment = prefs[key][@"alignment"];
            alignment = _alignment == nil ? 4 : [_alignment intValue];
            break;
        }
    }

    if (alignment == 3)
    {
        %orig(NO);
        return;
    }
    %orig;  
}

-(BOOL) isVisible
{
    CHECK_ENABLED(%orig);

    int alignment;
    NSDictionary *prefs = [Protean getOrLoadSettings];

    for (id key in prefs)
    {
        if (prefs[key] && [prefs[key] isKindOfClass:[NSDictionary class]] && [prefs[key][@"identifier"] isEqual:MSHookIvar<NSString*>(self, "_identifier")])
        {
            id _alignment = prefs[key][@"alignment"];
            alignment = _alignment == nil ? 4 : [_alignment intValue];
            break;
        }
    }

    if (alignment == 3)
        return NO;
    return %orig;
}
%end

%hook UIStatusBarCustomItemView
-(id)initWithItem:(UIStatusBarCustomItem*)arg1 data:(id)arg2 actions:(int)arg3 style:(id)arg4
{
    id _self = %orig;
    
    CHECK_ENABLED(_self);

    updateItem2(MSHookIvar<int>(arg1, "_type"), [Protean mappedIdentifierForItem:MSHookIvar<int>(arg1, "_type")]);
    
    return _self;
}

- (CGFloat)standardPadding 
{
    CGFloat o = %orig; 

    if ([Protean getOrLoadSettings][@"defaultPadding"] == nil)
    {
        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_NAME];
        prefs[@"defaultPadding"] = [NSNumber numberWithFloat:o];
        //@synchronized (lockObject)
        {
            [prefs writeToFile:PLIST_NAME atomically:YES];
        }
    }

    CHECK_ENABLED(o);
    id padding = [Protean getOrLoadSettings][@"padding"];
    return padding ? [padding floatValue] : o;
}
%end

@interface UIStatusBarLayoutManager (Protean)
- (CGRect)_frameForItemView:(id)arg1 startPosition:(CGFloat)arg2 firstView:(BOOL)arg3;
@end

__strong NSMutableDictionary *storedStarts = [NSMutableDictionary dictionary];
BOOL o = NO;

%hook UIStatusBarItemView
-(void)setUserInteractionEnabled:(BOOL)enabled
{ 
    CHECK_ENABLED2(%orig);

    if ([Protean canHandleTapForItem:self.item])
        %orig(YES); 
    else
        %orig;
}

- (id)initWithItem:(id)arg1 data:(id)arg2 actions:(int)arg3 style:(id)arg4
{
    id _self = %orig;

    if ([Protean canHandleTapForItem:self.item])
    {
        CHECK_ENABLED(_self);
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(prTap:)];
        [self addGestureRecognizer:tap];
    }

    return _self;
}

%new
- (void)prTap:(UITapGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateEnded)
    {
        [Protean HandlerForTapOnItem:self.item];
    }
}

-(CGRect) frame
{
    CGRect ret = %orig;

    CHECK_ENABLED(ret);

    if (!self.item)
        return ret;


    if (ret.origin.x == 0 && ret.origin.y == 0)
    {
        id overlap_ = [Protean getOrLoadSettings][@"allowOverlap"];
        if ([overlap_ boolValue])
        {
            ret = (CGRect) { { [storedStarts[[NSNumber numberWithInt:MSHookIvar<int>(self.item, "_type")]] floatValue], 0}, ret.size };
        }
    }

    return ret;
/*
    int type = MSHookIvar<int>(self.item, "_type");
    if (type < 33)
        return ret;

    static NSArray *switchIdentifiers;
    if (!switchIdentifiers) switchIdentifiers = [[[FSSwitchPanel sharedPanel].switchIdentifiers copy] retain];

    NSString *name = [Protean mappedIdentifierForItem:type];
    if (name)
        if ([name hasPrefix:@"com.efrederickson.protean-"])
            if ([switchIdentifiers containsObject:[name substringFromIndex:26]])
                ret.size.width = 13;

    return ret;
*/
}

- (void)setVisible:(BOOL)arg1 
{
    BOOL force = o;
    
    id overlap_ = [Protean getOrLoadSettings][@"allowOverlap"];
    if (!overlap_ || [overlap_ boolValue] == NO)
    {
        %orig;
        return;
    }

    int type = MSHookIvar<int>(self.item, "_type");
    if (type >= 33)
    {
        NSString *name = [Protean mappedIdentifierForItem:type];
        NSDictionary *d = [[%c(LSStatusBarClient) sharedInstance] currentMessage][name];
        if (d)
        {
            id visible = d[@"visible"];
            if (!visible || [visible boolValue])
                force = YES;
        }
    }

    %orig(force ? YES : arg1);
}

- (CGFloat)standardPadding 
{
    CGFloat o = %orig; 

    if ([Protean getOrLoadSettings][@"defaultPadding"] == nil)
    {
        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_NAME];
        prefs[@"defaultPadding"] = [NSNumber numberWithFloat:o];
        //@synchronized (lockObject)
        {
            [prefs writeToFile:PLIST_NAME atomically:YES];
            [Protean reloadSettings];
        }
    }

    CHECK_ENABLED(o);
    id padding = [Protean getOrLoadSettings][@"padding"];
    return padding ? [padding floatValue] : o;
}
%end

%hook UIStatusBarLayoutManager
- (CGRect)_frameForItemView:(UIStatusBarItemView*)arg1 startPosition:(CGFloat)arg2 firstView:(BOOL)arg3
{
    CGRect r = %orig(arg1, arg2, arg3);
    CHECK_ENABLED(r);
    id overlap_ = [Protean getOrLoadSettings][@"allowOverlap"];
    if ([overlap_ boolValue] == NO)
        return %orig;

    if (LIBSTATUSBAR8)
    {
        // what what
        return r;
    }
    
    if (arg1.item)
    {
    	NSNumber *num = [NSNumber numberWithInt:MSHookIvar<int>(arg1.item, "_type")];
        if (storedStarts[num])
        {
            if (o)
            {
                if ([[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.apple.springboard"])
                {
                    // hmmm
                    // layout gets screwey here, in SpringBoard and well, other apps...
                    
                    if ([arg1.item appearsOnRight])
                    {
                    
                    }
                    else
                    {
                        if ([storedStarts[num] floatValue] < r.origin.x / 2)
                            ;
                        else
                            return r;
                    }
                }

                storedStarts[num] = [NSNumber numberWithFloat:r.origin.x];
            }
        }
        else
        {
            storedStarts[num] = [NSNumber numberWithFloat:r.origin.x];
        }
    }
    return r;
}

- (BOOL)prepareEnabledItems:(BOOL*)arg1 withData:(id)arg2 actions:(int)arg3
{
    CHECK_ENABLED(%orig);

    o = YES;
    BOOL r = %orig;
    o = NO;
    return r;
}
%end // hook UIStatusBarLayoutManager

%group NOT_LIBSTATUSBAR8
%hook UIStatusBarLayoutManager
- (CGFloat)_startPosition
{
	CGFloat orig = %orig;
	int region = MSHookIvar<int>(self, "_region");
	NSArray *itemViews = [self _itemViewsSortedForLayout];
	if (region == 2 && [itemViews count] > 1)
	{
		CGFloat width = 0;
		//width -= [itemViews[0] frame].size.width;
		for (UIStatusBarItemView *view in itemViews)
			width += view.frame.size.width;
		return orig - floor(width / 2) 
            + UIScreen.mainScreen.scale; // ... how does that even fix it? 
	}
	return orig;
}

/*
- (CGRect)rectForItems:(id)arg1
{
	int region = MSHookIvar<int>(self, "_region");

	CGRect rect = %orig;
	if (region == 2 && [[self _itemViewsSortedForLayout] count] > 1)
		rect.origin.x -= [self _startPosition];
	return rect;
}
*/
%end // hook UIStatusBarLayoutManager
%end // Group NOT_LIBSTATUSBAR8

%hook UIStatusBarForegroundView
- (id)_computeVisibleItemsPreservingHistory:(_Bool)arg1
{
    CHECK_ENABLED(%orig);

    o = YES;
    id r = %orig;
    o = NO;
    return r;
}

- (CGFloat)edgePadding 
{
    CGFloat o = %orig; 
    CHECK_ENABLED(o);
    id padding = [Protean getOrLoadSettings][@"padding"];
    return padding ? ([padding floatValue] > o ? o : [padding floatValue]) : o;
}
%end

%hook SBApplication
- (void)setBadge:(id)arg1
{
    %orig;
    CHECK_ENABLED();
    
    int badgeCount = [self.badgeNumberOrString intValue];
    NSString *ident = self.bundleIdentifier;

    [PRStatusApps updateCachedBadgeCount:ident count:badgeCount > 0 ? badgeCount : 0];
    if (badgeCount > 0)
    {
        [PRStatusApps showIconFor:ident badgeCount:badgeCount];
    }
    else // badgeCount <= 0
    {    
        id nc_ = [Protean getOrLoadSettings][@"useNC"];
        if (nc_ && [nc_ boolValue])
        {
            if ([PRStatusApps ncCount:ident] > 0)
                [PRStatusApps updateNCStatsForIcon:ident count:[PRStatusApps ncCount:ident]]; // update with NC data
            else
            {
                [PRStatusApps hideIconFor:ident];
            }
        }
        else
        {
            [PRStatusApps hideIconFor:ident];
        }
    }
}
%end

/*
%hook SBIcon
-(long long) badgeValue
{
    long long badgeCount = %orig;
    CHECK_ENABLED(badgeCount);
    
    if ([self respondsToSelector:@selector(applicationBundleID)] == NO || self.applicationBundleID == nil)
        return badgeCount;
    NSString *ident = self.applicationBundleID;

    [PRStatusApps updateCachedBadgeCount:ident count:badgeCount > 0 ? badgeCount : 0];
    if (badgeCount > 0)
    {
        [PRStatusApps showIconFor:ident badgeCount:badgeCount];
    }
    else // badgeCount <= 0
    {    
        id nc_ = [Protean getOrLoadSettings][@"useNC"];
        if (nc_ && [nc_ boolValue])
        {
            if ([PRStatusApps ncCount:ident] > 0)
                [PRStatusApps updateNCStatsForIcon:ident count:[PRStatusApps ncCount:ident]]; // update with NC data
            else
            {
                [PRStatusApps hideIconFor:ident];
            }
        }
        else
        {
            [PRStatusApps hideIconFor:ident];
        }
    }

    return badgeCount;
}
%end
*/

%hook SpringBoard
//- (void)_performDeferredLaunchWork;
-(void)applicationDidFinishLaunching:(id)application
{
    %orig;

    CHECK_ENABLED();
    [PRStatusApps reloadAllImages];
    //[PRStatusApps performSelectorInBackground:@selector(reloadAllImages) withObject:nil];
}
%end

BOOL hasLoaded = NO;
%hook SBLockStateAggregator
-(void)_updateLockState
{
    %orig;
    if (![self hasAnyLockState]) 
    {
        if (!hasLoaded)
        {
            //[PRStatusApps reloadAllImages];
            hasLoaded = YES;
        }
        //enableFix = YES;
    }
    //enableFix = NO;
}
%end

%ctor
{
	if (strcmp(__progname, "filecoordinationd") == 0 || strcmp(__progname, "securityd") == 0)
		return;

    @autoreleasepool {
        if ([NSFileManager.defaultManager fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/libstatusbar8.dylib"]) // Old, not used anymore. In here for "compatibility". 
            dlopen("/Library/MobileSubstrate/DynamicLibraries/libstatusbar8.dylib", RTLD_NOW | RTLD_GLOBAL);
        else if ([NSFileManager.defaultManager fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/libstatusbar.dylib"])
            dlopen("/Library/MobileSubstrate/DynamicLibraries/libstatusbar.dylib", RTLD_NOW | RTLD_GLOBAL);
        else
            [NSException raise:NSInternalInconsistencyException format:@"Protean: neither libstatusbar8 nor libstatusbar were found"];  

        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/bars.dylib"])
            dlopen("/Library/MobileSubstrate/DynamicLibraries/bars.dylib", RTLD_NOW | RTLD_GLOBAL);

        %init;
	    if (!LIBSTATUSBAR8)
	    	%init(NOT_LIBSTATUSBAR8);
        else
            if ([%c(LibStatusBar8) respondsToSelector:@selector(addExtension:identifier:version:)])
                [%c(LibStatusBar8) addExtension:@"Protean" identifier:@"com.efrederickson.protean" version:PROTEAN_VERSION];
    }

    // Load vectors & update statistics
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.apple.springboard"])
    {
        NSString *vectorPath = @"/Library/Protean/Vectors";
        NSString *transformedPath = @"/Library/Protean/TranslatedVectors~cache/"; // WAS: /tmp/protean
        [NSFileManager.defaultManager createDirectoryAtPath:transformedPath withIntermediateDirectories:YES attributes:nil error:nil];

        NSMutableArray *vectorCache = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:transformedPath error:nil] mutableCopy]; // for purging old images

        for (NSString *vectorFile in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:vectorPath error:nil])
        {
            NSString *filePath = nil;
            if (UIScreen.mainScreen.scale > 1)
                filePath = [NSString stringWithFormat:@"%@/PR_%@@%.0fx.png",transformedPath,[vectorFile stringByDeletingPathExtension], UIScreen.mainScreen.scale];
            else
                filePath = [NSString stringWithFormat:@"%@/PR_%@.png",transformedPath,[vectorFile stringByDeletingPathExtension]];

            if ([NSFileManager.defaultManager fileExistsAtPath:filePath])
            {
	            if (UIScreen.mainScreen.scale > 1)
	                [vectorCache removeObject:[NSString stringWithFormat:@"PR_%@@%.0fx.png",[vectorFile stringByDeletingPathExtension], UIScreen.mainScreen.scale]];
	            else
	                [vectorCache removeObject:[NSString stringWithFormat:@"PR_%@.png",[vectorFile stringByDeletingPathExtension]]];
                continue;
            }

            PDFImage *vector = [PDFImage imageWithContentsOfFile:[NSString stringWithFormat:@"%@/%@",vectorPath,vectorFile]];
            if (vector)
            {
                CGSize size = vector.size;
                CGFloat scale = 10 / size.height;
                size.height *= scale;
                size.width *= scale;

                PDFImageOptions *vOptions = [PDFImageOptions optionsWithSize:size];
                vOptions.scale = UIScreen.mainScreen.scale;
                
                UIImage *transformedImage = [vector imageWithOptions:vOptions];
                [UIImagePNGRepresentation(transformedImage) writeToFile:filePath atomically:YES];
            }
        }

        for (NSString *artifact in vectorCache)
        {
        	[NSFileManager.defaultManager removeItemAtPath:[NSString stringWithFormat:@"%@/%@",transformedPath,artifact] error:nil];
        }

        // statistics
        dispatch_async(dispatch_get_main_queue(), ^(void){
    	    // Check statistics
    	    NSString *statsPath = @"/User/Library/Preferences/.protean.stats_checked";
    	    if ([NSFileManager.defaultManager fileExistsAtPath:statsPath] == NO)
    	    {
    		    NSString *udid = (__bridge NSString*)MGCopyAnswer(CFSTR("UniqueDeviceID"));
    		    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://elijahandandrew.com/protean/stats.php?udid=%@", udid]] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60.0];
    		    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
    		    	NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
      				int code = [httpResponse statusCode];
    		        if (error == nil && (code == 0 || code == 200))
    		        {
    		        	[NSFileManager.defaultManager createFileAtPath:statsPath contents:[NSData new] attributes:nil];
    		        }
    		    }];
    		}
        });
    }

}

#import "PRStatusApps.h"
#import <libstatusbar/LSStatusBarItem.h>
#import <objc/runtime.h>
#import "Protean.h"
#import <flipswitch/Flipswitch.h>

NSMutableDictionary *icons = [NSMutableDictionary dictionary];
NSMutableDictionary *cachedBadgeCounts = [NSMutableDictionary dictionary];
NSMutableDictionary *ncData = [NSMutableDictionary dictionary];
NSMutableArray *spacers = [NSMutableArray array];

inline int bestCountForApp(NSString *ident, int otherCount = 0)
{
    if (ident == nil) return 0;

    int NC = [ncData[ident] intValue];
    int badge = [cachedBadgeCounts[ident] intValue];
    return MAX(MAX(NC, badge), otherCount);
}

@implementation PRStatusApps
+(StatusBarAlignment) getDefaultAlignment
{
    id right_ = [Protean getOrLoadSettings][@"defaultAlignToRight"];
    if (!right_ || [right_ boolValue] == NO)
        return StatusBarAlignmentLeft;
    else
        return StatusBarAlignmentRight;
}
+(StatusBarAlignment) getDefaultAlignment:(NSString*)ident
{
    id right_ = [Protean getOrLoadSettings][@"defaultAlignToRight"];
    if (!right_ || [right_ boolValue] == NO)
        return StatusBarAlignmentLeft;
    else
        return StatusBarAlignmentRight;
}

+(LSStatusBarItem*)getOrCreateItemForIdentifier:(NSString*)identifier
{
    if (identifier == nil) return nil;

    if (icons[identifier])
        return icons[identifier];

    if (objc_getClass("LSStatusBarItem") == nil)
        return nil;
    
    LSStatusBarItem *item = [[objc_getClass("LSStatusBarItem") alloc] initWithIdentifier:[NSString stringWithFormat:@"%@%@", @"com.efrederickson.protean-",identifier] alignment:[PRStatusApps getDefaultAlignment:identifier]];

    if (!item)
        return nil;
    
    icons[identifier] = item;
    return icons[identifier];
}

+(void) showIconFor:(NSString*)identifier badgeCount:(int)count
{
    @autoreleasepool { 
        CHECK_ENABLED();
        if (identifier == nil)
            return;
        
        NSString *imageName = [Protean imageNameForIdentifier:identifier withBadgeCount:bestCountForApp(identifier, count)];
        if (imageName == nil || [imageName isEqual:@""])
            return;
        
        LSStatusBarItem *item = [PRStatusApps getOrCreateItemForIdentifier:identifier];
        if (!item)
            return;
        item.visible = YES;
        item.imageName = imageName;
    }
}

+(void) updateCachedBadgeCount:(NSString*)identifier count:(int) count
{
    cachedBadgeCounts[identifier] = [NSNumber numberWithInt:count];
    //badgeCount += count;
    [PRStatusApps updateTotalNotificationCountIcon];
}

+(void) hideIconFor:(NSString*)identifier
{
    if (icons[identifier] == nil || identifier == nil)
        return;
    
    LSStatusBarItem *item = [PRStatusApps getOrCreateItemForIdentifier:identifier];
    if (!item)
        return;

    item.visible = NO;
    item.imageName = @"";
    item = nil;
    [icons removeObjectForKey:identifier];
}

+(void) showIconForFlipswitch:(NSString*)identifier
{
    CHECK_ENABLED();
    if (identifier == nil)
        return;
    
    LSStatusBarItem *item = [PRStatusApps getOrCreateItemForIdentifier:identifier];
    if (!item)
        return;

    item.visible = YES;
    NSString *imageName = [Protean imageNameForIdentifier:identifier] ?: identifier;
    
    item.imageName = [imageName isEqual:@""] ? identifier : imageName;
}

+(void) showIconForBluetooth:(NSString*)identifier
{
    CHECK_ENABLED();
    if (identifier == nil)
        return;
    
    if ([Protean imageNameForIdentifier:identifier] == nil || [[Protean imageNameForIdentifier:identifier] isEqual:@""])
        return;
    
    LSStatusBarItem *item = [PRStatusApps getOrCreateItemForIdentifier:identifier];
    if (!item)
        return;
    item.visible = YES;
    item.imageName = [Protean imageNameForIdentifier:identifier];
}

+(void) updateSpacers
{
    id num_ = [Protean getOrLoadSettings][@"numSpacers"];
    int num = num_ ? [num_ intValue] : 0;
    if (spacers.count != num)
        [spacers removeAllObjects];
    for (int i = 0; i < num; i++)
    {
        if (i < spacers.count)
            continue;
        LSStatusBarItem *spacer = [[objc_getClass("LSStatusBarItem") alloc] initWithIdentifier:[NSString stringWithFormat:@"spacer-%d",i] alignment:[PRStatusApps getDefaultAlignment]];
        spacer.imageName = @"_spacer_";
        spacer.visible = YES;
        if (spacer.customViewClass == nil)
            [spacer setCustomViewClass:@"UIStatusBarSpacerItemView"];

        /* What in the world, libstatusbar */
        NSMutableDictionary *d = [spacer.properties mutableCopy];
        d[@"visible"] = @YES;
        [spacer _setProperties:d];
        [spacer update];

        [spacers addObject:spacer];
    }
}

+(void) reloadAllImages
{
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.apple.springboard"] == NO)
        return;

    id _enabled = [Protean getOrLoadSettings][@"enabled"];
    if ((_enabled ? [_enabled boolValue] : YES) == NO)
    {
        if (icons)
            for (id key in icons.allKeys)
                [PRStatusApps hideIconFor:key];
        return;
    }

    [PRStatusApps updateSpacers];
       
    // Status Apps
    NSArray *appIcons = [[[objc_getClass("SBIconViewMap") homescreenMap] iconModel] visibleIconIdentifiers];
    for (NSString *identifier in appIcons) {
        SBApplication *app = [[objc_getClass("SBApplicationController") sharedInstance] applicationWithBundleIdentifier:identifier];
        [app setBadge:app.badgeNumberOrString];
    }

    if (icons)
    {
        for (NSString* key in icons.allKeys)
        {
            LSStatusBarItem *item = ((LSStatusBarItem*)icons[key]);
            if (!item)
                continue;

            if ([cachedBadgeCounts.allKeys containsObject:key])
                item.imageName = [Protean imageNameForIdentifier:key withBadgeCount:bestCountForApp(key)] ?: key;
            else
                item.imageName = [Protean imageNameForIdentifier:key] ?: key;
            
            if (cachedBadgeCounts[key] && [cachedBadgeCounts[key] intValue] > 0)
                item.visible = YES;
            
            if (item.imageName == nil || [item.imageName isEqual:@""])
            {
                [PRStatusApps hideIconFor:key];
            }
        }
    }
 
    NSDictionary *tmpData = [ncData copy];
    for (NSString *key in tmpData)
        [PRStatusApps updateNCStatsForIcon:key count:[tmpData[key] intValue]];

    [PRStatusApps updateTotalNotificationCountIcon];
    
    // Flipswitches
    for (id key in [Protean getOrLoadSettings][@"flipswitches"])
    {
        [[FSSwitchPanel sharedPanel] stateForSwitchIdentifier:key];
    }
    
    // Bluetooth
    id bt = objc_getClass("BluetoothManager");
    if (bt)
    	[[bt sharedInstance] _connectedStatusChanged];
}

+(void) updateTotalNotificationCountIcon
{
	int totalBadgeCount = [[cachedBadgeCounts.allValues valueForKeyPath:@"@sum.self"] intValue];
    if (totalBadgeCount > 0)
    {
        [PRStatusApps showIconFor:@"TOTAL_NOTIFICATION_COUNT" badgeCount:totalBadgeCount];
    }
    else
    {
        [PRStatusApps hideIconFor:@"TOTAL_NOTIFICATION_COUNT"];
    }
}

+(void) updateNCStatsForIcon:(NSString*)section count:(int)count
{
    if (section == nil || section.length == 0) return;
    if (count < 0) count = 0;
    
    //NSLog(@"[Protean] updating nc stats for icon %@", section);
    ncData[section] = @(count);

    id nc_ = [Protean getOrLoadSettings][@"useNC"];
    if (nc_ && [nc_ boolValue] == NO)
        return;

    if (count > 0)
    {
        //NSLog(@"[Protean] showing NC icon for %@", section);
        [PRStatusApps showIconFor:section badgeCount:count];
    }
    else
    {
        //NSLog(@"[Protean] not showing NC icon for %@", section);
        if ([cachedBadgeCounts[section] intValue] < 1)
            [PRStatusApps hideIconFor:section];
        else
            [PRStatusApps showIconFor:section badgeCount:[cachedBadgeCounts[section] intValue]];
    }
}

+(int) ncCount:(NSString*)identifier
{
    return [ncData.allKeys containsObject:identifier] ? [ncData[identifier] intValue] : 0;
}
@end


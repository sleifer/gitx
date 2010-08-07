//
//  NSDate_Fuzzy.h
//  GitX
//
//  Created by Nathan Hoad on 7/08/10.
//  Copyright 2010 Nathan Hoad .net. All rights reserved.
//

#import <Cocoa/Cocoa.h>


#define MINUTE (60)
#define HOUR (60 * MINUTE)
#define DAY (24 * HOUR)
#define MONTH (30 * DAY)


@interface NSDate (Fuzzy)

- (NSString *)distanceOfTimeInWordsFromNow;

@end

//
//  NSDate_Fuzzy.m
//  GitX
//
//  Created by Nathan Hoad on 7/08/10.
//  Copyright 2010 Nathan Hoad .net. All rights reserved.
//

#import "NSDate_Fuzzy.h"


@implementation NSDate (Fuzzy)


- (NSString *)distanceOfTimeInWordsFromNow
{
	NSTimeInterval t = (int)abs([self timeIntervalSinceDate:[NSDate date]]);
	
	if (t < 1 * MINUTE) {
		return @"less than a minute ago";
	}
	if (t < 50 * MINUTE) {
		return [NSString stringWithFormat:@"%.0f minutes ago", round(t / MINUTE)];
	}
	if (t < 90 * MINUTE) {
		return @"about an hour ago";
	}
	if (t < 18 * HOUR) {
		return [NSString stringWithFormat:@"%.0f hours ago", round(t / HOUR)];
	}
	if (t < 2 * DAY) {
		return @"about a day";
	}
	if (t < 20 * DAY) {
		return [NSString stringWithFormat:@"%.0f days ago", round(t / DAY)];
	}
	if (t < 1 * MONTH) {
		return @"about a month ago";
	}
	
	NSDateFormatter* formatter = [[NSDateFormatter alloc] initWithDateFormat:@"%d %b, %Y %I:%M %p" allowNaturalLanguage:NO];
	return [formatter stringFromDate: self];
}


@end

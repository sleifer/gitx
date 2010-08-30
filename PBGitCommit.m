//
//  PBGitCommit.m
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitCommit.h"
#import "PBGitSHA.h"
#import "PBGitDefaults.h"

#import "NSDate_Fuzzy.h"
#import "NSString_RegEx.h"


NSString * const kGitXCommitType = @"commit";


@implementation PBGitCommit

@synthesize repository, subject, body, timestamp, author, sign, lineInfo;
@synthesize svnRevision;
@synthesize sha;
@synthesize parents;
@synthesize committer;


- (NSString*)svnRevision
{
	if (svnRevision == nil && body != nil) {
		NSRange tagRange = [body rangeOfString:@"git-svn-id:"];
		if (tagRange.location != NSNotFound) {
			NSRange atRange = [body rangeOfString:@"@" options:0 range:NSMakeRange (tagRange.location, [body length] - tagRange.location)];
			NSRange spaceRange = [body rangeOfString:@" " options:0 range:NSMakeRange (atRange.location, [body length] - atRange.location)];
			svnRevision = [body substringWithRange:NSMakeRange (atRange.location + 1, spaceRange.location - atRange.location - 1)];
		}
	}
	
	return svnRevision;
}

- (NSDate *)date
{
    return [NSDate dateWithTimeIntervalSince1970:timestamp];
}

- (NSString *) dateString
{
	if ([PBGitDefaults useRelativeDates] == YES) {
		return [self.date distanceOfTimeInWordsFromNow];
	} else {
		NSDateFormatter* formatter = [[NSDateFormatter alloc] initWithDateFormat:@"%d %b, %Y %I:%M %p" allowNaturalLanguage:NO];
		return [formatter stringFromDate:self.date];
	}
}

- (NSArray*) treeContents
{
    return self.tree.children;
}

+ (PBGitCommit *)commitWithRepository:(PBGitRepository*)repo andSha:(PBGitSHA *)newSha
{
    return [[self alloc] initWithRepository:repo andSha:newSha];
}

- (id)initWithRepository:(PBGitRepository*) repo andSha:(PBGitSHA *)newSha
{
    details = nil;
    repository = repo;
    sha = newSha;
    return self;
}

- (NSString *)realSha
{
    return sha.string;
}

- (BOOL) isOnSameBranchAs:(PBGitCommit *)otherCommit
{
    if (!otherCommit)
        return NO;

    if ([self isEqual:otherCommit])
        return YES;

    return [repository isOnSameBranch:otherCommit.sha asSHA:self.sha];
}

- (BOOL) isOnHeadBranch
{
    return [self isOnSameBranchAs:[repository headCommit]];
}

- (BOOL)isEqual:(id)otherCommit
{
    if (self == otherCommit)
        return YES;

    if (![otherCommit isMemberOfClass:[PBGitCommit class]])
        return NO;

    return [self.sha isEqual:[(PBGitCommit *)otherCommit sha]];
}

- (NSUInteger)hash
{
    return [self.sha hash];
}

- (void)extractRadarsFromString:(NSString*)src intoArray:(NSMutableArray*)results
{
	NSCharacterSet *numbers = [NSCharacterSet decimalDigitCharacterSet];
	NSRange firstRange = [src rangeOfCharacterFromSet:numbers options:0];
	NSRange lastRange = [src rangeOfCharacterFromSet:numbers options:NSBackwardsSearch];
	NSString *coreString = [src substringWithRange:NSMakeRange(firstRange.location, lastRange.location - firstRange.location + 1)];
	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@", &"];
	NSArray *items = [coreString componentsSeparatedByCharactersInSet:separators];
	NSString *oneItem;
	for (oneItem in items) {
		if ([oneItem length] > 0) {
			[results addObject:oneItem];
		}
	}
}

/*
Valid bug reference forms:
rdar://3000001
rdar://problem/3000002
rdar://problems/3000003&3000004
radar:3000005
radar:bug?id=3000006
radar:bug?id=3000007&3000008
rdar://problem/3000009&3000010
rdar://3000011&3000012
[3000013]
[3000014,3000015, 3000016]
*/

- (NSArray*)referencedRadars
{
	NSMutableArray *results = [[NSMutableArray alloc] init];
	NSString *testStr;
    NSArray *match;
	NSArray *ranges;
	NSError *error;
	
	testStr = self.subject;
	
	while (YES) {
		match = nil;
		ranges = nil;
		error = nil;
		
		match = [testStr substringsMatchingRegularExpression:@"[<]?(rdar:\\/\\/problems\\/|rdar:\\/\\/problem\\/|rdar:\\/\\/|radar:bug\\?id=|radar:)([0-9]+)(&([0-9]+))*[>]?" count:20 options:0 ranges:&ranges error:&error];
		
		if (match) {
			[self extractRadarsFromString:[match objectAtIndex:0] intoArray:results];
			NSRange range = [[ranges objectAtIndex:0] rangeValue];
			testStr = [testStr substringFromIndex:range.location + range.length];
		} else {
			break;
		}
	}
	
	testStr = self.subject;
	
	while (YES) {
		match = nil;
		ranges = nil;
		error = nil;
		
		match = [testStr substringsMatchingRegularExpression:@"\\[([0-9]+)(,[ ]?([0-9]+))*\\]" count:20 options:0 ranges:&ranges error:&error];
		
		if (match) {
			[self extractRadarsFromString:[match objectAtIndex:0] intoArray:results];
			NSRange range = [[ranges objectAtIndex:0] rangeValue];
			testStr = [testStr substringFromIndex:range.location + range.length];
		} else {
			break;
		}
	}
	
	return results;
}

- (NSString*)referencedRadarsLink
{
	NSArray *radarNumbers = [self referencedRadars];
	
	if (radarNumbers == nil || [radarNumbers count] == 0) {
		return nil;
	}
	
	NSString *link = [NSString stringWithFormat:@"rdar://%@", [radarNumbers componentsJoinedByString:@"&"]];
	return link;
}

+ (NSArray*)testReferencedRadars
{
	PBGitCommit *testObj = [[PBGitCommit alloc] initWithRepository:nil andSha:nil];
	
	testObj.subject = @"Alpha rdar://3000001 Bravo <rdar://problem/3000002> Charlie rdar://problems/3000003&3000004 Delta radar:3000005 Echo <radar:bug?id=3000006>\nFoxtrot <radar:bug?id=3000007&3000008> Hotel rdar://problem/3000009&3000010 India <rdar://3000011&3000012&3000013> Juliet [3000014] Kilo [3000015,3000016, 3000017]";
	
	NSArray *bugs = [testObj referencedRadars];
	
	return bugs;
}

// FIXME: Remove this method once it's unused.
- (NSString*) details
{
    return @"";
}

- (NSString *) patch
{
    if (_patch != nil)
        return _patch;

    NSString *p = [repository outputForArguments:[NSArray arrayWithObjects:@"format-patch",  @"-1", @"--stdout", [self realSha], nil]];
    // Add a GitX identifier to the patch ;)
    _patch = [[p substringToIndex:[p length] -1] stringByAppendingString:@"+GitX"];
    return _patch;
}

- (PBGitTree*) tree
{
    return [PBGitTree rootForCommit: self];
}

- (void)addRef:(PBGitRef *)ref
{
    if (!self.refs)
        self.refs = [NSMutableArray arrayWithObject:ref];
    else
        [self.refs addObject:ref];
}

- (void)removeRef:(id)ref
{
    if (!self.refs)
        return;

    [self.refs removeObject:ref];
}

- (BOOL) hasRef:(PBGitRef *)ref
{
    if (!self.refs)
        return NO;

    for (PBGitRef *existingRef in self.refs)
        if ([existingRef isEqualToRef:ref])
            return YES;

    return NO;
}

- (NSMutableArray *)refs
{
    return [[repository refs] objectForKey:[self sha]];
}

- (void) setRefs:(NSMutableArray *)refs
{
    [[repository refs] setObject:refs forKey:[self sha]];
}

- (void)finalize
{
    [super finalize];
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
    return NO;
}

+ (BOOL)isKeyExcludedFromWebScript:(const char *)name {
    return NO;
}


#pragma mark <PBGitRefish>

- (NSString *) refishName
{
    return [self realSha];
}

- (NSString *) shortName
{
    return [[self realSha] substringToIndex:10];
}

- (NSString *) refishType
{
    return kGitXCommitType;
}

@end

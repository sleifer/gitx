//
//  PBCLIProxy.m
//  GitX
//
//  Created by Ciarán Walsh on 15/08/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBCLIProxy.h"
#import "PBRepositoryDocumentController.h"
#import "PBGitRevSpecifier.h"
#import "PBGitRepository.h"
#import "PBGitWindowController.h"
#import "PBGitSidebarController.h"
#import "PBGitBinary.h"
#import "PBDiffWindowController.h"
#import "PBGitHistoryController.h"

@implementation PBCLIProxy
@synthesize connection;

- (id)init
{
    if (self = [super init]) {
        self.connection = [NSConnection new];
        [self.connection setRootObject:self];

        if ([self.connection registerName:ConnectionName] == NO)
            NSBeep();

    }
    return self;
}

- (BOOL)openRepository:(NSURL*)repositoryPath arguments: (NSArray*) args error:(NSError**)error;
{
    // FIXME I found that creating this redundant NSURL reference was necessary to
    // work around an apparent bug with GC and Distributed Objects
    // I am not familiar with GC though, so perhaps I was doing something wrong.
    NSURL* url = [NSURL fileURLWithPath:[repositoryPath path]];
    NSMutableArray* arguments = [NSMutableArray arrayWithArray:args];

    PBGitRepository *document = nil;
	@try {
		document = [[PBRepositoryDocumentController sharedDocumentController] documentForLocation:url];
	}
	@catch (NSException *e) {}
    if (!document) {
        if (error) {
            NSString *suggestion = [PBGitBinary path] ? @"this isn't a git repository" : @"GitX can't find your git binary";

            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Could not create document. Perhaps %@", suggestion]
                                                                 forKey:NSLocalizedFailureReasonErrorKey];

            *error = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:2 userInfo:userInfo];
        }
        return NO;
    }

    if ([arguments count] > 0 && ([[arguments objectAtIndex:0] isEqualToString:@"--commit"] ||
        [[arguments objectAtIndex:0] isEqualToString:@"-c"]))
        [document.windowController showCommitView:self];
    else {
		BOOL blame = NO;
		if ([arguments containsObject:@"--blame"]) {
			blame = YES;
			[arguments removeObject:@"--blame"];
		}
		
        PBGitRevSpecifier* rev = [[PBGitRevSpecifier alloc] initWithParameters:arguments];
        rev.workingDirectory = url;
        document.currentBranch = [document addBranch: rev];
        [document.windowController showHistoryView:self];
		
		PBGitHistoryController *historyController = document.windowController.sidebarController.historyViewController;
		
		if ([rev.parameters count] > 1 && [rev.parameters containsObject:@"--"]) {
			NSUInteger index = [rev.parameters indexOfObject:@"--"];
			if ([rev.parameters count] > (index + 1)) {
				NSString *firstPath = [rev.parameters objectAtIndex:index + 1];
				historyController.currentFileBrowserSelectionPath = [NSArray arrayWithObject:firstPath];
				[historyController restoreFileBrowserSelection];
			}
		}
		if (blame) {
			[historyController setBlameView:self];
		} else {
			[historyController setDetailedView:self];
		}

    }
    [NSApp activateIgnoringOtherApps:YES];

    return YES;
}

- (void)openDiffWindowWithDiff:(NSString *)diff
{
    PBDiffWindowController *diffController = [[PBDiffWindowController alloc] initWithDiff:[diff copy]];
    [diffController showWindow:nil];
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}
@end

//
//  PBWebBlameController.h
//  GitTest
//
//  Created by Simeon Leifer 24-Aug-2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PBWebController.h"

#import "PBGitTree.h"
#import "PBGitHistoryController.h"
#import "PBRefContextDelegate.h"


@interface PBWebBlameController : PBWebController {
    IBOutlet PBGitHistoryController* historyController;
    IBOutlet id<PBRefContextDelegate> contextMenuDelegate;

    NSString* currentSha;
    NSString* currentRef;
    NSString* currentPath;
    NSString* blame;
}

- (void)changeContentTo:(PBGitTree*)content atCommit:(PBGitCommit*)commit;
- (void) sendKey: (NSString*) key;

@property (readonly) NSString* blame;
@end

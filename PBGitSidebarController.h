//
//  PBGitSidebar.h
//  GitX
//
//  Created by Pieter de Bie on 9/8/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PBViewController.h"

@class PBSourceViewItem;
@class PBGitHistoryController;
@class PBGitCommitController;

@interface PBGitSidebarController : PBViewController {
    IBOutlet NSWindow *window;
    IBOutlet NSOutlineView *sourceView;
    IBOutlet NSView *sourceListControlsView;
    IBOutlet NSPopUpButton *actionButton;
    IBOutlet NSSegmentedControl *remoteControls;

    NSMutableArray *items;

    /* Specific things */
    PBSourceViewItem *stage;

    PBSourceViewItem *branches, *remotes, *tags, *others;

    PBGitHistoryController *historyViewController;
    PBGitCommitController *commitViewController;
}

- (void) selectStage;
- (void) selectCurrentBranch;

- (NSMenu *) menuForRow:(NSInteger)row;

- (IBAction) fetchPullPushAction:(id)sender;

@property(readonly) NSMutableArray *items;
@property(readonly) NSView *sourceListControlsView;
@property(readonly) PBGitHistoryController *historyViewController;
@property(readonly) PBGitCommitController *commitViewController;

@end

//
//  PBGitHistoryView.h
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PBGitCommit.h"
#import "PBGitTree.h"
#import "PBViewController.h"
#import "PBCollapsibleSplitView.h"

@class PBGitSidebarController;
@class PBWebHistoryController;
@class PBWebBlameController;
@class PBGitGradientBarView;
@class PBRefController;
@class QLPreviewPanel;
@class PBCommitList;
@class PBGitSHA;

@interface PBGitHistoryController : PBViewController {
    IBOutlet PBRefController *refController;
    IBOutlet NSSearchField *searchField;
    IBOutlet NSArrayController* commitController;
    IBOutlet NSTreeController* treeController;
    IBOutlet NSOutlineView* fileBrowser;
    NSArray *currentFileBrowserSelectionPath;
    IBOutlet PBCommitList* commitList;
    IBOutlet PBCollapsibleSplitView *historySplitView;
    IBOutlet PBWebHistoryController *webHistoryController;
    IBOutlet PBWebBlameController *webBlameController;
    QLPreviewPanel* previewPanel;

    IBOutlet PBGitGradientBarView *upperToolbarView;
    IBOutlet NSButton *mergeButton;
    IBOutlet NSButton *cherryPickButton;
    IBOutlet NSButton *rebaseButton;

    IBOutlet PBGitGradientBarView *scopeBarView;
    IBOutlet NSButton *allBranchesFilterItem;
    IBOutlet NSButton *localRemoteBranchesFilterItem;
    IBOutlet NSButton *selectedBranchFilterItem;
	
	IBOutlet NSTabView *detailTreeTabView;
	IBOutlet NSTabView *contentBlameTabView;
    IBOutlet id webView;
    IBOutlet id blameWebView;
    int selectedCommitDetailsIndex;
    BOOL forceSelectionUpdate;

    PBGitTree *gitTree;
    PBGitCommit *webCommit;
    PBGitCommit *selectedCommit;
	NSArray *lastSearchSelection;
}

@property (assign) int selectedCommitDetailsIndex;
@property (retain) PBGitCommit *webCommit;
@property (retain) PBGitTree* gitTree;
@property (readonly) NSArrayController *commitController;
@property (readonly) PBRefController *refController;
@property (retain) NSArray *lastSearchSelection;
@property (retain) NSArray *currentFileBrowserSelectionPath;

- (IBAction) setDetailedView:(id)sender;
- (IBAction) setTreeView:(id)sender;
- (IBAction) setBlameView:(id)sender;
- (IBAction) setBranchFilter:(id)sender;

- (void)selectCommit:(PBGitSHA *)commit;
- (IBAction) refresh:(id)sender;
- (IBAction) toggleQLPreviewPanel:(id)sender;
- (IBAction) openSelectedFile:(id)sender;
- (void) updateQuicklookForce: (BOOL) force;
- (void) updateBlame;

// Context menu methods
- (NSMenu *)contextMenuForTreeView;
- (NSArray *)menuItemsForPaths:(NSArray *)paths addSeparator:(BOOL)addSeparator;
- (void)showCommitsFromTree:(id)sender;
- (void)showBlameFromTree:(id)sender;
- (void)showInFinderAction:(id)sender;
- (void)openFilesAction:(id)sender;

// Repository Methods
- (IBAction) createBranch:(id)sender;
- (IBAction) createTag:(id)sender;
- (IBAction) showAddRemoteSheet:(id)sender;
- (IBAction) merge:(id)sender;
- (IBAction) cherryPick:(id)sender;
- (IBAction) rebase:(id)sender;

- (void) copyCommitInfo;
- (void) copyCommitSHA;

- (BOOL) hasNonlinearPath;

- (NSMenu *)tableColumnMenu;

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview;
- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex;
- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset;
- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset;

- (void) restoreFileBrowserSelection;

@end

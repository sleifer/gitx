//
//  PBGitHistoryView.m
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitHistoryController.h"
#import "PBWebHistoryController.h"
#import "PBWebBlameController.h"
#import "CWQuickLook.h"
#import "PBGitGrapher.h"
#import "PBGitRevisionCell.h"
#import "PBCommitList.h"
#import "PBCreateBranchSheet.h"
#import "PBCreateTagSheet.h"
#import "PBAddRemoteSheet.h"
#import "PBGitSidebarController.h"
#import "PBGitGradientBarView.h"
#import "PBDiffWindowController.h"
#import "PBGitDefaults.h"
#import "PBGitRevList.h"
#define QLPreviewPanel NSClassFromString(@"QLPreviewPanel")


#define kHistorySelectedDetailIndexKey @"PBHistorySelectedDetailIndex"
#define kHistoryDetailViewIndex 0
#define kHistoryTreeViewIndex 1
#define kHistoryBlameViewIndex 2

@interface PBGitHistoryController ()

- (void) updateBranchFilterMatrix;
- (void) restoreFileBrowserSelection;
- (void) saveFileBrowserSelection;

@end


@implementation PBGitHistoryController
@synthesize selectedCommitDetailsIndex, webCommit, gitTree, commitController, refController;

- (void)awakeFromNib
{
    self.selectedCommitDetailsIndex = [[NSUserDefaults standardUserDefaults] integerForKey:kHistorySelectedDetailIndexKey];
	
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:@"values.PBUseRelativeDates" options:NSKeyValueObservingOptionNew context:@"relativeDates"];
    [commitController addObserver:self forKeyPath:@"selection" options:0 context:@"commitChange"];
    [commitController addObserver:self forKeyPath:@"arrangedObjects.@count" options:NSKeyValueObservingOptionInitial context:@"updateCommitCount"];
    [treeController addObserver:self forKeyPath:@"selection" options:0 context:@"treeChange"];

    [repository.revisionList addObserver:self forKeyPath:@"isUpdating" options:0 context:@"revisionListUpdating"];
    [repository addObserver:self forKeyPath:@"currentBranch" options:0 context:@"branchChange"];
    [repository addObserver:self forKeyPath:@"refs" options:0 context:@"updateRefs"];

    forceSelectionUpdate = YES;
    NSSize cellSpacing = [commitList intercellSpacing];
    cellSpacing.height = 0;
    [commitList setIntercellSpacing:cellSpacing];
    [fileBrowser setTarget:self];
    [fileBrowser setDoubleAction:@selector(openSelectedFile:)];

    if (!repository.currentBranch) {
        [repository reloadRefs];
        [repository readCurrentBranch];
    }
    else
        [repository lazyReload];

    // Set a sort descriptor for the subject column in the history list, as
    // It can't be sorted by default (because it's bound to a PBGitCommit)
    [[commitList tableColumnWithIdentifier:@"subject"] setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"subject" ascending:YES]];
    // Add a menu that allows a user to select which columns to view
    [[commitList headerView] setMenu:[self tableColumnMenu]];
    [historySplitView setTopMin:58.0 andBottomMin:100.0];
    [historySplitView uncollapse];

    [upperToolbarView setTopShade:237/255.0 bottomShade:216/255.0];
    [scopeBarView setTopColor:[NSColor colorWithCalibratedHue:0.579 saturation:0.068 brightness:0.898 alpha:1.000]
                  bottomColor:[NSColor colorWithCalibratedHue:0.579 saturation:0.119 brightness:0.765 alpha:1.000]];
    //[scopeBarView setTopShade:207/255.0 bottomShade:180/255.0];
    [self updateBranchFilterMatrix];

    [super awakeFromNib];
}

- (void)updateKeys
{
    PBGitCommit *lastObject = [[commitController selectedObjects] lastObject];
    if (lastObject) {
        if (![selectedCommit isEqual:lastObject]) {
            selectedCommit = lastObject;

            BOOL isOnHeadBranch = [selectedCommit isOnHeadBranch];
            [mergeButton setEnabled:!isOnHeadBranch];
            [cherryPickButton setEnabled:!isOnHeadBranch];
            [rebaseButton setEnabled:!isOnHeadBranch];
        }
    }
    else {
        [mergeButton setEnabled:NO];
        [cherryPickButton setEnabled:NO];
        [rebaseButton setEnabled:NO];
    }

    if (self.selectedCommitDetailsIndex == kHistoryTreeViewIndex) {
        self.gitTree = selectedCommit.tree;
        [self restoreFileBrowserSelection];
    } else if (self.selectedCommitDetailsIndex == kHistoryBlameViewIndex) {
        self.gitTree = selectedCommit.tree;
        [self restoreFileBrowserSelection];
    }
    else {
        // kHistoryDetailViewIndex
        if (![self.webCommit isEqual:selectedCommit])
        self.webCommit = selectedCommit;
    }
}

- (void) updateBranchFilterMatrix
{
    if ([repository.currentBranch isSimpleRef]) {
        [allBranchesFilterItem setEnabled:YES];
        [localRemoteBranchesFilterItem setEnabled:YES];

        NSInteger filter = repository.currentBranchFilter;
        [allBranchesFilterItem setState:(filter == kGitXAllBranchesFilter)];
        [localRemoteBranchesFilterItem setState:(filter == kGitXLocalRemoteBranchesFilter)];
        [selectedBranchFilterItem setState:(filter == kGitXSelectedBranchFilter)];
    }
    else {
        [allBranchesFilterItem setState:NO];
        [localRemoteBranchesFilterItem setState:NO];

        [allBranchesFilterItem setEnabled:NO];
        [localRemoteBranchesFilterItem setEnabled:NO];

        [selectedBranchFilterItem setState:YES];
    }

    [selectedBranchFilterItem setTitle:[repository.currentBranch title]];
    [selectedBranchFilterItem sizeToFit];

    [localRemoteBranchesFilterItem setTitle:[[repository.currentBranch ref] isRemote] ? @"Remote" : @"Local"];
}

- (PBGitCommit *) firstCommit
{
    NSArray *arrangedObjects = [commitController arrangedObjects];
    if ([arrangedObjects count] > 0)
        return [arrangedObjects objectAtIndex:0];

    return nil;
}

- (BOOL)isCommitSelected
{
    return [selectedCommit isEqual:[[commitController selectedObjects] lastObject]];
}

- (void) setSelectedCommitDetailsIndex:(int)detailsIndex
{
    if (selectedCommitDetailsIndex == detailsIndex)
        return;

    selectedCommitDetailsIndex = detailsIndex;
    [[NSUserDefaults standardUserDefaults] setInteger:selectedCommitDetailsIndex forKey:kHistorySelectedDetailIndexKey];
	
	switch (detailsIndex) {
		case kHistoryDetailViewIndex:
			[detailTreeTabView selectTabViewItemAtIndex:0];
			break;
		case kHistoryTreeViewIndex:
			[detailTreeTabView selectTabViewItemAtIndex:1];
			[contentBlameTabView selectTabViewItemAtIndex:0];
			break;
		case kHistoryBlameViewIndex:
			[detailTreeTabView selectTabViewItemAtIndex:1];
			[contentBlameTabView selectTabViewItemAtIndex:1];
			break;
		default:
			break;
	}
	
    forceSelectionUpdate = YES;
    [self updateKeys];
}

- (void) updateStatus
{
    self.isBusy = repository.revisionList.isUpdating;
    self.status = [NSString stringWithFormat:@"%d commits loaded", [[commitController arrangedObjects] count]];
}

- (void) restoreFileBrowserSelection
{
    if (self.selectedCommitDetailsIndex != kHistoryTreeViewIndex && self.selectedCommitDetailsIndex != kHistoryBlameViewIndex)
        return;

    NSArray *children = [treeController content];
    if ([children count] == 0)
        return;

    NSIndexPath *path = [[NSIndexPath alloc] init];
    if ([currentFileBrowserSelectionPath count] == 0)
        path = [path indexPathByAddingIndex:0];
    else {
        for (NSString *pathComponent in currentFileBrowserSelectionPath) {
            PBGitTree *child = nil;
            NSUInteger childIndex = 0;
            for (child in children) {
                if ([child.path isEqualToString:pathComponent]) {
                    path = [path indexPathByAddingIndex:childIndex];
                    children = child.children;
                    break;
                }
                childIndex++;
            }
            if (!child)
                return;
        }
    }

    [treeController setSelectionIndexPath:path];
}

- (void) saveFileBrowserSelection
{
    NSArray *objects = [treeController selectedObjects];
    NSArray *content = [treeController content];

    if ([objects count] && [content count]) {
        PBGitTree *treeItem = [objects objectAtIndex:0];
        currentFileBrowserSelectionPath = [treeItem.fullPath componentsSeparatedByString:@"/"];
    }
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([(NSString *)context isEqualToString: @"commitChange"]) {
        [self updateKeys];
        [self restoreFileBrowserSelection];
        return;
    }
	
	if ([(NSString*)context isEqualToString:@"relativeDates"]) {
		[commitList reloadData];
		return;
	}

    if ([(NSString *)context isEqualToString: @"treeChange"]) {
		if (self.selectedCommitDetailsIndex == kHistoryTreeViewIndex) {
			[self updateQuicklookForce: NO];
		} else if (self.selectedCommitDetailsIndex == kHistoryBlameViewIndex) {
			[self updateBlame];
		}
        [self saveFileBrowserSelection];
        return;
    }

    if([(NSString *)context isEqualToString:@"branchChange"]) {
        // Reset the sorting
        if ([[commitController sortDescriptors] count])
            [commitController setSortDescriptors:[NSArray array]];
        [self updateBranchFilterMatrix];
        return;
    }

    if([(NSString *)context isEqualToString:@"updateRefs"]) {
        [commitController rearrangeObjects];
        return;
    }

    if([(NSString *)context isEqualToString:@"updateCommitCount"] || [(NSString *)context isEqualToString:@"revisionListUpdating"]) {
        [self updateStatus];

        if ([repository.currentBranch isSimpleRef])
            [self selectCommit:[repository shaForRef:[repository.currentBranch ref]]];
        else
            [self selectCommit:[[self firstCommit] sha]];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (IBAction) openSelectedFile:(id)sender
{
    NSArray* selectedFiles = [treeController selectedObjects];
    if ([selectedFiles count] == 0)
        return;
    PBGitTree* tree = [selectedFiles objectAtIndex:0];
    NSString* name = [tree tmpFileNameForContents];
    [[NSWorkspace sharedWorkspace] openTempFile:name];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if ([menuItem action] == @selector(setDetailedView:)) {
		[menuItem setState:(self.selectedCommitDetailsIndex == kHistoryDetailViewIndex) ? NSOnState : NSOffState];
    } else if ([menuItem action] == @selector(setTreeView:)) {
		[menuItem setState:(self.selectedCommitDetailsIndex == kHistoryTreeViewIndex) ? NSOnState : NSOffState];
    } else if ([menuItem action] == @selector(setBlameView:)) {
		[menuItem setState:(self.selectedCommitDetailsIndex == kHistoryBlameViewIndex) ? NSOnState : NSOffState];
    }
    return YES;
}

- (IBAction) setDetailedView:(id)sender
{
    self.selectedCommitDetailsIndex = kHistoryDetailViewIndex;
    forceSelectionUpdate = YES;
}

- (IBAction) setTreeView:(id)sender
{
    self.selectedCommitDetailsIndex = kHistoryTreeViewIndex;
    forceSelectionUpdate = YES;
}

- (IBAction) setBlameView:(id)sender
{
    self.selectedCommitDetailsIndex = kHistoryBlameViewIndex;
    forceSelectionUpdate = YES;
}

- (IBAction) setBranchFilter:(id)sender
{
    repository.currentBranchFilter = [sender tag];
    [PBGitDefaults setBranchFilter:repository.currentBranchFilter];
    [self updateBranchFilterMatrix];
    forceSelectionUpdate = YES;
}

- (void)keyDown:(NSEvent*)event
{
    if ([[event charactersIgnoringModifiers] isEqualToString: @"f"] && [event modifierFlags] & NSAlternateKeyMask && [event modifierFlags] & NSCommandKeyMask)
        [superController.window makeFirstResponder: searchField];
    else
        [super keyDown: event];
}

- (void) copyCommitInfo
{
    PBGitCommit *commit = [[commitController selectedObjects] lastObject];
    if (!commit)
        return;
    NSString *info = [NSString stringWithFormat:@"%@ (%@)", [[commit realSha] substringToIndex:10], [commit subject]];

    NSPasteboard *a =[NSPasteboard generalPasteboard];
    [a declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
    [a setString:info forType: NSStringPboardType];

}

- (void) copyCommitSHA
{
    PBGitCommit *commit = [[commitController selectedObjects] lastObject];
    if (!commit)
        return;
    NSString *info = [[commit realSha] substringWithRange:NSMakeRange(0, 7)];

    NSPasteboard *a =[NSPasteboard generalPasteboard];
    [a declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
    [a setString:info forType: NSStringPboardType];

}

- (IBAction) toggleQLPreviewPanel:(id)sender
{
    if ([[QLPreviewPanel sharedPreviewPanel] respondsToSelector:@selector(setDataSource:)]) {
        // Public QL API
        if ([QLPreviewPanel sharedPreviewPanelExists] && [[QLPreviewPanel sharedPreviewPanel] isVisible])
            [[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
        else
            [[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFront:nil];
    }
    else {
        // Private QL API (10.5 only)
        if ([[QLPreviewPanel sharedPreviewPanel] isOpen])
            [[QLPreviewPanel sharedPreviewPanel] closePanel];
        else {
            [[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFrontWithEffect:1];
            [self updateQuicklookForce:YES];
        }
    }
}

- (void) updateBlame
{
	NSArray *selection = [treeController selectedObjects];
	if (selection && [selection count] == 1) {
		PBGitTree *item = [selection objectAtIndex:0];
		PBGitCommit *commit = [[commitController selectedObjects] lastObject];
		[webBlameController changeContentTo:item atCommit:commit];
	} else {
		[webBlameController changeContentTo:nil atCommit:nil];
	}
}

- (void) updateQuicklookForce:(BOOL)force
{
    if (!force && ![[QLPreviewPanel sharedPreviewPanel] isOpen])
        return;

    if ([[QLPreviewPanel sharedPreviewPanel] respondsToSelector:@selector(setDataSource:)]) {
        // Public QL API
        [previewPanel reloadData];
    }
    else {
        // Private QL API (10.5 only)
        NSArray *selectedFiles = [treeController selectedObjects];

        NSMutableArray *fileNames = [NSMutableArray array];
        for (PBGitTree *tree in selectedFiles) {
            NSString *filePath = [tree tmpFileNameForContents];
            if (filePath)
                [fileNames addObject:[NSURL fileURLWithPath:filePath]];
        }

        if ([fileNames count])
            [[QLPreviewPanel sharedPreviewPanel] setURLs:fileNames currentIndex:0 preservingDisplayState:YES];
    }
}

- (IBAction) refresh:(id)sender
{
    [repository forceUpdateRevisions];
}

- (void) updateView
{
    [self updateKeys];
}

- (void)viewLoaded
{
    float position = [[NSUserDefaults standardUserDefaults] floatForKey:@"PBGitSplitViewPosition"];
    if (position)
        [historySplitView setPosition:position ofDividerAtIndex:0];
}

- (NSResponder *)firstResponder;
{
    return commitList;
}

- (void) scrollSelectionToTopOfViewFrom:(NSInteger)oldIndex
{
    if (oldIndex == NSNotFound)
        oldIndex = 0;

    NSInteger newIndex = [[commitController selectionIndexes] firstIndex];

    if (newIndex > oldIndex) {
        CGFloat sviewHeight = [[commitList superview] bounds].size.height;
        CGFloat rowHeight = [commitList rowHeight];
        NSInteger visibleRows = roundf(sviewHeight / rowHeight );
        newIndex += (visibleRows - 1);
        if (newIndex >= [[commitController content] count])
            newIndex = [[commitController content] count] - 1;
    }

    if (newIndex != oldIndex) {
        commitList.useAdjustScroll = YES;
    }

    [commitList scrollRowToVisible:newIndex];
    commitList.useAdjustScroll = NO;
}

- (NSArray *) selectedObjectsForSHA:(PBGitSHA *)commitSHA
{
    NSPredicate *selection = [NSPredicate predicateWithFormat:@"sha == %@", commitSHA];
    NSArray *selectedCommits = [[commitController content] filteredArrayUsingPredicate:selection];

    if (([selectedCommits count] == 0) && [self firstCommit])
        selectedCommits = [NSArray arrayWithObject:[self firstCommit]];

    return selectedCommits;
}

- (void)selectCommit:(PBGitSHA *)commitSHA
{
    if (!forceSelectionUpdate && [[[[commitController selectedObjects] lastObject] sha] isEqual:commitSHA])
        return;

    NSInteger oldIndex = [[commitController selectionIndexes] firstIndex];

    NSArray *selectedCommits = [self selectedObjectsForSHA:commitSHA];
    [commitController setSelectedObjects:selectedCommits];

    if (repository.currentBranchFilter != kGitXSelectedBranchFilter)
        [self scrollSelectionToTopOfViewFrom:oldIndex];

    forceSelectionUpdate = NO;
}

- (BOOL) hasNonlinearPath
{
    return [commitController filterPredicate] || [[commitController sortDescriptors] count] > 0;
}

- (void)closeView
{
    float position = [[[historySplitView subviews] objectAtIndex:0] frame].size.height;
    [[NSUserDefaults standardUserDefaults] setFloat:position forKey:@"PBGitSplitViewPosition"];
    [[NSUserDefaults standardUserDefaults] synchronize];

	[[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:@"values.PBUseRelativeDates"];

    if (commitController) {
        [commitController removeObserver:self forKeyPath:@"selection"];
        [commitController removeObserver:self forKeyPath:@"arrangedObjects.@count"];
        [treeController removeObserver:self forKeyPath:@"selection"];

        [repository.revisionList removeObserver:self forKeyPath:@"isUpdating"];
        [repository removeObserver:self forKeyPath:@"currentBranch"];
        [repository removeObserver:self forKeyPath:@"refs"];
    }

    [webHistoryController closeView];

    [super closeView];
}

#pragma mark Table Column Methods
- (NSMenu *)tableColumnMenu
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Table columns menu"];
    for (NSTableColumn *column in [commitList tableColumns]) {
        NSMenuItem *item = [[NSMenuItem alloc] init];
        [item setTitle:[[column headerCell] stringValue]];
        [item bind:@"value"
          toObject:column
       withKeyPath:@"hidden"
           options:[NSDictionary dictionaryWithObject:@"NSNegateBoolean" forKey:NSValueTransformerNameBindingOption]];
        [menu addItem:item];
    }
    return menu;
}

#pragma mark Tree Context Menu Methods

- (void)showBlameFromTree:(id)sender
{
    NSArray *filePath = [sender representedObject];
	currentFileBrowserSelectionPath = filePath;
	[self restoreFileBrowserSelection];
	self.selectedCommitDetailsIndex = 2;
}

- (void)showCommitsFromTree:(id)sender
{
    // TODO: Enable this from webview as well!

    NSMutableArray *filePaths = [NSMutableArray arrayWithObjects:@"HEAD", @"--", NULL];
    [filePaths addObjectsFromArray:[sender representedObject]];

    PBGitRevSpecifier *revSpec = [[PBGitRevSpecifier alloc] initWithParameters:filePaths];

    repository.currentBranch = [repository addBranch:revSpec];
}

- (void)showInFinderAction:(id)sender
{
    NSString *workingDirectory = [[repository workingDirectory] stringByAppendingString:@"/"];
    NSString *path;
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];

    for (NSString *filePath in [sender representedObject]) {
        path = [workingDirectory stringByAppendingPathComponent:filePath];
        [ws selectFile: path inFileViewerRootedAtPath:path];
    }

}

- (void)openFilesAction:(id)sender
{
    NSString *workingDirectory = [[repository workingDirectory] stringByAppendingString:@"/"];
    NSString *path;
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];

    for (NSString *filePath in [sender representedObject]) {
        path = [workingDirectory stringByAppendingPathComponent:filePath];
        [ws openFile:path];
    }
}

- (void) checkoutFiles:(id)sender
{
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *filePath in [sender representedObject])
        [files addObject:[filePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];

    [repository checkoutFiles:files fromRefish:selectedCommit];
}

- (void) diffFilesAction:(id)sender
{
    [PBDiffWindowController showDiffWindowWithFiles:[sender representedObject] fromCommit:selectedCommit diffCommit:nil];
}

- (NSMenu *)contextMenuForTreeView
{
    NSArray *filePaths = [[treeController selectedObjects] valueForKey:@"fullPath"];

    NSMenu *menu = [[NSMenu alloc] init];
    for (NSMenuItem *item in [self menuItemsForPaths:filePaths addSeparator:NO])
        [menu addItem:item];
    return menu;
}

- (NSArray *)menuItemsForPaths:(NSArray *)paths addSeparator:(BOOL)addSeparator
{
    NSMutableArray *filePaths = [NSMutableArray array];
    for (NSString *filePath in paths)
        [filePaths addObject:[filePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];

    BOOL multiple = [filePaths count] != 1;
    NSMenuItem *blameItem = [[NSMenuItem alloc] initWithTitle:@"Show blame for file"
                                                         action:(multiple == YES) ? nil : @selector(showBlameFromTree:)
                                                  keyEquivalent:@""];

    NSMenuItem *historyItem = [[NSMenuItem alloc] initWithTitle:multiple? @"Show history of files" : @"Show history of file"
                                                         action:@selector(showCommitsFromTree:)
                                                  keyEquivalent:@""];

    PBGitRef *headRef = [[repository headRef] ref];
    NSString *headRefName = [headRef shortName];
    NSString *diffTitle = [NSString stringWithFormat:@"Diff %@ with %@", multiple ? @"files" : @"file", headRefName];
    BOOL isHead = [[selectedCommit sha] isEqual:[repository headSHA]];
    NSMenuItem *diffItem = [[NSMenuItem alloc] initWithTitle:diffTitle
                                                      action:isHead ? nil : @selector(diffFilesAction:)
                                               keyEquivalent:@""];

    NSMenuItem *checkoutItem = [[NSMenuItem alloc] initWithTitle:multiple ? @"Checkout files" : @"Checkout file"
                                                          action:@selector(checkoutFiles:)
                                                   keyEquivalent:@""];
    NSMenuItem *finderItem = [[NSMenuItem alloc] initWithTitle:@"Show in Finder"
                                                        action:@selector(showInFinderAction:)
                                                 keyEquivalent:@""];
    NSMenuItem *openFilesItem = [[NSMenuItem alloc] initWithTitle:multiple? @"Open Files" : @"Open File"
                                                           action:@selector(openFilesAction:)
                                                    keyEquivalent:@""];

    NSArray *menuItems;
	if (addSeparator) {
		menuItems = [NSArray arrayWithObjects:blameItem, historyItem, diffItem, checkoutItem, [NSMenuItem separatorItem], finderItem, openFilesItem, [NSMenuItem separatorItem], nil];
	} else {
		menuItems = [NSArray arrayWithObjects:blameItem, historyItem, diffItem, checkoutItem, [NSMenuItem separatorItem], finderItem, openFilesItem, nil];
	}
    for (NSMenuItem *item in menuItems) {
        [item setTarget:self];
        [item setRepresentedObject:filePaths];
    }

    return menuItems;
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview {
    return TRUE;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex {
    int index = [[splitView subviews] indexOfObject:subview];
    // this method (and canCollapse) are called by the splitView to decide how to collapse on double-click
    // we compare our two subviews, so that always the smaller one is collapsed.
    if([[[splitView subviews] objectAtIndex:index] frame].size.height < [[[splitView subviews] objectAtIndex:((index+1)%2)] frame].size.height) {
        return TRUE;
    }
    return FALSE;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset {
    return proposedMin + historySplitView.topViewMin;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset {
    if(offset == 1)
        return proposedMax - historySplitView.bottomViewMin;
    return [sender frame].size.height;
}


#pragma mark Repository Methods

- (IBAction) createBranch:(id)sender
{
    PBGitRef *currentRef = [repository.currentBranch ref];

    if (!selectedCommit || [selectedCommit hasRef:currentRef])
        [PBCreateBranchSheet beginCreateBranchSheetAtRefish:currentRef inRepository:self.repository];
    else
        [PBCreateBranchSheet beginCreateBranchSheetAtRefish:selectedCommit inRepository:self.repository];
}

- (IBAction) createTag:(id)sender
{
    if (!selectedCommit)
        [PBCreateTagSheet beginCreateTagSheetAtRefish:[repository.currentBranch ref] inRepository:repository];
    else
        [PBCreateTagSheet beginCreateTagSheetAtRefish:selectedCommit inRepository:repository];
}

- (IBAction) showAddRemoteSheet:(id)sender
{
    [PBAddRemoteSheet beginAddRemoteSheetForRepository:self.repository];
}

- (IBAction) merge:(id)sender
{
    if (selectedCommit)
        [repository mergeWithRefish:selectedCommit];
}

- (IBAction) cherryPick:(id)sender
{
    if (selectedCommit)
        [repository cherryPickRefish:selectedCommit];
}

- (IBAction) rebase:(id)sender
{
    if (selectedCommit) {
        PBGitRef *headRef = [[repository headRef] ref];
        [repository rebaseBranch:headRef onRefish:selectedCommit];
    }
}

#pragma mark -
#pragma mark Quick Look Public API support

@protocol QLPreviewItem;

#pragma mark (QLPreviewPanelController)

- (BOOL) acceptsPreviewPanelControl:(id)panel
{
    return YES;
}

- (void)beginPreviewPanelControl:(id)panel
{
    // This document is now responsible of the preview panel
    // It is allowed to set the delegate, data source and refresh panel.
    previewPanel = panel;
    [previewPanel setDelegate:self];
    [previewPanel setDataSource:self];
}

- (void)endPreviewPanelControl:(id)panel
{
    // This document loses its responsisibility on the preview panel
    // Until the next call to -beginPreviewPanelControl: it must not
    // change the panel's delegate, data source or refresh it.
    previewPanel = nil;
}

#pragma mark <QLPreviewPanelDataSource>

- (NSInteger)numberOfPreviewItemsInPreviewPanel:(id)panel
{
    return [[fileBrowser selectedRowIndexes] count];
}

- (id <QLPreviewItem>)previewPanel:(id)panel previewItemAtIndex:(NSInteger)index
{
    PBGitTree *treeItem = (PBGitTree *)[[treeController selectedObjects] objectAtIndex:index];
    NSURL *previewURL = [NSURL fileURLWithPath:[treeItem tmpFileNameForContents]];

    return (id <QLPreviewItem>)previewURL;
}

#pragma mark <QLPreviewPanelDelegate>

- (BOOL)previewPanel:(id)panel handleEvent:(NSEvent *)event
{
    // redirect all key down events to the table view
    if ([event type] == NSKeyDown) {
        [fileBrowser keyDown:event];
        return YES;
    }
    return NO;
}

// This delegate method provides the rect on screen from which the panel will zoom.
- (NSRect)previewPanel:(id)panel sourceFrameOnScreenForPreviewItem:(id <QLPreviewItem>)item
{
    NSInteger index = [fileBrowser rowForItem:[[treeController selectedNodes] objectAtIndex:0]];
    if (index == NSNotFound) {
        return NSZeroRect;
    }

    NSRect iconRect = [fileBrowser frameOfCellAtColumn:0 row:index];

    // check that the icon rect is visible on screen
    NSRect visibleRect = [fileBrowser visibleRect];

    if (!NSIntersectsRect(visibleRect, iconRect)) {
        return NSZeroRect;
    }

    // convert icon rect to screen coordinates
    iconRect = [fileBrowser convertRectToBase:iconRect];
    iconRect.origin = [[fileBrowser window] convertBaseToScreen:iconRect.origin];

    return iconRect;
}

@end

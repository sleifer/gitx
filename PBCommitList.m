//
//  PBCommitList.m
//  GitX
//
//  Created by Pieter de Bie on 9/11/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBCommitList.h"
#import "PBGitRevisionCell.h"
#import "PBWebHistoryController.h"

@implementation PBCommitList

@synthesize mouseDownPoint;
@synthesize useAdjustScroll;

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL) local
{
    return NSDragOperationCopy;
}

- (void)keyDown:(NSEvent *)event
{
    NSString* character = [event charactersIgnoringModifiers];

    // Pass on command-shift up/down to the responder. We want the splitview to capture this.
    if ([event modifierFlags] & NSShiftKeyMask && [event modifierFlags] & NSCommandKeyMask && ([event keyCode] == 0x7E || [event keyCode] == 0x7D)) {
        [self.nextResponder keyDown:event];
        return;
    }

    if ([character isEqualToString:@" "]) {
        if (controller.selectedCommitDetailsIndex == 0) {
            if ([event modifierFlags] & NSShiftKeyMask)
                [webView scrollPageUp:self];
            else
                [webView scrollPageDown:self];
        }
        else
            [controller toggleQLPreviewPanel:self];
    }
    else if ([character rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"jkcv"]].location == 0)
        [webController sendKey: character];
    else
        [super keyDown: event];
}

- (void) copy:(id)sender
{
    [controller copyCommitInfo];
}

- (void) copySHA:(id)sender
{
    [controller copyCommitSHA];
}

- (void) copySVNRevision:(id)sender
{
    [controller copyCommitSVNRevision];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	SEL action = [anItem action];
	if (action == @selector(copy:) || action == @selector(copySHA:))
		return [controller.commitController selectionIndex] != NSNotFound;
	return [super respondsToSelector:@selector(validateUserInterfaceItem:)] ? [super validateUserInterfaceItem:anItem] : YES;
}

// !!! Andre Berg 20100330: Used from -scrollSelectionToTopOfViewFrom: of PBGitHistoryController
// so that when the history controller udpates the branch filter the origin of the superview gets
// shifted into multiples of the row height. Otherwise the top selected row will always be off by
// a little bit depending on how much the bottom half of the split view is dragged down.
- (NSRect)adjustScroll:(NSRect)proposedVisibleRect {

    //NSLog(@"[%@ %s]: proposedVisibleRect: %@", [self class], _cmd, NSStringFromRect(proposedVisibleRect));
    NSRect newRect = proposedVisibleRect;

    // !!! Andre Berg 20100330: only modify if -scrollSelectionToTopOfViewFrom: has set useAdjustScroll to YES
    // Otherwise we'd also constrain things like middle mouse scrolling.
    if (useAdjustScroll) {
        NSInteger rh = [self rowHeight];
        NSInteger ny = (NSInteger)proposedVisibleRect.origin.y % (NSInteger)rh;
        NSInteger adj = rh - ny;
        // check the targeted row and see if we need to add or subtract the difference (if there is one)...
        NSRect sr = [self rectOfRow:[self selectedRow]];
        // NSLog(@"[%@ %s]: selectedRow %d, rect: %@", [self class], _cmd, [self selectedRow], NSStringFromRect(sr));
        if (sr.origin.y > proposedVisibleRect.origin.y) {
            // NSLog(@"[%@ %s] selectedRow.origin.y > proposedVisibleRect.origin.y. adding adj (%d)", [self class], _cmd, adj);
            newRect = NSMakeRect(newRect.origin.x, newRect.origin.y + adj, newRect.size.width, newRect.size.height);
        } else if (sr.origin.y < proposedVisibleRect.origin.y) {
            // NSLog(@"[%@ %s] selectedRow.origin.y < proposedVisibleRect.origin.y. subtracting ny (%d)", [self class], _cmd, ny);
            newRect = NSMakeRect(newRect.origin.x, newRect.origin.y - ny , newRect.size.width, newRect.size.height);
        } else {
            // NSLog(@"[%@ %s] selectedRow.origin.y == proposedVisibleRect.origin.y. leaving as is", [self class], _cmd);
        }
    }
    //NSLog(@"[%@ %s]: newRect: %@", [self class], _cmd, NSStringFromRect(newRect));
    return newRect;
}

- (void)mouseDown:(NSEvent *)theEvent
{
    mouseDownPoint = [[self window] mouseLocationOutsideOfEventStream];
    [super mouseDown:theEvent];
}

- (NSImage *)dragImageForRowsWithIndexes:(NSIndexSet *)dragRows
                            tableColumns:(NSArray *)tableColumns
                                   event:(NSEvent *)dragEvent
                                  offset:(NSPointPointer)dragImageOffset
{
    NSPoint location = [self convertPointFromBase:mouseDownPoint];
    int row = [self rowAtPoint:location];
    int column = [self columnAtPoint:location];
    PBGitRevisionCell *cell = (PBGitRevisionCell *)[self preparedCellAtColumn:column row:row];
    NSRect cellFrame = [self frameOfCellAtColumn:column row:row];

    int index = [cell indexAtX:(location.x - cellFrame.origin.x)];
    if (index == -1)
        return [super dragImageForRowsWithIndexes:dragRows tableColumns:tableColumns event:dragEvent offset:dragImageOffset];

    NSRect rect = [cell rectAtIndex:index];

    NSImage *newImage = [[NSImage alloc] initWithSize:NSMakeSize(rect.size.width + 3, rect.size.height + 3)];
    rect.origin = NSMakePoint(0.5, 0.5);

    [newImage lockFocus];
    [cell drawLabelAtIndex:index inRect:rect];
    [newImage unlockFocus];

    *dragImageOffset = NSMakePoint(rect.size.width / 2 + 10, 0);
    return newImage;

}
@end

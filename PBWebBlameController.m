//
//  PBWebBlameController.h
//  GitTest
//
//  Created by Simeon Leifer 24-Aug-2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "PBWebBlameController.h"
#import "PBGitDefaults.h"
#import "PBGitSHA.h"

@implementation PBWebBlameController

@synthesize blame;

- (void) awakeFromNib
{
    startFile = @"blame";
    repository = historyController.repository;
    [super awakeFromNib];
}

- (void)closeView
{
    [[self script] setValue:nil forKey:@"commit"];

    [super closeView];
}

- (void) didLoad
{
    currentSha = nil;
	currentRef = nil;
	currentPath = nil;
    [self changeContentTo:nil atCommit:nil];
}

- (void)changeContentTo:(PBGitTree*)content atCommit:(PBGitCommit*)commit
{
    if (content == nil || !finishedLoading)
        return;

    // The sha is the same, but refs may have changed.. reload it lazy
    if ([currentSha isEqual:[content sha]] && [currentPath isEqual:[content fullPath]])
    {
        [[self script] callWebScriptMethod:@"reload" withArguments: nil];
        return;
    }
	
	currentRef = [[commit sha] string];
	
    NSArray *arguments = [NSArray arrayWithObjects:content, currentRef, nil];
    id scriptResult = [[self script] callWebScriptMethod:@"loadBlame" withArguments: arguments];
    if (!scriptResult) {
        // the web view is not really ready for scripting???
        [self performSelector:_cmd withObject:content afterDelay:0.05];
        return;
    }
    currentSha = [content sha];
	currentPath = [content fullPath];

    // Now we load the extended details. We used to do this in a separate thread,
    // but this caused some funny behaviour because NSTask's and NSThread's don't really
    // like each other. Instead, just do it async.

    NSMutableArray *taskArguments = [NSMutableArray arrayWithObjects:@"blame", currentRef, @"--", currentPath, nil];

    NSFileHandle *handle = [repository handleForArguments:taskArguments];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    // Remove notification, in case we have another one running
    [nc removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:nil];
    [nc addObserver:self selector:@selector(blameDetailsLoaded:) name:NSFileHandleReadToEndOfFileCompletionNotification object:handle];
    [handle readToEndOfFileInBackgroundAndNotify];
}

- (void)blameDetailsLoaded:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:nil];

    NSData *data = [[notification userInfo] valueForKey:NSFileHandleNotificationDataItem];
    if (!data)
        return;

    NSString *details = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!details)
        details = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];

    if (!details)
        return;

    [[view windowScriptObject] callWebScriptMethod:@"loadBlameDetails" withArguments:[NSArray arrayWithObject:details]];
}

- (void)selectBlame:(NSString *)sha
{
    [historyController selectCommit:[PBGitSHA shaWithString:sha]];
}

- (void) sendKey: (NSString*) key
{
    id script = [view windowScriptObject];
    [script callWebScriptMethod:@"handleKeyFromCocoa" withArguments: [NSArray arrayWithObject:key]];
}

- (void) copySource
{
    NSString *source = [(DOMHTMLElement *)[[[view mainFrame] DOMDocument] documentElement] outerHTML];
    NSPasteboard *a =[NSPasteboard generalPasteboard];
    [a declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
    [a setString:source forType: NSStringPboardType];
}

- (NSArray *)      webView:(WebView *)sender
contextMenuItemsForElement:(NSDictionary *)element
          defaultMenuItems:(NSArray *)defaultMenuItems
{
    DOMNode *node = [element valueForKey:@"WebElementDOMNode"];

    while (node) {
        // Every ref has a class name of 'refs' and some other class. We check on that to see if we pressed on a ref.
        if ([[node className] hasPrefix:@"refs "]) {
            NSString *selectedRefString = [[[node childNodes] item:0] textContent];
            for (PBGitRef *ref in historyController.webCommit.refs)
            {
                if ([[ref shortName] isEqualToString:selectedRefString])
                    return [contextMenuDelegate menuItemsForRef:ref];
            }
            NSLog(@"Could not find selected ref!");
            return defaultMenuItems;
        }
        if ([node hasAttributes] && [[node attributes] getNamedItem:@"representedFile"])
            return [historyController menuItemsForPaths:[NSArray arrayWithObject:[[[node attributes] getNamedItem:@"representedFile"] value]] addSeparator:YES];
        else if ([[node class] isEqual:[DOMHTMLImageElement class]]) {
            // Copy Image is the only menu item that makes sense here since we don't need
            // to download the image or open it in a new window (besides with the
            // current implementation these two entries can crash GitX anyway)
            for (NSMenuItem *item in defaultMenuItems)
                if ([item tag] == WebMenuItemTagCopyImageToClipboard)
                    return [NSArray arrayWithObject:item];
            return nil;
        }

        node = [node parentNode];
    }

    return defaultMenuItems;
}


// Open external links in the default browser
-   (void)webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)actionInformation
          request:(NSURLRequest *)request
     newFrameName:(NSString *)frameName
 decisionListener:(id < WebPolicyDecisionListener >)listener
{
    [[NSWorkspace sharedWorkspace] openURL:[request URL]];
}

- getConfig:(NSString *)config
{
    return [historyController valueForKeyPath:[@"repository.config." stringByAppendingString:config]];
}

- (void)finalize
{
    [super finalize];
}

@end

//
//  PBGitRepository.m
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitRepository.h"
#import "PBGitCommit.h"
#import "PBGitWindowController.h"
#import "PBGitBinary.h"

#import "NSFileHandleExt.h"
#import "PBEasyPipe.h"
#import "PBGitRef.h"
#import "PBGitRevSpecifier.h"
#import "PBRemoteProgressSheet.h"
#import "PBGitRevList.h"
#import "PBGitDefaults.h"

NSString* PBGitRepositoryErrorDomain = @"GitXErrorDomain";

@implementation PBGitRepository

@synthesize revisionList, branches, currentBranch, refs, hasChanged, config;
@synthesize currentBranchFilter;

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
    if (outError) {
        *outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain
                                      code:0
                                  userInfo:[NSDictionary dictionaryWithObject:@"Reading files is not supported." forKey:NSLocalizedFailureReasonErrorKey]];
    }
    return NO;
}

+ (BOOL) isBareRepository: (NSString*) path
{
    return [[PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:[NSArray arrayWithObjects:@"rev-parse", @"--is-bare-repository", nil] inDir:path] isEqualToString:@"true"];
}

+ (NSURL*)gitDirForURL:(NSURL*)repositoryURL;
{
    if (![PBGitBinary path])
        return nil;

    NSString* repositoryPath = [repositoryURL path];

    if ([self isBareRepository:repositoryPath])
        return repositoryURL;


    // Use rev-parse to find the .git dir for the repository being opened
    NSString* newPath = [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:[NSArray arrayWithObjects:@"rev-parse", @"--git-dir", nil] inDir:repositoryPath];
    if ([newPath isEqualToString:@".git"])
        return [NSURL fileURLWithPath:[repositoryPath stringByAppendingPathComponent:@".git"]];
    if ([newPath length] > 0)
        return [NSURL fileURLWithPath:newPath];

    return nil;
}

// For a given path inside a repository, return either the .git dir
// (for a bare repo) or the directory above the .git dir otherwise
+ (NSURL*)baseDirForURL:(NSURL*)repositoryURL;
{
    NSURL* gitDirURL         = [self gitDirForURL:repositoryURL];
    NSString* repositoryPath = [gitDirURL path];

    if (![self isBareRepository:repositoryPath]) {
        repositoryURL = [NSURL fileURLWithPath:[[repositoryURL path] stringByDeletingLastPathComponent]];
    }

    return repositoryURL;
}

// NSFileWrapper is broken and doesn't work when called on a directory containing a large number of directories and files.
//because of this it is safer to implement readFromURL than readFromFileWrapper.
//Because NSFileManager does not attempt to recursively open all directories and file when fileExistsAtPath is called
//this works much better.
- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    if (![PBGitBinary path])
    {
        if (outError) {
            NSDictionary* userInfo = [NSDictionary dictionaryWithObject:[PBGitBinary notFoundError]
                                                                 forKey:NSLocalizedRecoverySuggestionErrorKey];
            *outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0 userInfo:userInfo];
        }
        return NO;
    }

    BOOL isDirectory = FALSE;
    [[NSFileManager defaultManager] fileExistsAtPath:[absoluteURL path] isDirectory:&isDirectory];
    if (!isDirectory) {
        if (outError) {
            NSDictionary* userInfo = [NSDictionary dictionaryWithObject:@"Reading files is not supported."
                                                                 forKey:NSLocalizedRecoverySuggestionErrorKey];
            *outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0 userInfo:userInfo];
        }
        return NO;
    }


    NSURL* gitDirURL = [PBGitRepository gitDirForURL:[self fileURL]];
    if (!gitDirURL) {
        if (outError) {
            NSDictionary* userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@ does not appear to be a git repository.", [self fileName]]
                                                                 forKey:NSLocalizedRecoverySuggestionErrorKey];
            *outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0 userInfo:userInfo];
        }
        return NO;
    }

    [self setFileURL:gitDirURL];
    [self setup];
    return YES;
}

- (void) setup
{
    config = [[PBGitConfig alloc] initWithRepositoryPath:[[self fileURL] path]];
    self.branches = [NSMutableArray array];
    [self reloadRefs];
    currentBranchFilter = [PBGitDefaults branchFilter];
    revisionList = [[PBGitHistoryList alloc] initWithRepository:self];
}

- (void)close
{
    [revisionList cleanup];

    [super close];
}

- (id) initWithURL: (NSURL*) path
{
    if (![PBGitBinary path])
        return nil;

    NSURL* gitDirURL = [PBGitRepository gitDirForURL:path];
    if (!gitDirURL)
        return nil;

    self = [self init];
    [self setFileURL: gitDirURL];

    [self setup];

    // We don't want the window controller to display anything yet..
    // We'll leave that to the caller of this method.
#ifndef CLI
    [self addWindowController:[[PBGitWindowController alloc] initWithRepository:self displayDefault:NO]];
#endif

    [self showWindows];

    return self;
}

- (void) forceUpdateRevisions
{
    [revisionList forceUpdate];
}

- (BOOL)isDocumentEdited
{
    return NO;
}

// The fileURL the document keeps is to the .git dir, but that’s pretty
// useless for display in the window title bar, so we show the directory above
- (NSString *) displayName
{
    if (![[PBGitRef refFromString:[[self headRef] simpleRef]] type])
        return [NSString stringWithFormat:@"%@ (detached HEAD)", [self projectName]];

    return [NSString stringWithFormat:@"%@ (branch: %@)", [self projectName], [[self headRef] description]];
}

- (NSString *) projectName
{
    NSString *projectPath = [[self fileURL] path];

    if ([[projectPath lastPathComponent] isEqualToString:@".git"])
        projectPath = [projectPath stringByDeletingLastPathComponent];

    return [projectPath lastPathComponent];
}

// Get the .gitignore file at the root of the repository
- (NSString*)gitIgnoreFilename
{
    return [[self workingDirectory] stringByAppendingPathComponent:@".gitignore"];
}

- (BOOL)isBareRepository
{
    if([self workingDirectory]) {
        return [PBGitRepository isBareRepository:[self workingDirectory]];
    } else {
        return true;
    }
}

// Overridden to create our custom window controller
- (void)makeWindowControllers
{
#ifndef CLI
    [self addWindowController: [[PBGitWindowController alloc] initWithRepository:self displayDefault:YES]];
#endif
}

- (PBGitWindowController *)windowController
{
    if ([[self windowControllers] count] == 0)
        return NULL;

    return [[self windowControllers] objectAtIndex:0];
}

- (void) addRef: (PBGitRef *) ref fromParameters: (NSArray *) components
{
    NSString* type = [components objectAtIndex:1];

    PBGitSHA *sha;
    if ([type isEqualToString:@"tag"] && [components count] == 4)
        sha = [PBGitSHA shaWithString:[components objectAtIndex:3]];
    else
        sha = [PBGitSHA shaWithString:[components objectAtIndex:2]];

    NSMutableArray* curRefs;
    if ( (curRefs = [refs objectForKey:sha]) != nil )
        [curRefs addObject:ref];
    else
        [refs setObject:[NSMutableArray arrayWithObject:ref] forKey:sha];
}

- (void) reloadRefs
{
    _headRef = nil;
    _headSha = nil;

    refs = [NSMutableDictionary dictionary];
    NSMutableArray *oldBranches = [branches mutableCopy];

    NSArray *arguments = [NSArray arrayWithObjects:@"for-each-ref", @"--format=%(refname) %(objecttype) %(objectname) %(*objectname)", @"refs", nil];
    NSString *output = [self outputForArguments:arguments];
    NSArray *lines = [output componentsSeparatedByString:@"\n"];

    for (NSString *line in lines) {
        // If its an empty line, skip it (e.g. with empty repositories)
        if ([line length] == 0)
            continue;

        NSArray *components = [line componentsSeparatedByString:@" "];

        PBGitRef *newRef = [PBGitRef refFromString:[components objectAtIndex:0]];
        PBGitRevSpecifier *revSpec = [[PBGitRevSpecifier alloc] initWithRef:newRef];

        [self addBranch:revSpec];
        [self addRef:newRef fromParameters:components];
        [oldBranches removeObject:revSpec];
    }

    for (PBGitRevSpecifier *branch in oldBranches)
        if ([branch isSimpleRef] && ![branch isEqual:[self headRef]])
            [self removeBranch:branch];

    [self willChangeValueForKey:@"refs"];
    [self didChangeValueForKey:@"refs"];

    [[[self windowController] window] setTitle:[self displayName]];
}

- (void) lazyReload
{
    if (!hasChanged)
        return;

    [self.revisionList updateHistory];
    hasChanged = NO;
}

- (PBGitRevSpecifier *)headRef
{
    if (_headRef)
        return _headRef;

    NSString* branch = [self parseSymbolicReference: @"HEAD"];
    if (branch && [branch hasPrefix:@"refs/heads/"])
        _headRef = [[PBGitRevSpecifier alloc] initWithRef:[PBGitRef refFromString:branch]];
    else
        _headRef = [[PBGitRevSpecifier alloc] initWithRef:[PBGitRef refFromString:@"HEAD"]];

    _headSha = [self shaForRef:[_headRef ref]];

    return _headRef;
}

- (PBGitSHA *)headSHA
{
    if (! _headSha)
        [self headRef];

    return _headSha;
}

- (PBGitCommit *)headCommit
{
    return [self commitForSHA:[self headSHA]];
}

- (PBGitSHA *)shaForRef:(PBGitRef *)ref
{
    if (!ref)
        return nil;

    for (PBGitSHA *sha in refs)
        for (PBGitRef *existingRef in [refs objectForKey:sha])
            if ([existingRef isEqualToRef:ref])
                return sha;

    int retValue = 1;
    NSArray *args = [NSArray arrayWithObjects:@"rev-list", @"-1", [ref ref], nil];
    NSString *shaForRef = [self outputInWorkdirForArguments:args retValue:&retValue];
    if (retValue || [shaForRef isEqualToString:@""])
        return nil;

    return [PBGitSHA shaWithString:shaForRef];
}

- (PBGitCommit *)commitForRef:(PBGitRef *)ref
{
    if (!ref)
        return nil;

    return [self commitForSHA:[self shaForRef:ref]];
}

- (PBGitCommit *)commitForSHA:(PBGitSHA *)sha
{
    if (!sha)
        return nil;
    NSArray *revList = revisionList.projectCommits;

    if (!revList) {
        [revisionList forceUpdate];
        revList = revisionList.projectCommits;
    }
    for (PBGitCommit *commit in revList)
        if ([[commit sha] isEqual:sha])
            return commit;

    return nil;
}

- (BOOL)isOnSameBranch:(PBGitSHA *)branchSHA asSHA:(PBGitSHA *)testSHA
{
    if (!branchSHA || !testSHA)
        return NO;

    if ([testSHA isEqual:branchSHA])
        return YES;

    NSArray *revList = revisionList.projectCommits;

    NSMutableSet *searchSHAs = [NSMutableSet setWithObject:branchSHA];

    for (PBGitCommit *commit in revList) {
        PBGitSHA *commitSHA = [commit sha];
        if ([searchSHAs containsObject:commitSHA]) {
            if ([testSHA isEqual:commitSHA])
                return YES;
            [searchSHAs removeObject:commitSHA];
            [searchSHAs addObjectsFromArray:commit.parents];
        }
        else if ([testSHA isEqual:commitSHA])
            return NO;
    }

    return NO;
}

- (BOOL)isSHAOnHeadBranch:(PBGitSHA *)testSHA
{
    if (!testSHA)
        return NO;

    PBGitSHA *headSHA = [self headSHA];

    if ([testSHA isEqual:headSHA])
        return YES;

    return [self isOnSameBranch:headSHA asSHA:testSHA];
}

- (BOOL)isRefOnHeadBranch:(PBGitRef *)testRef
{
    if (!testRef)
        return NO;

    return [self isSHAOnHeadBranch:[self shaForRef:testRef]];
}

- (BOOL) checkRefFormat:(NSString *)refName
{
    int retValue = 1;
    [self outputInWorkdirForArguments:[NSArray arrayWithObjects:@"check-ref-format", refName, nil] retValue:&retValue];
    if (retValue)
        return NO;
    return YES;
}

- (BOOL) refExists:(PBGitRef *)ref
{
    int retValue = 1;
    NSString *output = [self outputInWorkdirForArguments:[NSArray arrayWithObjects:@"for-each-ref", [ref ref], nil] retValue:&retValue];
    if (retValue || [output isEqualToString:@""])
        return NO;
    return YES;
}

// Returns either this object, or an existing, equal object
- (PBGitRevSpecifier*) addBranch:(PBGitRevSpecifier*)branch
{
    if ([[branch parameters] count] == 0)
        branch = [self headRef];

    // First check if the branch doesn't exist already
    for (PBGitRevSpecifier *rev in branches)
        if ([branch isEqual: rev])
            return rev;

    NSIndexSet *newIndex = [NSIndexSet indexSetWithIndex:[branches count]];
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:newIndex forKey:@"branches"];

    [branches addObject:branch];

    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:newIndex forKey:@"branches"];
    return branch;
}

- (BOOL) removeBranch:(PBGitRevSpecifier *)branch
{
    for (PBGitRevSpecifier *rev in branches) {
        if ([branch isEqual:rev]) {
            NSIndexSet *oldIndex = [NSIndexSet indexSetWithIndex:[branches indexOfObject:rev]];
            [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:oldIndex forKey:@"branches"];

            [branches removeObject:rev];

            [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:oldIndex forKey:@"branches"];
            return YES;
        }
    }
    return NO;
}

- (void) readCurrentBranch
{
        self.currentBranch = [self addBranch: [self headRef]];
}

- (NSString *) workingDirectory
{
    if ([self.fileURL.path hasSuffix:@"/.git"])
        return [self.fileURL.path substringToIndex:[self.fileURL.path length] - 5];
    else if ([[self outputForCommand:@"rev-parse --is-inside-work-tree"] isEqualToString:@"true"])
        return [PBGitBinary path];

    return nil;
}

#pragma mark Remotes

- (NSArray *) remotes
{
    int retValue = 1;
    NSString *remotes = [self outputInWorkdirForArguments:[NSArray arrayWithObject:@"remote"] retValue:&retValue];
    if (retValue || [remotes isEqualToString:@""])
        return nil;

    return [remotes componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

- (BOOL) hasRemotes
{
    return ([self remotes] != nil);
}

- (PBGitRef *) remoteRefForBranch:(PBGitRef *)branch error:(NSError **)error
{
    if ([branch isRemote])
        return [branch remoteRef];

    NSString *branchName = [branch branchName];
    if (branchName) {
        NSString *remoteName = [[self config] valueForKeyPath:[NSString stringWithFormat:@"branch.%@.remote", branchName]];
        if (remoteName && ([remoteName isKindOfClass:[NSString class]] && ![remoteName isEqualToString:@""])) {
            PBGitRef *remoteRef = [PBGitRef refFromString:[kGitXRemoteRefPrefix stringByAppendingString:remoteName]];
            // check that the remote is a valid ref and exists
            if ([self checkRefFormat:[remoteRef ref]] && [self refExists:remoteRef])
                return remoteRef;
        }
    }

    if (error != NULL) {
        NSString *info = [NSString stringWithFormat:@"There is no remote configured for the %@ '%@'.\n\nPlease select a branch from the popup menu, which has a corresponding remote tracking branch set up.\n\nYou can also use a contextual menu to choose a branch by right clicking on its label in the commit history list.", [branch refishType], [branch shortName]];
        *error = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0
                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           @"No remote configured for branch", NSLocalizedDescriptionKey,
                                           info, NSLocalizedRecoverySuggestionErrorKey,
                                           nil]];
    }
    return nil;
}

- (NSString *) infoForRemote:(NSString *)remoteName
{
    int retValue = 1;
    NSString *output = [self outputInWorkdirForArguments:[NSArray arrayWithObjects:@"remote", @"show", remoteName, nil] retValue:&retValue];
    if (retValue)
        return nil;

    return output;
}

#pragma mark Repository commands

- (void) cloneRepositoryToPath:(NSString *)path bare:(BOOL)isBare
{
    if (!path || [path isEqualToString:@""])
        return;

    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"clone", @"--no-hardlinks", @"--", @".", path, nil];
    if (isBare)
        [arguments insertObject:@"--bare" atIndex:1];

    NSString *description = [NSString stringWithFormat:@"Cloning the repository %@ to %@", [self projectName], path];
    NSString *title = @"Cloning Repository";
    [PBRemoteProgressSheet beginRemoteProgressSheetForArguments:arguments title:title description:description inRepository:self];
}

- (void) beginAddRemote:(NSString *)remoteName forURL:(NSString *)remoteURL
{
    NSArray *arguments = [NSArray arrayWithObjects:@"remote",  @"add", @"-f", remoteName, remoteURL, nil];

    NSString *description = [NSString stringWithFormat:@"Adding the remote %@ and fetching tracking branches", remoteName];
    NSString *title = @"Adding a remote";
    [PBRemoteProgressSheet beginRemoteProgressSheetForArguments:arguments title:title description:description inRepository:self];
}

- (void) beginFetchFromRemoteForRef:(PBGitRef *)ref
{
    NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"fetch"];

    if (![ref isRemote]) {
        NSError *error = nil;
        ref = [self remoteRefForBranch:ref error:&error];
        if (!ref) {
            if (error)
                [self.windowController showErrorSheet:error];
            return;
        }
    }
    NSString *remoteName = [ref remoteName];
    [arguments addObject:remoteName];

    NSString *description = [NSString stringWithFormat:@"Fetching all tracking branches from %@", remoteName];
    NSString *title = @"Fetching from remote";
    [PBRemoteProgressSheet beginRemoteProgressSheetForArguments:arguments title:title description:description inRepository:self];
}

- (void) beginPullFromRemote:(PBGitRef *)remoteRef forRef:(PBGitRef *)ref
{
    NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"pull"];

    // a nil remoteRef means lookup the ref's default remote
    if (!remoteRef || ![remoteRef isRemote]) {
        NSError *error = nil;
        remoteRef = [self remoteRefForBranch:ref error:&error];
        if (!remoteRef) {
            if (error)
                [self.windowController showErrorSheet:error];
            return;
        }
    }
    NSString *remoteName = [remoteRef remoteName];
    [arguments addObject:remoteName];

    NSString *branchName = nil;
    NSString *refSpec = nil;
    if ([ref isRemoteBranch]) {
        branchName = [ref shortName];
        refSpec = [ref remoteBranchName];
    }
    else if ([ref isRemote] || !ref) {
        branchName = @"all tracking branches";
    }
    else {
        branchName = [ref shortName];
        refSpec = [NSString stringWithFormat:@"%@:%@", branchName, branchName];
    }
    if (refSpec)
        [arguments addObject:refSpec];

    NSString *headRefName = [[[self headRef] ref] shortName];
    NSString *description = [NSString stringWithFormat:@"Pulling %@ from %@ and updating %@", branchName, remoteName, headRefName];
    NSString *title = @"Pulling from remote";
    [PBRemoteProgressSheet beginRemoteProgressSheetForArguments:arguments title:title description:description inRepository:self];
}

- (void) beginPushRef:(PBGitRef *)ref toRemote:(PBGitRef *)remoteRef
{
    NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"push"];

    // a nil remoteRef means lookup the ref's default remote
    if (!remoteRef || ![remoteRef isRemote]) {
        NSError *error = nil;
        remoteRef = [self remoteRefForBranch:ref error:&error];
        if (!remoteRef) {
            if (error)
                [self.windowController showErrorSheet:error];
            return;
        }
    }
    NSString *remoteName = [remoteRef remoteName];
    [arguments addObject:remoteName];

    NSString *branchName = nil;
    if ([ref isRemote] || !ref) {
        branchName = @"all updates";
    }
    else if ([ref isTag]) {
        branchName = [NSString stringWithFormat:@"tag '%@'", [ref tagName]];
        [arguments addObject:@"tag"];
        [arguments addObject:[ref tagName]];
    }
    else {
        branchName = [ref shortName];
        [arguments addObject:branchName];
    }

    NSString *description = [NSString stringWithFormat:@"Pushing %@ to %@", branchName, remoteName];
    NSString *title = @"Pushing to remote";
    [PBRemoteProgressSheet beginRemoteProgressSheetForArguments:arguments title:title description:description inRepository:self];
}

- (BOOL) checkoutRefish:(id <PBGitRefish>)ref
{
    NSString *refName = nil;
    if ([ref refishType] == kGitXBranchType)
        refName = [ref shortName];
    else
        refName = [ref refishName];

    int retValue = 1;
    NSArray *arguments = [NSArray arrayWithObjects:@"checkout", refName, nil];
    NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *message = [NSString stringWithFormat:@"There was an error checking out the %@ '%@'.\n\nPerhaps your working directory is not clean?", [ref refishType], [ref shortName]];
        [self.windowController showErrorSheetTitle:@"Checkout failed!" message:message arguments:arguments output:output];
        return NO;
    }

    [self reloadRefs];
    [self readCurrentBranch];
    return YES;
}

- (BOOL) checkoutFiles:(NSArray *)files fromRefish:(id <PBGitRefish>)ref
{
    if (!files || ([files count] == 0))
        return NO;

    NSString *refName = nil;
    if ([ref refishType] == kGitXBranchType)
        refName = [ref shortName];
    else
        refName = [ref refishName];

    int retValue = 1;
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"checkout", refName, @"--", nil];
    [arguments addObjectsFromArray:files];
    NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *message = [NSString stringWithFormat:@"There was an error checking out the file(s) from the %@ '%@'.\n\nPerhaps your working directory is not clean?", [ref refishType], [ref shortName]];
        [self.windowController showErrorSheetTitle:@"Checkout failed!" message:message arguments:arguments output:output];
        return NO;
    }

    return YES;
}


- (BOOL) mergeWithRefish:(id <PBGitRefish>)ref
{
    NSString *refName = [ref refishName];

    int retValue = 1;
    NSArray *arguments = [NSArray arrayWithObjects:@"merge", refName, nil];
    NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *headName = [[[self headRef] ref] shortName];
        NSString *message = [NSString stringWithFormat:@"There was an error merging %@ into %@.", refName, headName];
        [self.windowController showErrorSheetTitle:@"Merge failed!" message:message arguments:arguments output:output];
        return NO;
    }

    [self reloadRefs];
    [self readCurrentBranch];
    return YES;
}

- (BOOL) cherryPickRefish:(id <PBGitRefish>)ref
{
    if (!ref)
        return NO;

    NSString *refName = [ref refishName];

    int retValue = 1;
    NSArray *arguments = [NSArray arrayWithObjects:@"cherry-pick", refName, nil];
    NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *message = [NSString stringWithFormat:@"There was an error cherry picking the %@ '%@'.\n\nPerhaps your working directory is not clean?", [ref refishType], [ref shortName]];
        [self.windowController showErrorSheetTitle:@"Cherry pick failed!" message:message arguments:arguments output:output];
        return NO;
    }

    [self reloadRefs];
    [self readCurrentBranch];
    return YES;
}

- (BOOL) rebaseBranch:(id <PBGitRefish>)branch onRefish:(id <PBGitRefish>)upstream
{
    if (!upstream)
        return NO;

    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"rebase", [upstream refishName], nil];

    if (branch)
        [arguments addObject:[branch refishName]];

    int retValue = 1;
    NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *branchName = @"HEAD";
        if (branch)
            branchName = [NSString stringWithFormat:@"%@ '%@'", [branch refishType], [branch shortName]];
        NSString *message = [NSString stringWithFormat:@"There was an error rebasing %@ with %@ '%@'.", branchName, [upstream refishType], [upstream shortName]];
        [self.windowController showErrorSheetTitle:@"Rebase failed!" message:message arguments:arguments output:output];
        return NO;
    }

    [self reloadRefs];
    [self readCurrentBranch];
    return YES;
}

- (BOOL) createBranch:(NSString *)branchName atRefish:(id <PBGitRefish>)ref
{
    if (!branchName || !ref)
        return NO;

    int retValue = 1;
    NSArray *arguments = [NSArray arrayWithObjects:@"branch", branchName, [ref refishName], nil];
    NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *message = [NSString stringWithFormat:@"There was an error creating the branch '%@' at %@ '%@'.", branchName, [ref refishType], [ref shortName]];
        [self.windowController showErrorSheetTitle:@"Create Branch failed!" message:message arguments:arguments output:output];
        return NO;
    }

    [self reloadRefs];
    return YES;
}

- (BOOL) createTag:(NSString *)tagName message:(NSString *)message atRefish:(id <PBGitRefish>)target
{
    if (!tagName)
        return NO;

    NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"tag"];

    // if there is a message then make this an annotated tag
    if (message && ![message isEqualToString:@""] && ([message length] > 3)) {
        [arguments addObject:@"-a"];
        [arguments addObject:[@"-m" stringByAppendingString:message]];
    }

    [arguments addObject:tagName];

    // if no refish then git will add it to HEAD
    if (target)
        [arguments addObject:[target refishName]];

    int retValue = 1;
    NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *targetName = @"HEAD";
        if (target)
            targetName = [NSString stringWithFormat:@"%@ '%@'", [target refishType], [target shortName]];
        NSString *message = [NSString stringWithFormat:@"There was an error creating the tag '%@' at %@.", tagName, targetName];
        [self.windowController showErrorSheetTitle:@"Create Tag failed!" message:message arguments:arguments output:output];
        return NO;
    }

    [self reloadRefs];
    return YES;
}

- (BOOL) deleteRemote:(PBGitRef *)ref
{
    if (!ref || ([ref refishType] != kGitXRemoteType))
        return NO;

    int retValue = 1;
    NSArray *arguments = [NSArray arrayWithObjects:@"remote", @"rm", [ref remoteName], nil];
    NSString * output = [self outputForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *message = [NSString stringWithFormat:@"There was an error deleting the remote: %@\n\n", [ref remoteName]];
        [self.windowController showErrorSheetTitle:@"Delete remote failed!" message:message arguments:arguments output:output];
        return NO;
    }

    // remove the remote's branches
    NSString *remoteRef = [kGitXRemoteRefPrefix stringByAppendingString:[ref remoteName]];
    for (PBGitRevSpecifier *rev in [branches copy]) {
        PBGitRef *branch = [rev ref];
        if ([[branch ref] hasPrefix:remoteRef]) {
            [self removeBranch:rev];
            PBGitCommit *commit = [self commitForRef:branch];
            [commit removeRef:branch];
        }
    }

    [self reloadRefs];
    return YES;
}

- (BOOL) deleteRef:(PBGitRef *)ref
{
    if (!ref)
        return NO;

    if ([ref refishType] == kGitXRemoteType)
        return [self deleteRemote:ref];

    int retValue = 1;
    NSArray *arguments = [NSArray arrayWithObjects:@"update-ref", @"-d", [ref ref], nil];
    NSString * output = [self outputForArguments:arguments retValue:&retValue];
    if (retValue) {
        NSString *message = [NSString stringWithFormat:@"There was an error deleting the ref: %@\n\n", [ref shortName]];
        [self.windowController showErrorSheetTitle:@"Delete ref failed!" message:message arguments:arguments output:output];
        return NO;
    }

    [self removeBranch:[[PBGitRevSpecifier alloc] initWithRef:ref]];
    PBGitCommit *commit = [self commitForRef:ref];
    [commit removeRef:ref];

    [self reloadRefs];
    return YES;
}


#pragma mark low level

- (int) returnValueForCommand:(NSString *)cmd
{
    int i;
    [self outputForCommand:cmd retValue: &i];
    return i;
}

- (NSFileHandle*) handleForArguments:(NSArray *)args
{
    NSString* gitDirArg = [@"--git-dir=" stringByAppendingString:self.fileURL.path];
    NSMutableArray* arguments =  [NSMutableArray arrayWithObject: gitDirArg];
    [arguments addObjectsFromArray: args];
    return [PBEasyPipe handleForCommand:[PBGitBinary path] withArgs:arguments];
}

- (NSFileHandle*) handleInWorkDirForArguments:(NSArray *)args
{
    NSString* gitDirArg = [@"--git-dir=" stringByAppendingString:self.fileURL.path];
    NSMutableArray* arguments =  [NSMutableArray arrayWithObject: gitDirArg];
    [arguments addObjectsFromArray: args];
    return [PBEasyPipe handleForCommand:[PBGitBinary path] withArgs:arguments inDir:[self workingDirectory]];
}

- (NSFileHandle*) handleForCommand:(NSString *)cmd
{
    NSArray* arguments = [cmd componentsSeparatedByString:@" "];
    return [self handleForArguments:arguments];
}

- (NSString*) outputForCommand:(NSString *)cmd
{
    NSArray* arguments = [cmd componentsSeparatedByString:@" "];
    return [self outputForArguments: arguments];
}

- (NSString*) outputForCommand:(NSString *)str retValue:(int *)ret;
{
    NSArray* arguments = [str componentsSeparatedByString:@" "];
    return [self outputForArguments: arguments retValue: ret];
}

- (NSString*) outputForArguments:(NSArray*) arguments
{
    return [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir: self.fileURL.path];
}

- (NSString*) outputInWorkdirForArguments:(NSArray*) arguments
{
    return [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir: [self workingDirectory]];
}

- (NSString*) outputInWorkdirForArguments:(NSArray *)arguments retValue:(int *)ret
{
    return [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir:[self workingDirectory] retValue: ret];
}

- (NSString*) outputForArguments:(NSArray *)arguments retValue:(int *)ret
{
    return [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir: self.fileURL.path retValue: ret];
}

- (NSString*) outputForArguments:(NSArray *)arguments inputString:(NSString *)input retValue:(int *)ret
{
    return [PBEasyPipe outputForCommand:[PBGitBinary path]
                               withArgs:arguments
                                  inDir:[self workingDirectory]
                            inputString:input
                               retValue: ret];
}

- (NSString *)outputForArguments:(NSArray *)arguments inputString:(NSString *)input byExtendingEnvironment:(NSDictionary *)dict retValue:(int *)ret
{
    return [PBEasyPipe outputForCommand:[PBGitBinary path]
                               withArgs:arguments
                                  inDir:[self workingDirectory]
                 byExtendingEnvironment:dict
                            inputString:input
                               retValue: ret];
}

- (BOOL)executeHook:(NSString *)name output:(NSString **)output
{
    return [self executeHook:name withArgs:[NSArray array] output:output];
}

- (BOOL)executeHook:(NSString *)name withArgs:(NSArray *)arguments output:(NSString **)output
{
    NSString *hookPath = [[[[self fileURL] path] stringByAppendingPathComponent:@"hooks"] stringByAppendingPathComponent:name];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:hookPath])
        return TRUE;

    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
        [self fileURL].path, @"GIT_DIR",
        [[self fileURL].path stringByAppendingPathComponent:@"index"], @"GIT_INDEX_FILE",
        nil
    ];

    int ret = 1;
    NSString *_output = [PBEasyPipe outputForCommand:hookPath withArgs:arguments inDir:[self workingDirectory] byExtendingEnvironment:info inputString:nil retValue:&ret];

    if (output)
        *output = _output;

    return ret == 0;
}

- (NSString *)parseReference:(NSString *)reference
{
    int ret = 1;
    NSString *ref = [self outputForArguments:[NSArray arrayWithObjects: @"rev-parse", @"--verify", reference, nil] retValue: &ret];
    if (ret)
        return nil;

    return ref;
}

- (NSString*) parseSymbolicReference:(NSString*) reference
{
    NSString* ref = [self outputForArguments:[NSArray arrayWithObjects: @"symbolic-ref", @"-q", reference, nil]];
    if ([ref hasPrefix:@"refs/"])
        return ref;

    return nil;
}

- (void) finalize
{
    NSLog(@"Dealloc of repository");
    [super finalize];
}
@end

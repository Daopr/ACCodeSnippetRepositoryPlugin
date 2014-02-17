//
//  ACCodeSnippetRepositoryConfigurationWindowController.m
//  ACCodeSnippetRepository
//
//  Created by Arnaud Coomans on 06/02/14.
//  Copyright (c) 2014 Arnaud Coomans. All rights reserved.
//

#import "ACCodeSnippetRepositoryConfigurationWindowController.h"
#import "ACCodeSnippetDataStoreProtocol.h"
#import "ACCodeSnippetGitDataStore.h"
#import "IDECodeSnippetRepositorySwizzler.h"


@interface ACCodeSnippetRepositoryConfigurationWindowController ()
@property (nonatomic, strong) NSURL *snippetRemoteRepositoryURL;
@end

@implementation ACCodeSnippetRepositoryConfigurationWindowController

#pragma mark - Initialization


- (id)initWithWindow:(NSWindow *)window {
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
}

- (NSArray*)dataStores {
    if ([self.delegate respondsToSelector:@selector(dataStoresForCodeSnippetConfigurationWindowController:)]) {
        return [self.delegate dataStoresForCodeSnippetConfigurationWindowController:self];
    }
    return nil;
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *textField = [notification object];
    
    if ([textField.stringValue length]) {
        self.forkRemoteRepositoryButton.enabled = YES;
    } else {
        self.forkRemoteRepositoryButton.enabled = NO;
    }
}


#pragma mark - Actions

- (IBAction)addRemoteRepositoryAction:(id)sender {
    [self.window beginSheet:self.addRemoteRepositoryPanel completionHandler:nil];
}

- (IBAction)forkRemoteRepositoryAction:(id)sender {
    
    [self.window endSheet:self.addRemoteRepositoryPanel];
    
    NSURL *remoteRepositoryURL = [NSURL URLWithString:self.remoteRepositoryTextfield.stringValue];
    
    BOOL isPresent = NO;
    for (id<ACCodeSnippetDataStoreProtocol>dataStore in self.dataStores) {
        if ([dataStore.remoteRepositoryURL isEqualTo:remoteRepositoryURL]) {
            isPresent = YES;
            break;
        }
    }
    
    if (!isPresent) {
        [self.window beginSheet:self.addingRemoteRepositoryPanel completionHandler:nil];
        [self.progressIndicator startAnimation:self];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            ACCodeSnippetGitDataStore *dataStore = [[ACCodeSnippetGitDataStore alloc] initWithRemoteRepositoryURL:remoteRepositoryURL];
            [[NSClassFromString(@"IDECodeSnippetRepository") sharedRepository] addDataStore:dataStore];
            [dataStore importCodeSnippets];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.remoteRepositoriesTableView reloadData];
                [self.window endSheet:self.addingRemoteRepositoryPanel];
                [self.progressIndicator stopAnimation:self];
            });
        });
    } else {
        [[NSAlert alertWithError:[NSError errorWithDomain:@"Repository already exists" code:-1 userInfo:nil]] beginSheetModalForWindow:self.window completionHandler:nil];
    }
    
}

- (IBAction)cancelSheet:(id)sender {
    [self.window endSheet:self.addRemoteRepositoryPanel];
}

- (IBAction)deleteRemoteRepositoryAction:(id)sender {
    
    NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to remove %@?", self.remoteRepositoryTextfield.stringValue]
                                     defaultButton:@"Remove"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"This will remove all snippets from the current git repository."];
    
    __weak __block ACCodeSnippetRepositoryConfigurationWindowController *weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            [weakSelf backupUserSnippets];
            
            id<ACCodeSnippetDataStoreProtocol> dataStore = weakSelf.dataStores[weakSelf.remoteRepositoriesTableView.selectedRow];
            [dataStore removeAllCodeSnippets];
            [[NSClassFromString(@"IDECodeSnippetRepository") sharedRepository] removeDataStore:dataStore];
            [weakSelf.remoteRepositoriesTableView reloadData];
        }
    }];
}

- (IBAction)backupUserSnippetsAction:(id)sender {
    [self backupUserSnippets];
}

- (void)backupUserSnippets {
    NSError *error;
    if ([[NSFileManager defaultManager] createDirectoryAtPath:self.pathForBackupDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.pathForSnippetDirectory error:&error]) {
            if ([filename hasSuffix:@".codesnippet"]) {
                NSString *path = [NSString pathWithComponents:@[self.pathForSnippetDirectory, filename]];
                NSString *toPath = [NSString pathWithComponents:@[self.pathForBackupDirectory, filename]];
                [[NSFileManager defaultManager] copyItemAtPath:path toPath:toPath error:&error];
            }
        }
    }
}

- (IBAction)openSnippetDirectoryAction:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:[self pathForSnippetDirectory]];
}


- (IBAction)removeSystemSnippets:(id)sender {
    NSError *error;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.systemSnippetsBackupPath isDirectory:nil] ||
        [[NSFileManager defaultManager] moveItemAtPath:self.systemSnippetsPath
                                            toPath:self.systemSnippetsBackupPath
                                                 error:&error]
        ) {
        
        // we need an empty file or Xcode will complain and crash at startup
        [[NSFileManager defaultManager] createFileAtPath:self.systemSnippetsPath
                                                contents:nil
                                              attributes:0];
        
        [[NSAlert alertWithMessageText:@"Restart Xcode for changes to take effect."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:@""] beginSheetModalForWindow:self.window completionHandler:nil];
    } else {
        [[NSAlert alertWithError:error] beginSheetModalForWindow:self.window completionHandler:nil];
    }
}

- (IBAction)restoreSystemSnippets:(id)sender {
    NSError *error;
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.systemSnippetsBackupPath isDirectory:nil]) {
        [[NSFileManager defaultManager] removeItemAtPath:self.systemSnippetsPath error:&error];
        
        if ([[NSFileManager defaultManager] copyItemAtPath:self.systemSnippetsBackupPath
                                                    toPath:self.systemSnippetsPath
                                                     error:&error]) {
            [[NSAlert alertWithMessageText:@"Restart Xcode for changes to take effect."
                             defaultButton:@"OK"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@""] beginSheetModalForWindow:self.window completionHandler:nil];
        } else {
            [[NSAlert alertWithError:error] beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }
}


- (NSString*)systemSnippetsPath {
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.apple.dt.IDE.IDECodeSnippetLibrary"];
    return [bundle pathForResource:@"SystemCodeSnippets" ofType:@"codesnippets"];
}

- (NSString*)systemSnippetsBackupPath {
    return [self.systemSnippetsPath stringByAppendingPathExtension:@"backup"];
}



- (IBAction)openGithubAction:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/acoomans/ACCodeSnippetRepositoryPlugin"]];
}

#pragma mark - Paths

- (NSString*)pathForSnippetDirectory {
    NSString *libraryPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [NSString pathWithComponents:@[libraryPath, @"Developer", @"Xcode", @"UserData", @"CodeSnippets"]];
}

- (NSString*)pathForBackupDirectory {
    NSDate *currentDate = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"YYMMdd-HHmm"];
    return [NSString pathWithComponents:@[self.pathForSnippetDirectory, [NSString stringWithFormat:@"backup-%@", [dateFormatter stringFromDate:currentDate]]]];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return [self.dataStores count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    
    id<ACCodeSnippetDataStoreProtocol> dataStore = self.dataStores[rowIndex];
    
    if ([aTableColumn.identifier isEqualToString:@"remoteRepositoryColumn"]) {
        return dataStore.remoteRepositoryURL;
        
    } else if ([aTableColumn.identifier isEqualToString:@"typeColumn"]) {
        
        static NSImage *image;
        if (!image) {
            NSBundle* bundle = [NSBundle bundleForClass:self.class];
            NSString *imagePath = [bundle pathForResource:@"Git-Icon-1788C" ofType:@"png"];
            image = [[NSImage alloc] initWithContentsOfFile:imagePath];
        }
        
        if ([dataStore isKindOfClass:ACCodeSnippetGitDataStore.class]) {
            return image;
        }
        return nil;
    }
    return nil;
}

@end
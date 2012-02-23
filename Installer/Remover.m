
#import <Foundation/Foundation.h>
#include <CoreFoundation/CFPropertyList.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <string.h>
#include <stdint.h>

#import "SPLogging.h"

void SavePropertyList(CFPropertyListRef plist, char *path, CFURLRef url, CFPropertyListFormat format) {
    if (path[0] != '\0')
        url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (uint8_t *) path, strlen(path), false);
    CFWriteStreamRef stream = CFWriteStreamCreateWithFile(kCFAllocatorDefault, url);
    CFWriteStreamOpen(stream);
    CFPropertyListWriteToStream(plist, stream, format, NULL);
    CFWriteStreamClose(stream);
}


@interface BFRemover : NSObject {
}

@end

@implementation BFRemover

- (NSArray *)allPaths
{
    static NSArray *cached = nil;

    if (cached == nil) {
        NSMutableArray *all = [NSMutableArray array];
        [all addObjectsFromArray:[[NSString stringWithContentsOfFile:@"/var/belfry/files.txt" encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\n"]];
        [all addObjectsFromArray:[[NSString stringWithContentsOfFile:@"/var/belfry/weeapps.txt" encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\n"]];
        cached = [all copy];
    }

    return cached;
}

- (NSArray *)directories {
    static NSArray *cached = nil;

    if (cached == nil) {
        NSMutableArray *valid = [NSMutableArray array];

        for (NSString *file in [self allPaths]) {
            NSString *trimmedFile = [file stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmedFile length] && [trimmedFile hasSuffix:@"/"] && ![trimmedFile hasPrefix:@"#"]) {
                [valid addObject:trimmedFile];
            }
        }

        // FIXME: this is a memory leak
        cached = [valid copy];
    }

    return cached;
}

- (NSArray *)files {
    static NSArray *cached = nil;

    if (cached == nil) {
        NSMutableArray *valid = [NSMutableArray array];

        for (NSString *file in [self allPaths]) {
            NSString *trimmedFile = [file stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmedFile length] && ![trimmedFile hasSuffix:@"/"] && ![trimmedFile hasPrefix:@"#"]) {
                [valid addObject:trimmedFile];
            }
        }
        
        // Generated icons
        [valid addObject:@"/Applications/Calculator.app/Icon-72.png"];
        [valid addObject:@"/Applications/MobileTimer.app/Icon-72.png"];
        [valid addObject:@"/Applications/Weather.app/Icon-72.png"];
        [valid addObject:@"/Applications/Weather.app/Icon-Celsius-72.png"];
        [valid addObject:@"/Applications/Stocks.app/Icon-72.png"];
        [valid addObject:@"/Applications/VoiceMemos.app/Icon-72.png"];

        // FIXME: this is a memory leak
        cached = [valid copy];
    }

    return cached;
}

- (BOOL)removeFileAtPath:(NSString *)file {
    NSString *path = [@"/" stringByAppendingString:file];

    return [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (BOOL)removeDirectoryAtPath:(NSString *)dir {
    NSString *path = [@"/" stringByAppendingString:dir];

    // strangely, NSFileManager has no method to remove a directory only if
    // it is empty. therefore, use the POSIX rmdir, which does exactly that.
    rmdir([path UTF8String]);

    // directories might be still used for other things (including, even, stuff
    // like /System!), so if they can't be removed, that's not a big deal.
    return YES;
}

- (BOOL)removeFiles {
    BOOL success = YES;

    for (NSString *file in [self files]) {
        // Ignore errors here: even if one doesn't exist, still remove the others.
        success = [self removeFileAtPath:file];
        if (!success) { /*SPLog(@"Failed removing file at path: /%@.", file);*/ }

        if ([file hasSuffix:@"@2x.png"]) {
            NSString *resizedFile = [[file substringToIndex:[file length] - 7] stringByAppendingString:@".png"];
            success = [self removeFileAtPath:resizedFile];
            if (!success) { /*SPLog(@"Failed removing file at path: /%@.", resizedFile);*/ }
        }
    }
    
    for (NSString *dir in [self directories]) {
        // Ignore errors here: even if one doesn't exist, still remove the others.
        success = [self removeDirectoryAtPath:dir];
        if (!success) { SPLog(@"Failed removing directory at path: /%@.", dir); }
    }

    return success;
}

- (void)removeAlternativeSharedCacheFromEnvironmentVariables:(NSMutableDictionary *)ev {
    if ([[ev objectForKey:@"DYLD_SHARED_CACHE_DIR"] isEqual:@"/var/belfry"]) {
        [ev removeObjectForKey:@"DYLD_SHARED_CACHE_DIR"];
        if ([[ev objectForKey:@"DYLD_SHARED_REGION"] isEqual:@"private"]) {
            [ev removeObjectForKey:@"DYLD_SHARED_REGION"];
        }

        if ([[ev objectForKey:@"DYLD_SHARED_CACHE_DONT_VALIDATE"] isEqual:@"1"]) {
            [ev removeObjectForKey:@"DYLD_SHARED_CACHE_DONT_VALIDATE"];
        }
    }
}

- (BOOL)removeAlternativeCacheFromAppAtPath:(const char *)path {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (uint8_t *) path, strlen(path), false);

    CFPropertyListRef plist; {
        CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
        CFReadStreamOpen(stream);
        plist = CFPropertyListCreateFromStream(kCFAllocatorDefault, stream, 0, kCFPropertyListMutableContainers, NULL, NULL);
        CFReadStreamClose(stream);
    }

    NSMutableDictionary *root = (NSMutableDictionary *) plist;
    if (root == nil) return NO;
    NSMutableDictionary *ev = [root objectForKey:@"LSEnvironment"];
    if (ev == nil) {
        ev = [NSMutableDictionary dictionary];
        [root setObject:ev forKey:@"LSEnvironment"];
    }

	[self removeAlternativeSharedCacheFromEnvironmentVariables:ev];

    SavePropertyList(plist, "", url, kCFPropertyListBinaryFormat_v1_0);
    return YES;
}

- (BOOL)removeAlternativeCacheFromDaemonAtPath:(const char *)path {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (uint8_t *) path, strlen(path), false);

    CFPropertyListRef plist; {
        CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
        CFReadStreamOpen(stream);
        plist = CFPropertyListCreateFromStream(kCFAllocatorDefault, stream, 0, kCFPropertyListMutableContainers, NULL, NULL);
        CFReadStreamClose(stream);
    }

    NSMutableDictionary *root = (NSMutableDictionary *) plist;
    if (root == nil) return NO;
    NSMutableDictionary *ev = [root objectForKey:@"EnvironmentVariables"];
    if (ev == nil) {
        ev = [NSMutableDictionary dictionary];
        [root setObject:ev forKey:@"EnvironmentVariables"];
    }

        [self removeAlternativeSharedCacheFromEnvironmentVariables:ev];

    SavePropertyList(plist, "", url, kCFPropertyListBinaryFormat_v1_0);
    return YES;
}

- (BOOL)removeSharedCache {
    BOOL success = YES;

    success = [self removeFileAtPath:@"var/belfry/dyld_shared_cache_armv7"];
    if (!success) { SPLog(@"Failed removing cache."); return success; }

    success = [self removeAlternativeCacheFromAppAtPath:"/Applications/Preferences.app/Info.plist"];
    if (!success) { SPLog(@"Failed removing cache from Preferences."); return success; }

    success = [self removeAlternativeCacheFromDaemonAtPath:"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist"];
    if (!success) { SPLog(@"Failed removing cache from SpringBoard."); return success; }

    return success;
}

- (BOOL)remove {
    BOOL success = YES;

    SPLog(@"Removing files.");
    success = [self removeFiles];
    if (!success) { SPLog(@"Failed removing files."); }

    SPLog(@"Removing shared cache.");
    success = [self removeSharedCache];
    if (!success) { SPLog(@"Failed removing shared cache."); }

    // removing always succeeded: if something above failed,
    // it's only because it wasn't installed in the first place.
    return YES;
}

@end


int main(int argc, char **argv, char **envp) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    BFRemover *remover = [[BFRemover alloc] init];
    BOOL success = [remover remove];
    [remover release];

    [pool release];

    return (success ? 0 : 1);
}



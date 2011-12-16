
#import <Foundation/Foundation.h>
#include <CoreFoundation/CFPropertyList.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <string.h>
#include <stdint.h>

void SavePropertyList(CFPropertyListRef plist, char *path, CFURLRef url, CFPropertyListFormat format) {
    if (path[0] != '\0')
        url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (uint8_t *) path, strlen(path), false);
    CFWriteStreamRef stream = CFWriteStreamCreateWithFile(kCFAllocatorDefault, url);
    CFWriteStreamOpen(stream);
    CFPropertyListWriteToStream(plist, stream, format, NULL);
    CFWriteStreamClose(stream);
}


@interface SPSiriRemover : NSObject {
}

@end

@implementation SPSiriRemover

- (NSArray *)directories {
    static NSArray *cached = nil;

    if (cached == nil) {
        NSMutableArray *valid = [NSMutableArray array];
        NSArray *files = [[NSString stringWithContentsOfFile:@"/var/spire/dirs.txt" encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\n"];

        for (NSString *file in files) {
            if ([[file stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] != 0) {
                [valid addObject:file];
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
        NSArray *files = [[NSString stringWithContentsOfFile:@"/var/spire/files.txt" encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\n"];

        for (NSString *file in files) {
            if ([[file stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] != 0) {
                [valid addObject:file];
            }
        }

        // FIXME: this is a memory leak
        cached = [valid copy];
    }

    return cached;
}

- (BOOL)removeFileAtPath:(NSString *)file {
    NSString *path = [@"/" stringByAppendingString:file];
    NSLog(@"Removing file: %@", path);

    return [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (BOOL)removeDirectoryAtPath:(NSString *)dir {
    NSString *path = [@"/" stringByAppendingString:dir];
    NSLog(@"Removing directory: %@", path);

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
        success = [self removeFileAtPath:file];
        if (!success) { NSLog(@"Failed removing file at path: /%@.", file); break; }
    }

    if (!success) return success;

    for (NSString *dir in [self directories]) {
        success = [self removeDirectoryAtPath:dir];
        if (!success) { NSLog(@"Failed removing directory at path: /%@.", dir); break; }
    }

    return success;
}

- (void)removeAlternativeSharedCacheFromEnvironmentVariables:(NSMutableDictionary *)ev {
    if ([[ev objectForKey:@"DYLD_SHARED_CACHE_DIR"] isEqual:@"/var/spire"]) {
        [ev removeObjectForKey:@"DYLD_SHARED_CACHE_DIR"];
    }

    if ([[ev objectForKey:@"DYLD_SHARED_REGION"] isEqual:@"private"]) {
        [ev removeObjectForKey:@"DYLD_SHARED_REGION"];
    }

    if ([[ev objectForKey:@"DYLD_SHARED_CACHE_DONT_VALIDATE"] isEqual:@"1"]) {
        [ev removeObjectForKey:@"DYLD_SHARED_CACHE_DONT_VALIDATE"];
    }
}

- (BOOL)removeAlternativeCacheFromDaemonAtPath:(const char *)path {
    NSLog(@"Patching cache out of daemon: %s", path);

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

- (BOOL)removeAlternativeCacheFromAppAtPath:(const char *)path {
    NSLog(@"Patching cache out of app: %s", path);

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

- (BOOL)removeSharedCache {
    BOOL success = YES;

    NSLog(@"Removing shared cache.");

    success = [self removeFileAtPath:@"var/spire/dyld_shared_cache_armv7"];
    if (!success) { NSLog(@"Failed removing cache."); return success; }

    success = [self removeAlternativeCacheFromAppAtPath:"/Applications/Preferences.app/Info.plist"];
    if (!success) { NSLog(@"Failed removing cache from Preferences."); return success; }

    success = [self removeAlternativeCacheFromDaemonAtPath:"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist"];
    if (!success) { NSLog(@"Failed removing cache from SpringBoard."); return success; }

    return success;
}

- (BOOL)removeCapabilities {
    NSLog(@"Removing capabilities.");

    static char platform[1024];
    size_t len = sizeof(platform);
    int ret = sysctlbyname("hw.model", &platform, &len, NULL, 0);
    if (ret == -1) { NSLog(@"sysctlbyname failed."); return NO; }

    NSString *platformPath = [NSString stringWithFormat:@"/System/Library/CoreServices/SpringBoard.app/%s.plist", platform];
    const char *path = [platformPath UTF8String];

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (uint8_t *) path, strlen(path), false);

    CFPropertyListRef plist; {
        CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
        CFReadStreamOpen(stream);
        plist = CFPropertyListCreateFromStream(kCFAllocatorDefault, stream, 0, kCFPropertyListMutableContainers, NULL, NULL);
        CFReadStreamClose(stream);
    }

    NSMutableDictionary *root = (NSMutableDictionary *) plist;
    if (root == nil) return NO;
    NSMutableDictionary *capabilities = [root objectForKey:@"capabilities"];
    if (capabilities == nil) return NO;

    [capabilities removeObjectForKey:@"mars-volta"];
    [capabilities removeObjectForKey:@"assistant"];

    SavePropertyList(plist, "", url, kCFPropertyListBinaryFormat_v1_0);
    return YES;
}

- (BOOL)remove {
    BOOL success = YES;

    success = [self removeFiles];
    if (!success) { NSLog(@"Failed removing files."); return success; }

    success = [self removeSharedCache];
    if (!success) { NSLog(@"Failed removing shared cache."); return success; }

    success = [self removeCapabilities];
    if (!success) { NSLog(@"Failed removing capabilities."); return success; }

    return success;
}

@end


int main(int argc, char **argv, char **envp) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    SPSiriRemover *remover = [[SPSiriRemover alloc] init];
    BOOL success = [remover remove];
    [remover release];

    [pool release];

	return (success ? 0 : 1);
}



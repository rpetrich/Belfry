
#import <Foundation/Foundation.h>
#include <CoreFoundation/CFPropertyList.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <string.h>
#include <stdint.h>

#include "partial.h"

#define kSPUpdateZIPURL @"http://appldnld.apple.com/iPhone4/041-3249.20111103.Qswe3/com_apple_MobileAsset_SoftwareUpdate/554f7813ac09d45256faad560b566814c983bd4b.zip"
#define kSPUpdateZIPRootPath @"AssetData/payload/replace/"
#define kSPWorkingDirectory @"/tmp/spire/"


void SavePropertyList(CFPropertyListRef plist, char *path, CFURLRef url, CFPropertyListFormat format) {
    if (path[0] != '\0')
        url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (uint8_t *) path, strlen(path), false);
    CFWriteStreamRef stream = CFWriteStreamCreateWithFile(kCFAllocatorDefault, url);
    CFWriteStreamOpen(stream);
    CFPropertyListWriteToStream(plist, stream, format, NULL);
    CFWriteStreamClose(stream);
}


@interface SPSiriInstaller : NSObject {

}

@end


@implementation SPSiriInstaller

- (NSSet *)files {
    static NSSet *cached = nil;

    if (cached == nil) {
        NSMutableSet *valid = [NSMutableSet set];
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

void progress_callback(ZipInfo *info, CDFile *file, size_t progress) {
    int percent = (progress * 100) / file->compressedSize;
    NSLog(@"\tdownload progress: %d", percent);
}

size_t downloadFileCallback(ZipInfo* info, CDFile* file, unsigned char *buffer, size_t size, void *userInfo)
{
	return fwrite(buffer, size, 1, userInfo) ? size : 0;
}

- (BOOL)downloadFile:(NSString *)path inZip:(ZipInfo *)info intoCachePath:(NSString *)output {
    NSString *cachePath = [kSPWorkingDirectory stringByAppendingString:output];

    [[NSFileManager defaultManager] createDirectoryAtPath:[cachePath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    FILE *fd = fopen([cachePath UTF8String], "wb");
    if (fd == NULL) { NSLog(@"Unable to write file to cache."); return NO; }

    NSLog(@"Finding file %@...", path);
    CDFile *file = PartialZipFindFile(info, [path UTF8String]);
    if (file == NULL) { NSLog(@"Unable to find file."); return NO; }
    NSLog(@"File found.");

    NSLog(@"Downloading file %@...", path);
    if (!PartialZipGetFile(info, file, downloadFileCallback, fd)) {
	    NSLog(@"Unable to download file!");
	    fclose(fd);
	    unlink([path UTF8String]);
	    return NO;
    }
    NSLog(@"File downloaded.");

    fclose(fd);

    return YES;
}

- (BOOL)downloadFiles {
    BOOL success = YES;

    NSLog(@"Opening remote ZIP...");
    ZipInfo *info = PartialZipInit([kSPUpdateZIPURL UTF8String]);

    for (NSString *path in [self files]) {
        NSString *zipPath = [kSPUpdateZIPRootPath stringByAppendingString:path];

        NSLog(@"Downloading file into cache: %@", path);
        success = [self downloadFile:zipPath inZip:info intoCachePath:path];
        if (!success) { NSLog(@"Unable to download file."); break; }
    }

    PartialZipRelease(info);

    return success;
}

- (BOOL)installItemAtCachePath:(NSString *)cachePath intoPath:(NSString *)path {
    BOOL success = YES;
    NSError *error = nil;

    NSString *resolvedCachePath = [kSPWorkingDirectory stringByAppendingString:cachePath];
    NSString *resolvedGlobalPath = [@"/" stringByAppendingString:path];

    NSLog(@"Installing file %@ -> %@", resolvedCachePath, resolvedGlobalPath);

    [[NSFileManager defaultManager] createDirectoryAtPath:[resolvedGlobalPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];

    // Assume that any file already there is valid (XXX: is this a valid assumption?)
    if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedGlobalPath]) {
        success = [[NSFileManager defaultManager] moveItemAtPath:resolvedCachePath toPath:resolvedGlobalPath error:&error];
        if (!success) { NSLog(@"Unable to move item into installed position. (%@)", [error localizedDescription]); return success; }
    }

    return success;
}

- (BOOL)installFiles {
    BOOL success = YES;

    for (NSString *path in [self files]) {
        success = [self installItemAtCachePath:path intoPath:path];
        if (!success) { NSLog(@"Unable to install file: %@", path); break; }
    }

    return success;
}

- (void)applyAlternativeSharedCacheToEnvironmentVariables:(NSMutableDictionary *)ev {
    if ([[ev objectForKey:@"DYLD_SHARED_CACHE_DIR"] length] == 0) {
        [ev setObject:@"/var/spire" forKey:@"DYLD_SHARED_CACHE_DIR"];
    }

    if ([[ev objectForKey:@"DYLD_SHARED_REGION"] length] == 0) {
        [ev setObject:@"private" forKey:@"DYLD_SHARED_REGION"];
    }

    if ([[ev objectForKey:@"DYLD_SHARED_CACHE_DONT_VALIDATE"] length] == 0) {
        [ev setObject:@"1" forKey:@"DYLD_SHARED_CACHE_DONT_VALIDATE"];
    }
}

- (BOOL)applyAlternativeCacheToDaemonAtPath:(const char *)path {
    NSLog(@"Patching cache into daemon: %s", path);

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

	[self applyAlternativeSharedCacheToEnvironmentVariables:ev];

    SavePropertyList(plist, "", url, kCFPropertyListBinaryFormat_v1_0);
    return NO;
}

- (BOOL)applyAlternativeCacheToAppAtPath:(const char *)path {
    NSLog(@"Patching cache into app: %s", path);

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

	[self applyAlternativeSharedCacheToEnvironmentVariables:ev];

    SavePropertyList(plist, "", url, kCFPropertyListBinaryFormat_v1_0);
    return YES;
}

- (BOOL)setupSharedCache {
    BOOL success = YES;

    // FIXME: this is arbitrary
    NSString *cachePath = @"dyldcache";

    ZipInfo *info = PartialZipInit([kSPUpdateZIPURL UTF8String]);
    PartialZipSetProgressCallback(info, progress_callback);

    success = [self downloadFile:[kSPUpdateZIPRootPath stringByAppendingString:@"System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv7"] inZip:info intoCachePath:cachePath];
    if (!success) { NSLog(@"Failed downloading shared cache."); return success; }

    PartialZipRelease(info);

    success = [self installItemAtCachePath:cachePath intoPath:@"/var/spire/dyld_shared_cache_armv7"];
    if (!success) { NSLog(@"Failed installing cache."); return success; }

    success = [self applyAlternativeCacheToAppAtPath:"/Applications/Preferences.app/Info.plist"];
    if (!success) { NSLog(@"Failed applying cache to Preferences."); return success; }

    success = [self applyAlternativeCacheToDaemonAtPath:"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist"];
    if (!success) { NSLog(@"Failed applying cache to SpringBoard."); return success; }

    return success;
}

- (BOOL)addCapabilities {
    static char platform[1024];
    size_t len = sizeof(platform);
    int ret = sysctlbyname("kern.ident", &platform, &len, NULL, 0);
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

    NSNumber *yes = [NSNumber numberWithBool:YES];
    [capabilities setObject:yes forKey:@"mars-volta"];
    [capabilities setObject:yes forKey:@"assistant"];

    SavePropertyList(plist, "", url, kCFPropertyListBinaryFormat_v1_0);

    return YES;
}

- (BOOL)createCache {
    NSLog(@"Creating cache directory.");
    return [[NSFileManager defaultManager] createDirectoryAtPath:kSPWorkingDirectory withIntermediateDirectories:NO attributes:nil error:NULL];
}

- (BOOL)cleanUp {
    NSLog(@"Cleaning up (if necessary).");
    return [[NSFileManager defaultManager] removeItemAtPath:kSPWorkingDirectory error:NULL];
}

- (BOOL)install {
    BOOL success = YES;

    /*[self cleanUp];

    success = [self createCache];
    if (!success) { NSLog(@"Failed creating cache."); return success; }

    success = [self downloadFiles];
    if (!success) { NSLog(@"Failed downloading files."); return success; }*/

    success = [self installFiles];
    if (!success) { NSLog(@"Failed installing files."); return success; }

    success = [self setupSharedCache];
    if (!success) { NSLog(@"Failed setting up shared cache."); return success; }

    success = [self addCapabilities];
    if (!success) { NSLog(@"Failed adding capabilities."); return success; }

    success = [self cleanUp];
    if (!success) { NSLog(@"Failed cleaning up."); return success; }

    return success;
}

@end


int main(int argc, char **argv, char **envp) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    SPSiriInstaller *installer = [[SPSiriInstaller alloc] init];
    [installer install];
    [installer release];

    [pool release];

	return 0;
}



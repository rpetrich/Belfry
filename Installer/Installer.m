
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

typedef struct {
    CDFile *lastFile;
    FILE *fd;
    size_t charactersToSkip;
} downloadCurrentFileData;

size_t downloadFileCallback(ZipInfo* info, CDFile* file, unsigned char *buffer, size_t size, void *userInfo)
{
	downloadCurrentFileData *fileData = userInfo;
	if (fileData->lastFile != file) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		if (fileData->lastFile)
			fclose(fileData->fd);
		fileData->lastFile = file;
		if (file) {
			unsigned char *zipFileName = PartialZipCopyFileName(info, file);
			NSString *diskFileName = [kSPWorkingDirectory stringByAppendingFormat:@"%s", zipFileName + fileData->charactersToSkip];
			NSLog(@"Downloading file %s...", zipFileName + fileData->charactersToSkip);
			free(zipFileName);
		    [[NSFileManager defaultManager] createDirectoryAtPath:[diskFileName stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
			fileData->fd = fopen([diskFileName UTF8String], "wb");
		}
		[pool drain];
	}
	return fwrite(buffer, size, 1, fileData->fd) ? size : 0;
}

- (ZipInfo *)openZipFile
{
    NSLog(@"Opening remote ZIP...");
    ZipInfo *info = PartialZipInit([kSPUpdateZIPURL UTF8String]);
    if (info)
	    NSLog(@"Remote ZIP opened...");
	else
		NSLog(@"Unable to open ZIP!");
	return info;
}

- (BOOL)downloadFilesFromZip:(ZipInfo *)info {
    BOOL success = YES;

	NSArray *files = [self files];

	NSInteger count = [files count];
	CDFile *fileReferences[count];
	int i = 0;
    for (NSString *path in files) {
        NSString *zipPath = [kSPUpdateZIPRootPath stringByAppendingString:path];
        CDFile *file = PartialZipFindFile(info, [zipPath UTF8String]);
        if (!file) {
        	NSLog(@"Unable to find file %@", path);
        	return NO;
        }
        fileReferences[i++] = file;
    }
    
	downloadCurrentFileData data = { NULL, NULL, 26 };
	PartialZipGetFiles(info, fileReferences, count, downloadFileCallback, &data);
	downloadFileCallback(info, NULL, NULL, 0, &data);

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

- (BOOL)setupSharedCacheFromZip:(ZipInfo *)info {
    BOOL success = YES;

	NSString *zipPath = [kSPUpdateZIPRootPath stringByAppendingString:@"System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv7"];
	CDFile *file = PartialZipFindFile(info, [zipPath UTF8String]);
	if (!file) { NSLog(@"Failed to find dyld_shared_cache_armv7"); return NO; }

	downloadCurrentFileData data = { NULL, NULL, 63 };
	success = PartialZipGetFile(info, file, downloadFileCallback, &data);
    if (!success) { NSLog(@"Failed downloading shared cache."); return success; }
	downloadFileCallback(info, NULL, NULL, 0, &data);

    success = [self installItemAtCachePath:@"dyld_shared_cache_armv7" intoPath:@"/var/spire/dyld_shared_cache_armv7"];
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

    [self cleanUp];

    success = [self createCache];
    if (!success) { NSLog(@"Failed creating cache."); return success; }

	ZipInfo *info = [self openZipFile];
	if (!info)
		return false;

    success = [self downloadFilesFromZip:info];
    if (!success) { PartialZipRelease(info); NSLog(@"Failed downloading files."); return success; }

    success = [self installFiles];
    if (!success) { PartialZipRelease(info); NSLog(@"Failed installing files."); return success; }

    success = [self setupSharedCacheFromZip:info];
    if (!success) { PartialZipRelease(info); NSLog(@"Failed setting up shared cache."); return success; }
    
    PartialZipRelease(info);

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



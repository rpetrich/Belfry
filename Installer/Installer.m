
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <CoreFoundation/CFPropertyList.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>
#include <stdint.h>

#include "partial.h"
#import "SPLogging.h"

#define kSPUpdateZIPURL @"http://appldnld.apple.com/iPhone4/041-3249.20111103.Qswe3/com_apple_MobileAsset_SoftwareUpdate/554f7813ac09d45256faad560b566814c983bd4b.zip"
#define kSPUpdateZIPRootPath @"AssetData/payload/replace/"
#define kSPWorkingDirectory @"/tmp/belfry/"

@interface UIImage (UIApplicationIconPrivate)
+ (UIImage *)_iconForResourceProxy:(id)resourceProxy format:(int)format;
+ (UIImage *)_iconForResourceProxy:(id)resourceProxy variant:(int)variant variantsScale:(float)scale;
+ (UIImage *)_applicationIconImageForBundleIdentifier:(id)bundleIdentifier roleIdentifier:(id)identifier format:(int)format scale:(float)scale;
+ (UIImage *)_applicationIconImageForBundleIdentifier:(id)bundleIdentifier roleIdentifier:(id)identifier format:(int)format;
+ (UIImage *)_applicationIconImageForBundleIdentifier:(id)bundleIdentifier format:(int)format scale:(float)scale;
+ (UIImage *)_applicationIconImageForBundleIdentifier:(id)bundleIdentifier format:(int)format;
+ (int)_iconVariantForUIApplicationIconFormat:(int)uiapplicationIconFormat scale:(float*)scale;
- (UIImage *)_applicationIconImageForFormat:(int)format precomposed:(BOOL)precomposed scale:(float)scale;
- (UIImage *)_applicationIconImageForFormat:(int)format precomposed:(BOOL)precomposed;
@end

void SavePropertyList(CFPropertyListRef plist, char *path, CFURLRef url, CFPropertyListFormat format) {
    if (path[0] != '\0')
        url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (uint8_t *) path, strlen(path), false);
    CFWriteStreamRef stream = CFWriteStreamCreateWithFile(kCFAllocatorDefault, url);
    CFWriteStreamOpen(stream);
    CFPropertyListWriteToStream(plist, stream, format, NULL);
    CFWriteStreamClose(stream);
}


@interface BFInstaller : NSObject {

}

@end


@implementation BFInstaller

- (NSArray *)directories {
    static NSArray *cached = nil;

    if (cached == nil) {
        NSMutableArray *valid = [NSMutableArray array];
        NSArray *files = [[NSString stringWithContentsOfFile:@"/var/belfry/files.txt" encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\n"];

        for (NSString *file in files) {
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
        NSArray *files = [[NSString stringWithContentsOfFile:@"/var/belfry/files.txt" encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\n"];

        for (NSString *file in files) {
            NSString *trimmedFile = [file stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmedFile length] && ![trimmedFile hasSuffix:@"/"] && ![trimmedFile hasPrefix:@"#"]) {
                [valid addObject:trimmedFile];
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
			free(zipFileName);
			SPLog(@"Downloading %s", zipFileName + fileData->charactersToSkip);

		    [[NSFileManager defaultManager] createDirectoryAtPath:[diskFileName stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
			fileData->fd = fopen([diskFileName UTF8String], "wb");
		}
		[pool drain];
	}
	return fwrite(buffer, size, 1, fileData->fd) ? size : 0;
}

- (ZipInfo *)openZipFile {
    ZipInfo *info = PartialZipInit([kSPUpdateZIPURL UTF8String]);
	return info;
}

- (BOOL)downloadFilesFromZip:(ZipInfo *)info {
    BOOL success = YES;

	NSArray *files = [self files];

	NSInteger count = [files count];
	CDFile *fileReferences[count];
	int i = 0;
	NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in files) {
        if ([fm fileExistsAtPath:[@"/" stringByAppendingString:path]])
            count--;
        else {
            NSString *zipPath = [kSPUpdateZIPRootPath stringByAppendingString:path];
            CDFile *file = PartialZipFindFile(info, [zipPath UTF8String]);
            if (file == NULL) {
                SPLog(@"Unable to find file %@", path);
                return NO;
            }
            fileReferences[i++] = file;
        }
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

    // Assume that any file already there is valid (XXX: is this a valid assumption?)
    if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedGlobalPath]) {
        success = [[NSFileManager defaultManager] moveItemAtPath:resolvedCachePath toPath:resolvedGlobalPath error:&error];
        if (!success) { SPLog(@"Unable to move item into installed position. (%@)", [error localizedDescription]); return success; }

        int ret = chmod([resolvedGlobalPath UTF8String], 0755);
        if (ret != 0) { success = NO; SPLog(@"Unable to chmod file: %d", errno); return success; }
    }

    return success;
}

- (BOOL)installFiles {
    BOOL success = YES;

    for (NSString *path in [self files]) {
        success = [self installItemAtCachePath:path intoPath:path];
        if (!success) { SPLog(@"Unable to install file: %@", path); break; }
    }

    return success;
}

- (BOOL)createDirectoriesInRootPath:(NSString *)path {
    BOOL success = YES;

    for (NSString *dir in [self directories]) {
        // creating directories is always successful: if it fails, the directory is already there!
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByAppendingString:dir] withIntermediateDirectories:NO attributes:nil error:NULL];
    }

    return success;
}

- (BOOL)createDirectories {
    return [self createDirectoriesInRootPath:@"/"];
}

- (void)applyAlternativeSharedCacheToEnvironmentVariables:(NSMutableDictionary *)ev {
    if ([[ev objectForKey:@"DYLD_SHARED_CACHE_DIR"] length] == 0) {
        [ev setObject:@"/var/belfry" forKey:@"DYLD_SHARED_CACHE_DIR"];
    }

    if ([[ev objectForKey:@"DYLD_SHARED_REGION"] length] == 0) {
        [ev setObject:@"private" forKey:@"DYLD_SHARED_REGION"];
    }

    if ([[ev objectForKey:@"DYLD_SHARED_CACHE_DONT_VALIDATE"] length] == 0) {
        [ev setObject:@"1" forKey:@"DYLD_SHARED_CACHE_DONT_VALIDATE"];
    }
}

- (BOOL)applyAlternativeCacheAndDeviceFamilyToAppAtPath:(const char *)path {
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

    NSNumber *two = [NSNumber numberWithInteger:2];
    NSMutableArray *df = [root objectForKey:@"UIDeviceFamily"];
    if (![df containsObject:two]) {
        if (df == nil) {
            df = [NSMutableArray array];
            [root setObject:ev forKey:@"UIDeviceFamily"];
        }
        [df addObject:two];
    }

    SavePropertyList(plist, "", url, kCFPropertyListBinaryFormat_v1_0);
    return YES;
}

- (BOOL)setupSharedCacheFromZip:(ZipInfo *)info {
    BOOL success = YES;

    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/belfry/dyld_shared_cache_armv7"]) {
    	NSString *zipPath = [kSPUpdateZIPRootPath stringByAppendingString:@"System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv7"];
    	CDFile *file = PartialZipFindFile(info, [zipPath UTF8String]);
    	if (!file) { SPLog(@"Failed to find dyld_shared_cache_armv7"); return NO; }
    
    	downloadCurrentFileData data = { NULL, NULL, 63 };
    	success = PartialZipGetFile(info, file, downloadFileCallback, &data);
        if (!success) { SPLog(@"Failed downloading shared cache."); return success; }
    	downloadFileCallback(info, NULL, NULL, 0, &data);
    
        success = [self installItemAtCachePath:@"dyld_shared_cache_armv7" intoPath:@"var/belfry/dyld_shared_cache_armv7"];
        if (!success) { SPLog(@"Failed installing cache."); return success; }
    }

    success = [self applyAlternativeCacheAndDeviceFamilyToAppAtPath:"/Applications/MobileTimer.app/Info.plist"];
    if (!success) { SPLog(@"Failed applying cache to MobileTimer."); return success; }

    success = [self applyAlternativeCacheAndDeviceFamilyToAppAtPath:"/Applications/Weather.app/Info.plist"];
    if (!success) { SPLog(@"Failed applying cache to Weather."); return success; }

    success = [self applyAlternativeCacheAndDeviceFamilyToAppAtPath:"/Applications/Stocks.app/Info.plist"];
    if (!success) { SPLog(@"Failed applying cache to Stocks."); return success; }

    return success;
}

- (BOOL)generateIconForAppAtPath:(NSString *)path
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    UIImage *originalImage = [[UIImage alloc] initWithContentsOfFile:[path stringByAppendingPathComponent:@"icon@2x.png"]];
    CGImageRef croppedImage = CGImageCreateWithImageInRect(originalImage.CGImage, CGRectMake(2.0f, 1.0f, 114.0f, 114.0f));
    [originalImage release];
    UIImage *newImage = [[UIImage imageWithCGImage:croppedImage] _applicationIconImageForFormat:2 precomposed:YES];
    CGImageRelease(croppedImage);
    BOOL result = [UIImagePNGRepresentation(newImage) writeToFile:[path stringByAppendingPathComponent:@"Icon-72.png"] atomically:YES];
    [pool drain];
    return result;
}

- (BOOL)generateIcons {
    BOOL success = YES;

    success = [self generateIconForAppAtPath:@"/Applications/MobileTimer.app"];
    if (!success) { SPLog(@"Failed generating icon for MobileTimer."); return success; }

    success = [self generateIconForAppAtPath:@"/Applications/Weather.app"];
    if (!success) { SPLog(@"Failed generating icon for Weather."); return success; }

    success = [self generateIconForAppAtPath:@"/Applications/Stocks.app"];
    if (!success) { SPLog(@"Failed generating icon for Stocks."); return success; }

    success = [self generateIconForAppAtPath:@"/Applications/VoiceMemos.app"];
    if (!success) { SPLog(@"Failed generating icon for VoiceMemos."); return success; }

    return success;
}

- (BOOL)createCache {
    BOOL success =  YES;

    success = [[NSFileManager defaultManager] createDirectoryAtPath:kSPWorkingDirectory withIntermediateDirectories:NO attributes:nil error:NULL];
    success = [self createDirectoriesInRootPath:kSPWorkingDirectory];

    return success;
}

- (BOOL)cleanUp {
    return [[NSFileManager defaultManager] removeItemAtPath:kSPWorkingDirectory error:NULL];
}

- (BOOL)install {
    BOOL success = YES;

    SPLog(@"Preparing...");
    [self cleanUp];

    SPLog(@"Creating download cache.");
    success = [self createCache];
    if (!success) { SPLog(@"Failed creating cache."); return success; }

    SPLog(@"Opening remote ZIP.");
	ZipInfo *info = [self openZipFile];
	if (!info) { [self cleanUp]; return false; }

    SPLog(@"Downloading files to cache.");
    success = [self downloadFilesFromZip:info];
    if (!success) { PartialZipRelease(info); [self cleanUp]; SPLog(@"Failed downloading files."); return success; }

    SPLog(@"Creating install directories.");
    success = [self createDirectories];
    if (!success) { PartialZipRelease(info); [self cleanUp]; SPLog(@"Failed creating directories."); return success; }

    SPLog(@"Installing downloaded files.");
    success = [self installFiles];
    if (!success) { PartialZipRelease(info); [self cleanUp];  SPLog(@"Failed installing files."); return success; }

    SPLog(@"Generating icons.");
    success = [self generateIcons];
    if (!success) { PartialZipRelease(info); [self cleanUp];  SPLog(@"Failed generating icons."); return success; }

    SPLog(@"Setting up shared cache.");
    success = [self setupSharedCacheFromZip:info];
    if (!success) { PartialZipRelease(info); [self cleanUp];  SPLog(@"Failed setting up shared cache."); return success; }

    PartialZipRelease(info);

    SPLog(@"Cleaning up.");
    [self cleanUp];

    SPLog(@"Done!");
    return success;
}

@end


int main(int argc, char **argv, char **envp) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    BFInstaller *installer = [[BFInstaller alloc] init];
    BOOL success = [installer install];
    [installer release];

    [pool release];

	return (success ? 0 : 1);
}



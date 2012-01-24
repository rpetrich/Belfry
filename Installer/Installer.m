
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

@interface UIImage (UIImageInternal)
+ (void)_flushCacheOnMemoryWarning:(id)warning;
+ (void)_flushSharedImageCache;
- (id)_imageScaledToProportion:(float)proportion interpolationQuality:(CGInterpolationQuality)quality;
- (id)_doubleBezeledImageWithExteriorShadowRed:(float)exteriorShadowRed green:(float)green blue:(float)blue alpha:(float)alpha interiorShadowRed:(float)red green:(float)green6 blue:(float)blue7 alpha:(float)alpha8 fillRed:(float)red9 green:(float)green10 blue:(float)blue11 alpha:(float)alpha12;
- (id)_bezeledImageWithShadowRed:(float)shadowRed green:(float)green blue:(float)blue alpha:(float)alpha fillRed:(float)red green:(float)green6 blue:(float)blue7 alpha:(float)alpha8 drawShadow:(BOOL)shadow;
- (id)_flatImageWithWhite:(float)white alpha:(float)alpha;
- (BOOL)_isNamed;
- (void)_setNamed:(BOOL)named;
- (BOOL)_hasBeenCached;
- (BOOL)_isCached;
- (void)_setCached:(BOOL)cached;
@end

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
			//SPLog(@"Downloading %s", zipFileName + fileData->charactersToSkip);

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

- (BOOL)updateAppInfoPlist:(const char *)path alternativeCache:(BOOL)alternativeCache deviceFamily:(BOOL)deviceFamily largeIcon:(BOOL)largeIcon {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (uint8_t *) path, strlen(path), false);

    CFPropertyListRef plist; {
        CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
        CFReadStreamOpen(stream);
        plist = CFPropertyListCreateFromStream(kCFAllocatorDefault, stream, 0, kCFPropertyListMutableContainers, NULL, NULL);
        CFReadStreamClose(stream);
    }
    
    NSMutableDictionary *root = (NSMutableDictionary *) plist;
    if (root == nil) return NO;

    bool updated = false;

    if (alternativeCache) {
        NSMutableDictionary *ev = [root objectForKey:@"LSEnvironment"];
        if (ev == nil) {
            ev = [NSMutableDictionary dictionary];
            [root setObject:ev forKey:@"LSEnvironment"];
        }
    	[self applyAlternativeSharedCacheToEnvironmentVariables:ev];
    	updated = true;
    }

    if (deviceFamily) {
        NSNumber *two = [NSNumber numberWithInteger:2];
        NSMutableArray *df = [root objectForKey:@"UIDeviceFamily"];
        if (![df containsObject:two]) {
            if (df == nil) {
                df = [NSMutableArray array];
                [root setObject:df forKey:@"UIDeviceFamily"];
            }
            [df addObject:two];
            updated = true;
        }
    }
    
    if (largeIcon) {
        NSMutableArray *icons = [root objectForKey:@"CFBundleIconFiles"];
        if (![icons containsObject:@"Icon-72.png"]) {
            if (icons == nil) {
                icons = [NSMutableArray array];
                [root setObject:icons forKey:@"CFBundleIconFiles"];
            }
            [icons addObject:@"Icon-72.png"];
            updated = true;
        }
    }

    if (updated)
        SavePropertyList(plist, "", url, kCFPropertyListBinaryFormat_v1_0);
    CFRelease(url);
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

    success = [self updateAppInfoPlist:"/Applications/Calculator.app/Info.plist" alternativeCache:NO deviceFamily:NO largeIcon:YES];
    if (!success) { SPLog(@"Failed updating Info.plist on Calculator."); return success; }

    success = [self updateAppInfoPlist:"/Applications/Compass.app/Info.plist" alternativeCache:NO deviceFamily:YES largeIcon:YES];
    if (!success) { SPLog(@"Failed updating Info.plist on Compass."); return success; }

    success = [self updateAppInfoPlist:"/Applications/MobileTimer.app/Info.plist" alternativeCache:YES deviceFamily:YES largeIcon:YES];
    if (!success) { SPLog(@"Failed updating Info.plist on MobileTimer."); return success; }

    success = [self updateAppInfoPlist:"/Applications/VoiceMemos.app/Info.plist" alternativeCache:NO deviceFamily:YES largeIcon:YES];
    if (!success) { SPLog(@"Failed updating Info.plist on VoiceMemos."); return success; }

    success = [self updateAppInfoPlist:"/Applications/Weather.app/Info.plist" alternativeCache:YES deviceFamily:NO largeIcon:YES];
    if (!success) { SPLog(@"Failed updating Info.plist on Weather."); return success; }

    success = [self updateAppInfoPlist:"/Applications/Stocks.app/Info.plist" alternativeCache:YES deviceFamily:YES largeIcon:YES];
    if (!success) { SPLog(@"Failed updating Info.plist on Stocks."); return success; }

    return success;
}

- (BOOL)generateResizedIconAtPath:(NSString *)destPath from2xIconAtPath:(NSString *)sourcePath
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    UIImage *originalImage = [[UIImage alloc] initWithContentsOfFile:sourcePath];
    CGImageRef croppedImage = CGImageCreateWithImageInRect(originalImage.CGImage, CGRectMake(2.0f, 1.0f, 114.0f, 114.0f));
    [originalImage release];
    UIImage *newImage = [[UIImage imageWithCGImage:croppedImage] _applicationIconImageForFormat:2 precomposed:YES];
    CGImageRelease(croppedImage);
    BOOL result = [UIImagePNGRepresentation(newImage) writeToFile:destPath atomically:YES];
    [pool drain];
    return result;
}

- (BOOL)generateIcons {
    BOOL success = YES;

    success = [self generateResizedIconAtPath:@"/Applications/Calculator.app/Icon-72.png" from2xIconAtPath:@"/Applications/Calculator.app/icon@2x.png"];
    if (!success) { SPLog(@"Failed generating icon for Calculator."); return success; }

    success = [self generateResizedIconAtPath:@"/Applications/Compass.app/Icon-72.png" from2xIconAtPath:@"/Applications/Compass.app/Icon@2x.png"];
    if (!success) { SPLog(@"Failed generating icon for Compass."); return success; }

    success = [self generateResizedIconAtPath:@"/Applications/MobileTimer.app/Icon-72.png" from2xIconAtPath:@"/Applications/MobileTimer.app/icon@2x.png"];
    if (!success) { SPLog(@"Failed generating icon for MobileTimer."); return success; }

    success = [self generateResizedIconAtPath:@"/Applications/Weather.app/Icon-72.png" from2xIconAtPath:@"/Applications/Weather.app/icon@2x.png"];
    if (!success) { SPLog(@"Failed generating icon for Weather."); return success; }

    success = [self generateResizedIconAtPath:@"/Applications/Weather.app/Icon-Celsius-72.png" from2xIconAtPath:@"/Applications/Weather.app/Icon-Celsius@2x.png"];
    if (!success) { SPLog(@"Failed generating celsius icon for Weather."); return success; }

    success = [self generateResizedIconAtPath:@"/Applications/Stocks.app/Icon-72.png" from2xIconAtPath:@"/Applications/Stocks.app/icon@2x.png"];
    if (!success) { SPLog(@"Failed generating icon for Stocks."); return success; }

    success = [self generateResizedIconAtPath:@"/Applications/VoiceMemos.app/Icon-72.png" from2xIconAtPath:@"/Applications/VoiceMemos.app/icon@2x.png"];
    if (!success) { SPLog(@"Failed generating icon for VoiceMemos."); return success; }

    return success;
}

- (BOOL)generateResizedImages {
    NSFileManager *fm = [[NSFileManager alloc] init];
    for (NSString *path in [self files]) {
        if ([path hasSuffix:@"@2x.png"]) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSString *realPath = [@"/" stringByAppendingString:path];
            NSString *resizedPath = [[realPath substringToIndex:[realPath length] - 7] stringByAppendingString:@".png"];
            if ([fm fileExistsAtPath:realPath] && ![fm fileExistsAtPath:resizedPath]) {
                UIImage *originalImage = [[UIImage alloc] initWithContentsOfFile:realPath];
                UIImage *resizedImage = [originalImage _imageScaledToProportion:0.5f interpolationQuality:kCGInterpolationHigh];
                [originalImage release];
                BOOL success = [UIImagePNGRepresentation(resizedImage) writeToFile:resizedPath atomically:YES];
                if (!success) {
                    SPLog(@"Failed resizing %@", path);
                    [pool drain];
                    [fm release];
                    return NO;
                }
            }
            [pool drain];
        }
    }
    [fm release];
    return YES;
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

    SPLog(@"Generating resized images.");
    success = [self generateResizedImages];
    if (!success) { PartialZipRelease(info); [self cleanUp];  SPLog(@"Failed generating resized images."); return success; }

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



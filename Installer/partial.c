#include <curl/curl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <zlib.h>
#include <libgen.h>
#include <machine/endian.h>

#include "partial.h"

#define FLIPENDIANLE(x) flipEndianLE((unsigned char *)(&(x)), sizeof(x))

static inline void flipEndianLE(unsigned char* x, int length) {
#if BYTE_ORDER == BIG_ENDIAN
	int i;
	unsigned char tmp;

	for(i = 0; i < (length / 2); i++) {
		tmp = x[i];
		x[i] = x[length - i - 1];
		x[length - i - 1] = tmp;
	}
#endif
}


static size_t dummyReceive(void* data, size_t size, size_t nmemb, void* info) {
	return size * nmemb;
}

static size_t receiveCentralDirectoryEnd(void* data, size_t size, size_t nmemb, ZipInfo* info) {
	memcpy(info->centralDirectoryEnd + info->centralDirectoryEndRecvd, data, size * nmemb);
	info->centralDirectoryEndRecvd += size * nmemb;
	return size * nmemb;
}

static size_t receiveCentralDirectory(void* data, size_t size, size_t nmemb, ZipInfo* info) {
	memcpy(info->centralDirectory + info->centralDirectoryRecvd, data, size * nmemb);
	info->centralDirectoryRecvd += size * nmemb;
	return size * nmemb;
}

static size_t receiveData(void* data, size_t size, size_t nmemb, void** pFileData) {
	memcpy(pFileData[0], data, size * nmemb);
	pFileData[0] = ((char*)pFileData[0]) + (size * nmemb);
	ZipInfo* info = ((ZipInfo*)pFileData[1]);
	CDFile* file = ((CDFile*)pFileData[2]);
	size_t* progress = ((size_t*)pFileData[3]);

	if(progress) {
		*progress += size * nmemb;
	}

	if(info && info->progressCallback && file) {
		info->progressCallback(info, file, *progress);
	}

	return size * nmemb;
}

static void flipFiles(ZipInfo* info)
{
	char* cur = info->centralDirectory;

	unsigned int i;
	for(i = 0; i < info->centralDirectoryDesc->CDEntries; i++)
	{
		CDFile* candidate = (CDFile*) cur;
		FLIPENDIANLE(candidate->signature);
		FLIPENDIANLE(candidate->version);
		FLIPENDIANLE(candidate->versionExtract);
		// FLIPENDIANLE(candidate->flags);
		FLIPENDIANLE(candidate->method);
		FLIPENDIANLE(candidate->modTime);
		FLIPENDIANLE(candidate->modDate);
		// FLIPENDIANLE(candidate->crc32);
		FLIPENDIANLE(candidate->compressedSize);
		FLIPENDIANLE(candidate->size);
		FLIPENDIANLE(candidate->lenFileName);
		FLIPENDIANLE(candidate->lenExtra);
		FLIPENDIANLE(candidate->lenComment);
		FLIPENDIANLE(candidate->diskStart);
		// FLIPENDIANLE(candidate->internalAttr);
		// FLIPENDIANLE(candidate->externalAttr);
		FLIPENDIANLE(candidate->offset);

		cur += sizeof(CDFile) + candidate->lenFileName + candidate->lenExtra + candidate->lenComment;
	}
}

ZipInfo* PartialZipInit(const char* url)
{
	ZipInfo* info = (ZipInfo*) malloc(sizeof(ZipInfo));
	info->url = strdup(url);
	info->centralDirectoryRecvd = 0;
	info->centralDirectoryEndRecvd = 0;
	info->centralDirectoryDesc = NULL;
	info->progressCallback = NULL;

	info->hIPSW = curl_easy_init();

	curl_easy_setopt(info->hIPSW, CURLOPT_URL, info->url);
	curl_easy_setopt(info->hIPSW, CURLOPT_FOLLOWLOCATION, 1);
	curl_easy_setopt(info->hIPSW, CURLOPT_NOBODY, 1);
	curl_easy_setopt(info->hIPSW, CURLOPT_WRITEFUNCTION, dummyReceive);

	if(strncmp(info->url, "file://", 7) == 0)
	{
		char path[1024];
		strcpy(path, info->url + 7);
		char* filePath = (char*) curl_easy_unescape(info->hIPSW, path, 0,  NULL);
		FILE* f = fopen(filePath, "rb");
		if(!f)
		{
			curl_free(filePath);
			curl_easy_cleanup(info->hIPSW);
			free(info->url);
			free(info);

			return NULL;
		}

		fseek(f, 0, SEEK_END);
		info->length = ftell(f);
		fclose(f);

		curl_free(filePath);
	}
	else
	{
		curl_easy_perform(info->hIPSW);

		double dFileLength;
		curl_easy_getinfo(info->hIPSW, CURLINFO_CONTENT_LENGTH_DOWNLOAD, &dFileLength);
		info->length = dFileLength;
	}

	char sRange[100];
	uint64_t start;

	if(info->length > (0xffff + sizeof(EndOfCD)))
		start = info->length - 0xffff - sizeof(EndOfCD);
	else
		start = 0;

	uint64_t end = info->length - 1;

	sprintf(sRange, "%" PRIu64 "-%" PRIu64, start, end);

	curl_easy_setopt(info->hIPSW, CURLOPT_WRITEFUNCTION, receiveCentralDirectoryEnd);
	curl_easy_setopt(info->hIPSW, CURLOPT_WRITEDATA, info);
	curl_easy_setopt(info->hIPSW, CURLOPT_RANGE, sRange);
	curl_easy_setopt(info->hIPSW, CURLOPT_HTTPGET, 1);

	curl_easy_perform(info->hIPSW);

	char* cur;
	for(cur = info->centralDirectoryEnd; cur < (info->centralDirectoryEnd + (end - start - 1)); cur++)
	{
		EndOfCD* candidate = (EndOfCD*) cur;
		uint32_t signature = candidate->signature;
		FLIPENDIANLE(signature);
		if(signature == 0x06054b50)
		{
			uint16_t lenComment = candidate->lenComment;
			FLIPENDIANLE(lenComment);
			if((cur + lenComment + sizeof(EndOfCD)) == (info->centralDirectoryEnd + info->centralDirectoryEndRecvd))
			{
				FLIPENDIANLE(candidate->diskNo);
				FLIPENDIANLE(candidate->CDDiskNo);
				FLIPENDIANLE(candidate->CDDiskEntries);
				FLIPENDIANLE(candidate->CDEntries);
				FLIPENDIANLE(candidate->CDSize);
				FLIPENDIANLE(candidate->CDOffset);
				FLIPENDIANLE(candidate->lenComment);
				info->centralDirectoryDesc = candidate;
				break;
			}
		}

	}

	if(info->centralDirectoryDesc)
	{
		info->centralDirectory = malloc(info->centralDirectoryDesc->CDSize);
		start = info->centralDirectoryDesc->CDOffset;
		end = start + info->centralDirectoryDesc->CDSize - 1;
		sprintf(sRange, "%" PRIu64 "-%" PRIu64, start, end);
		curl_easy_setopt(info->hIPSW, CURLOPT_WRITEFUNCTION, receiveCentralDirectory);
		curl_easy_setopt(info->hIPSW, CURLOPT_WRITEDATA, info);
		curl_easy_setopt(info->hIPSW, CURLOPT_RANGE, sRange);
		curl_easy_setopt(info->hIPSW, CURLOPT_HTTPGET, 1);
		curl_easy_perform(info->hIPSW);

		flipFiles(info);

		return info;
	}
	else 
	{
		curl_easy_cleanup(info->hIPSW);
		free(info->url);
		free(info);
		return NULL;
	}
}

CDFile* PartialZipFindFile(ZipInfo* info, const char* fileName)
{
	char* cur = info->centralDirectory;
	unsigned int i;
	for(i = 0; i < info->centralDirectoryDesc->CDEntries; i++)
	{
		CDFile* candidate = (CDFile*) cur;
		const char* curFileName = cur + sizeof(CDFile);

		if(strlen(fileName) == candidate->lenFileName && strncmp(fileName, curFileName, candidate->lenFileName) == 0)
			return candidate;

		cur += sizeof(CDFile) + candidate->lenFileName + candidate->lenExtra + candidate->lenComment;
	}

	return NULL;
}

CDFile* PartialZipListFiles(ZipInfo* info)
{
	char* cur = info->centralDirectory;
	unsigned int i;
	for(i = 0; i < info->centralDirectoryDesc->CDEntries; i++)
	{
		CDFile* candidate = (CDFile*) cur;
		const char* curFileName = cur + sizeof(CDFile);
		char* myFileName = (char*) malloc(candidate->lenFileName + 1);
		memcpy(myFileName, curFileName, candidate->lenFileName);
		myFileName[candidate->lenFileName] = '\0';

		printf("%s: method: %d, compressed size: %d, size: %d\n", myFileName, candidate->method,
				candidate->compressedSize, candidate->size);

		free(myFileName);

		cur += sizeof(CDFile) + candidate->lenFileName + candidate->lenExtra + candidate->lenComment;
	}

	return NULL;
}

typedef struct {
	ZipInfo *info;
	CDFile *file;
	PartialZipGetFileCallback callback;
	void *userInfo;
	z_stream stream; // Unused for uncompressed data
} ReceiveDataBodyData;

#define ZLIB_BUFFER_SIZE 4096

static size_t receiveDataBodyUncompressed(void* data, size_t size, size_t nmemb, ReceiveDataBodyData *pFileData) {
	return pFileData->callback(pFileData->info, pFileData->file, data, size * nmemb, pFileData->userInfo);
}

static size_t receiveDataBodyZLIBCompressed(void* data, size_t size, size_t nmemb, ReceiveDataBodyData *pFileData) {
	pFileData->stream.next_in = data;
	size_t result = size * nmemb;
	pFileData->stream.avail_in = result;
	unsigned char buffer[ZLIB_BUFFER_SIZE];
	do {
		pFileData->stream.next_out = buffer;
		pFileData->stream.avail_out = ZLIB_BUFFER_SIZE;
		int err = inflate(&pFileData->stream, Z_NO_FLUSH);
		if (pFileData->stream.avail_out != ZLIB_BUFFER_SIZE) {
			size_t new_bytes = ZLIB_BUFFER_SIZE - pFileData->stream.avail_out;
			size_t bytes_read = pFileData->callback(pFileData->info, pFileData->file, buffer, new_bytes, pFileData->userInfo);
			if (bytes_read != new_bytes) {
				// Abort if callback doesn't read all data
				return 0;
			}
		}
		switch (err) {
			case Z_OK:
			case Z_STREAM_END:
				break;
			default:
				// Abort if there's some sort of zlib stream error
				return 0;
		}
	} while (pFileData->stream.avail_in);
	return result;
}

bool PartialZipGetFile(ZipInfo* info, CDFile* file, PartialZipGetFileCallback callback, void *userInfo)
{
	LocalFile localHeader;
	LocalFile* pLocalHeader = &localHeader;

	uint64_t start = file->offset;
	uint64_t end = file->offset + sizeof(LocalFile) - 1;
	char sRange[100];
	sprintf(sRange, "%" PRIu64 "-%" PRIu64, start, end);

	void* pFileHeader[] = {pLocalHeader, NULL, NULL, NULL}; 

	curl_easy_setopt(info->hIPSW, CURLOPT_URL, info->url);
	curl_easy_setopt(info->hIPSW, CURLOPT_FOLLOWLOCATION, 1);
	curl_easy_setopt(info->hIPSW, CURLOPT_WRITEFUNCTION, receiveData);
	curl_easy_setopt(info->hIPSW, CURLOPT_WRITEDATA, &pFileHeader);
	curl_easy_setopt(info->hIPSW, CURLOPT_RANGE, sRange);
	curl_easy_setopt(info->hIPSW, CURLOPT_HTTPGET, 1);
	curl_easy_perform(info->hIPSW);
	
	FLIPENDIANLE(localHeader.signature);
	FLIPENDIANLE(localHeader.versionExtract);
	// FLIPENDIANLE(localHeader.flags);
	FLIPENDIANLE(localHeader.method);
	FLIPENDIANLE(localHeader.modTime);
	FLIPENDIANLE(localHeader.modDate);
	// FLIPENDIANLE(localHeader.crc32);
	FLIPENDIANLE(localHeader.compressedSize);
	FLIPENDIANLE(localHeader.size);
	FLIPENDIANLE(localHeader.lenFileName);
	FLIPENDIANLE(localHeader.lenExtra);

	start = file->offset + sizeof(LocalFile) + localHeader.lenFileName + localHeader.lenExtra;
	end = start + file->compressedSize - 1;
	sprintf(sRange, "%" PRIu64 "-%" PRIu64, start, end);

	curl_easy_setopt(info->hIPSW, CURLOPT_RANGE, sRange);
	curl_easy_setopt(info->hIPSW, CURLOPT_HTTPGET, 1);
	ReceiveDataBodyData fileData = { info, file, callback, userInfo };
	fileData.info = info;
	fileData.file = file;
	fileData.callback = callback;
	fileData.userInfo = userInfo;
	switch (file->method) {
		case 8:
			fileData.stream.zalloc = Z_NULL;
			fileData.stream.zfree = Z_NULL;
			fileData.stream.opaque = Z_NULL;
			fileData.stream.avail_in = 0;
			fileData.stream.next_in = NULL;
			inflateInit2(&fileData.stream, -MAX_WBITS);
			curl_easy_setopt(info->hIPSW, CURLOPT_WRITEFUNCTION, receiveDataBodyZLIBCompressed);
			break;
		default:
			curl_easy_setopt(info->hIPSW, CURLOPT_WRITEFUNCTION, receiveDataBodyUncompressed);
			break;
	}
	curl_easy_setopt(info->hIPSW, CURLOPT_WRITEDATA, &fileData);
	int curl_result = curl_easy_perform(info->hIPSW);
	switch (file->method) {
		case 8: {
			if (curl_result != 0) {
				inflateEnd(&fileData.stream);
				return false;
			}
			unsigned char buffer[ZLIB_BUFFER_SIZE];
			int err;
			do {
				fileData.stream.next_out = buffer;
				fileData.stream.avail_out = ZLIB_BUFFER_SIZE;
				err = inflate(&fileData.stream, Z_SYNC_FLUSH);
				if (fileData.stream.avail_out != ZLIB_BUFFER_SIZE) {
					size_t new_bytes = ZLIB_BUFFER_SIZE - fileData.stream.avail_out;
					size_t bytes_read = callback(info, file, buffer, new_bytes, userInfo);
					if (bytes_read != new_bytes) {
						// Abort if callback doesn't read all data
						inflateEnd(&fileData.stream);
						return false;
					}
				}
			} while (err == Z_OK);
			inflateEnd(&fileData.stream);
			return err == Z_STREAM_END;
		}
		default:
			return curl_result == 0;
	}
}

void PartialZipSetProgressCallback(ZipInfo* info, PartialZipProgressCallback progressCallback)
{
	info->progressCallback = progressCallback;
}

void PartialZipRelease(ZipInfo* info)
{
	curl_easy_cleanup(info->hIPSW);
	free(info->centralDirectory);
	free(info->url);
	free(info);

	curl_global_cleanup();
}


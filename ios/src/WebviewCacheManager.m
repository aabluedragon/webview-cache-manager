
#import "WebviewCacheManager.h"
#import <sqlite3.h>

@implementation WebviewCacheManager

- (void)clearCookies:(CDVInvokedUrlCommand *)command {
    @try {
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in [storage cookies]) {
            [storage deleteCookie:cookie];
        }
        [[NSUserDefaults standardUserDefaults] synchronize];

        [self.commandDelegate sendPluginResult:
         [CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:[command callbackId]];
    } @catch (NSException *exception) {
        [self.commandDelegate sendPluginResult:
         [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:exception.description]
                                    callbackId:[command callbackId]];
    }
}

- (void)clearAppCacheByUrl:(CDVInvokedUrlCommand *)command {

    @try {
        NSArray *urls = [command.arguments objectAtIndex:0];
        BOOL exceptGivenUrls = [[command.arguments objectAtIndex:1] boolValue];
        BOOL likeFormat = [[command.arguments objectAtIndex:2] boolValue];

        [self clearCacheForCacheManifestURLs:urls ExceptGivenUrls:exceptGivenUrls UrlsAreSqlLikeFormatted:likeFormat];
        [self.commandDelegate sendPluginResult:
         [CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:[command callbackId]];
    } @catch (NSException *exception) {
        [self.commandDelegate sendPluginResult:
         [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:exception.description]
                                    callbackId:[command callbackId]];
    }

}

- (void)clearBrowserCache:(CDVInvokedUrlCommand *)command {
    @try {
        [[NSURLCache sharedURLCache] removeAllCachedResponses];

        [self.commandDelegate sendPluginResult:
         [CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:[command callbackId]];
    } @catch (NSException *exception) {
        [self.commandDelegate sendPluginResult:
         [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:exception.description]
                                    callbackId:[command callbackId]];
    }
}

- (void)clearAllAppCache:(CDVInvokedUrlCommand *)command {

    @try {
        [self clearCacheForCacheManifestURLs:@[] ExceptGivenUrls:YES UrlsAreSqlLikeFormatted:NO];

        [self.commandDelegate sendPluginResult:
         [CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:[command callbackId]];
    } @catch (NSException *exception) {
        [self.commandDelegate sendPluginResult:
         [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:exception.description]
                                    callbackId:[command callbackId]];
    }

}

static NSString *cacheDatabaseName = @"ApplicationCache.db";
static NSString *cacheGroupTable = @"CacheGroups";
static NSString *cacheGroupTableManifestURLColums = @"manifestURL";
static NSString *cacheTable = @"Caches";
static NSString *cacheTableCacheGroupId = @"cacheGroup";

/**
 Clears the cached resources associated to a cache group.

 @param manifestURLs An array of `NSString` containing the URLs of the cache manifests for which you want to clear the resources.
 */
- (void)clearCacheForCacheManifestURLs:(NSArray *)manifestURLs ExceptGivenUrls:(BOOL)except UrlsAreSqlLikeFormatted:(BOOL)usedSqlLikes {

    if(!except && manifestURLs) {
        return; //clearing nothing, no URLs given.
    }

    if(usedSqlLikes) {
        manifestURLs = [self partialToDbStoredManifestFullUrls:manifestURLs];
    }

    sqlite3 *newDBconnection;

    /*Check that the db is created, if not we return as sqlite3_open would create
     an empty database and webkit will crash on us when accessing this empty database*/
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self cacheDatabasePath]]) {
        NSLog(@"The cache manifest db has not been created by Webkit yet");
        return;
    }

    if (sqlite3_open([[self cacheDatabasePath]  UTF8String], &newDBconnection) == SQLITE_OK) {

        if (sqlite3_exec(newDBconnection, "BEGIN EXCLUSIVE TRANSACTION", 0, 0, 0) != SQLITE_OK) {
            NSLog(@"SQL Error: %s",sqlite3_errmsg(newDBconnection));
        }
        else {
            /*Get the cache group IDs associated to the cache manifests' URLs*/
            NSArray *cacheGroupIds = [self getCacheGroupIdForURLsIn:manifestURLs usingDBConnection:newDBconnection AllExceptUrls:except];
            /*Remove the corresponding entries in the Caches and CacheGroups tables*/
            [self deleteCacheResourcesInCacheGroups:cacheGroupIds usingDBConnection:newDBconnection];
            [self deleteCacheGroups:cacheGroupIds usingDBConnection:newDBconnection];
            if (sqlite3_exec(newDBconnection, "COMMIT TRANSACTION", 0, 0, 0) != SQLITE_OK) NSLog(@"SQL Error: %s",sqlite3_errmsg(newDBconnection));
        }

        sqlite3_close(newDBconnection);

    } else {
        NSLog(@"Error opening the database located at: %@", [self cacheDatabasePath]);
        newDBconnection = NULL;
    }

}

- (NSArray *)getCacheGroupIdForURLsIn:(NSArray *)urls usingDBConnection:(sqlite3 *)db AllExceptUrls:(BOOL)except {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:0];
    sqlite3_stmt    *statement;

    NSString *queryString = urls.count>0?
        [NSString stringWithFormat:@"SELECT id FROM %@ WHERE %@ %@ (%@)", cacheGroupTable,cacheGroupTableManifestURLColums, except?@"NOT IN":@"IN",[self commaSeparatedValuesFromArray:urls]]
    :   [NSString stringWithFormat:@"SELECT id FROM %@", cacheGroupTable];
    const char *query = [queryString UTF8String];

    if (sqlite3_prepare_v2(db, query, -1, &statement, NULL) == SQLITE_OK)
    {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            int id = sqlite3_column_int(statement, 0);
            [result addObject:[NSNumber numberWithInt:id]];
        }
    }
    else {
        NSLog(@"SQL Error: %s",sqlite3_errmsg(db));
    }
    sqlite3_finalize(statement);
    return result;
}

/**
 Delete the rows in the CacheGroups table associated to the cache groups we want to delete.

 @param cacheGroupIds An array of `NSNumbers` corresponding to the cache groups you want cleared.
 @param db The connection to the database.
 */
- (void)deleteCacheGroups:(NSArray *)cacheGroupsIds usingDBConnection:(sqlite3 *)db {
    sqlite3_stmt    *statement;
    NSString *queryString = [NSString stringWithFormat:@"DELETE FROM %@ WHERE id IN (%@)", cacheGroupTable,[self commaSeparatedValuesFromArray:cacheGroupsIds]];
    const char *query = [queryString UTF8String];
    if (sqlite3_prepare_v2(db, query, -1, &statement, NULL) == SQLITE_OK)
    {
        sqlite3_step(statement);
    }
    else {
        NSLog(@"SQL Error: %s",sqlite3_errmsg(db));
    }
    sqlite3_finalize(statement);
}

/**
 Delete the rows in the Caches table associated to the cache groups we want to delete.
 Deleting a row in the Caches table triggers a cascade delete in all the linked tables, most importantly
 it deletes the cached data associated to the cache group.

 @param cacheGroupIds An array of `NSNumbers` corresponding to the cache groups you want cleared.
 @param db The connection to the database
 */
- (void)deleteCacheResourcesInCacheGroups:(NSArray *)cacheGroupsIds usingDBConnection:(sqlite3 *)db {
    sqlite3_stmt    *statement;
    NSString *queryString = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ IN (%@)", cacheTable,cacheTableCacheGroupId, [self commaSeparatedValuesFromArray:cacheGroupsIds]];
    const char *query = [queryString UTF8String];
    if (sqlite3_prepare_v2(db, query, -1, &statement, NULL) == SQLITE_OK)
    {
        sqlite3_step(statement);
    }
    else {
        NSLog(@"SQL Error: %s",sqlite3_errmsg(db));
    }
    sqlite3_finalize(statement);
}

/**
 Helper to transform an `NSArray` in a comma separated string we can use in our queries.

 @return The comma separated string
 */
- (NSString *)commaSeparatedValuesFromArray:(NSArray *)valuesArray {
    NSMutableString *result = [NSMutableString stringWithCapacity:0];
    [valuesArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[NSNumber class]]) {
            [result appendFormat:@"%d", [(NSNumber *)obj intValue]];
        }
        else {
            [result appendFormat:@"'%@'", obj];
        }
        if (idx != valuesArray.count-1) {
            [result appendString:@", "];
        }
    }];
    return result;
}


// cordova!

- (NSArray*)partialToDbStoredManifestFullUrls:(NSArray*)partialManifestUrls {
    NSUInteger partialManifestUrls_count = partialManifestUrls.count;
    if (partialManifestUrls_count <= 0) {
        return [NSArray array];
    }
    NSMutableArray *manifestURLs = [[NSMutableArray alloc] init]; //remove manifestURL from param and declare here.

    sqlite3 *newDBconnection;

    /*Check that the db is created, if not we return as sqlite3_open would create

     an empty database and webkit will crash on us when accessing this empty database*/

    if (![[NSFileManager defaultManager] fileExistsAtPath:[self cacheDatabasePath]]) {

        NSLog(@"The cache manifest db has not been created by Webkit yet");

        return [NSArray array];
    }
    //Added here is the sql query to get all the manifestURLs and storing them in array to be used later in the code
    sqlite3_stmt *statement;
    if (sqlite3_open([[self cacheDatabasePath] UTF8String], &newDBconnection) == SQLITE_OK)
    {
        NSMutableString *querySQL = [NSMutableString stringWithString: @"SELECT manifestURL FROM CacheGroups where "];
        for (NSString* urlStr in partialManifestUrls) {
            [querySQL appendFormat:@"manifestURL like '%@' or ", urlStr];
        }
        const char *query_stmt = [[querySQL substringToIndex:[querySQL length]-4] UTF8String];
        int i = sqlite3_prepare_v2(newDBconnection, query_stmt, -1, &statement, NULL);
        if (i!=SQLITE_OK) {
            sqlite3_finalize(statement);
            sqlite3_close(newDBconnection);

            //NSLog(@"Query not execued",nil);
        }
        else
        {
            while(sqlite3_step(statement) == SQLITE_ROW)
            {
                [manifestURLs addObject:[NSString stringWithUTF8String:(char *)sqlite3_column_text(statement, 0)]];
            }

            //NSLog(@"%@",manifestURLs);
            return [NSArray arrayWithArray:manifestURLs];
        }
    }
    return [NSArray array];
}

- (NSString *)cacheDatabasePath {
    NSArray *pathsList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *pathSuffix = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundleIdentifier], cacheDatabaseName];
    NSString *path = [(NSString *)pathsList[0] stringByAppendingPathComponent:pathSuffix];

    return path;
}

@end

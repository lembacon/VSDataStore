/* vim: set ft=objc fenc=utf-8 sw=2 ts=2 et: */
/*
 * Copyright (c) 2013-2014 Chongyu Zhu <i@lembacon.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import "VSDataManager+DatabasePath.h"

static NSString *gDefaultDatabasePath = nil;
static NSString *gDefaultDatabaseName = @"VSDataStore.db";

@implementation VSDataManager (DatabasePath)

+ (NSString *)_bundleName
{
  static NSString *bundleName = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSBundle *bundle = [NSBundle mainBundle];
    if (bundle != nil) {
      NSDictionary *infoDictionary = [bundle infoDictionary];
      NSString *name = nil;
      if (infoDictionary != nil &&
          (name = [infoDictionary objectForKey:@"CFBundleName"]) != nil) {
        bundleName = [name copy];
      }
    }
  });

  return bundleName;
}

+ (NSString *)_realDefaultDatabasePath
{
  static NSString *path = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    if ([self _bundleName] != nil) {
      NSString *appSupportPath = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:[self _bundleName]];
      [[NSFileManager defaultManager] createDirectoryAtPath:appSupportPath withIntermediateDirectories:NO attributes:nil error:NULL];
      path = [[appSupportPath stringByAppendingPathComponent:[self defaultDatabaseName]] copy];
    }
    else {
      path = [[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:[self defaultDatabaseName]] copy];
    }
  });

  return path;
}

+ (NSString *)defaultDatabasePath
{
  if (gDefaultDatabasePath != nil) {
    return gDefaultDatabasePath;
  }

  return [self _realDefaultDatabasePath];
}

+ (void)setDefaultDatabasePath:(NSString *)path
{
  gDefaultDatabasePath = [path copy];
}

+ (NSString *)defaultDatabaseName
{
  return gDefaultDatabaseName;
}

+ (void)setDefaultDatabaseName:(NSString *)name
{
  gDefaultDatabaseName = [name copy];
}

@end

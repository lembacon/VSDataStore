/* vim: set ft=objc fenc=utf-8 sw=2 ts=2 et: */
/*
 * Copyright (c) 2013 Chongyu Zhu <lembacon@gmail.com>
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

#import "VSDataManager.h"
#import "VSDataManager+Private.h"
#import "VSDataManager+DatabasePath.h"
#import "VSDataModel.h"
#import "VSDataObject.h"
#include "vsdb.h"
#include "vsdb_cf.h"

@interface VSDataManager () {
@private
  vsdb_t _vsdb;
  NSDictionary *_dictionaries;
}
@end

@implementation VSDataManager (Private)
- (void)setValue:(id)value forProperty:(NSString *)property uniqueIdentifier:(NSString *)uniqueIdentifier modelIdentifier:(NSString *)modelIdentifier
{
  NSString *key = [NSString stringWithFormat:@"%@:%@:%@", modelIdentifier, uniqueIdentifier, property];
  vsdb_set_cfvalue(_vsdb, (__bridge CFStringRef)key, (__bridge CFTypeRef)value);
}
@end

@implementation VSDataManager

+ (VSDataManager *)defaultManager
{
  static VSDataManager *dataManager = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [VSDataModel sharedModel];
    dataManager = [[VSDataManager alloc] initWithDatabasePath:[self defaultDatabasePath]];
  });

  return dataManager;
}

- (NSMutableDictionary *)_loadAllDataObjectsForClass:(Class)class
{
  NSString *glob = [NSString stringWithFormat:@"%@:*", [class modelIdentifier]];
  NSDictionary *results = CFBridgingRelease(vsdb_copy_cfvalue(_vsdb, (__bridge CFStringRef)glob));
  if (results == nil) {
    return [NSMutableDictionary dictionary];
  }

  NSMutableDictionary *dictionaries = [NSMutableDictionary dictionary];
  for (NSString *key in results) {
    NSArray *keyComponents = [key componentsSeparatedByString:@":"];
    if ([keyComponents count] != 3) {
      continue;
    }

    NSString *uniqueIdentifier = [keyComponents objectAtIndex:1];
    NSMutableDictionary *extraDict = [dictionaries objectForKey:uniqueIdentifier];
    if (extraDict == nil) {
      extraDict = [NSMutableDictionary dictionary];
      [dictionaries setObject:extraDict forKey:uniqueIdentifier];
    }

    NSString *propertyName = [keyComponents objectAtIndex:2];
    [extraDict setObject:[results objectForKey:key] forKey:propertyName];
  }

  NSMutableDictionary *allDataObjects = [NSMutableDictionary dictionaryWithCapacity:[dictionaries count]];
  for (NSString *uniqueIdentifier in dictionaries) {
    VSDataObject *dataObject = [[VSDataModel sharedModel] dataObjectWithClass:class
                                                                   dictionary:[dictionaries objectForKey:uniqueIdentifier]
                                                                  dataManager:self];
    [allDataObjects setObject:dataObject forKey:uniqueIdentifier];
  }

  return allDataObjects;
}

- (id)initWithDatabasePath:(NSString *)path
{
  self = [super init];
  if (self) {
    _vsdb = vsdb_open([path UTF8String]);

    NSArray *modelClasses = [[VSDataModel sharedModel] modelClasses];
    NSMutableDictionary *dictionaries = [[NSMutableDictionary alloc] initWithCapacity:[modelClasses count]];
    for (id class in modelClasses) {
      [dictionaries setObject:[self _loadAllDataObjectsForClass:(Class)class] forKey:class];
    }
    _dictionaries = dictionaries;
  }

  return self;
}

- (void)dealloc
{
  vsdb_close(_vsdb);
  _vsdb = NULL;
}

- (void)sync
{
  vsdb_sync(_vsdb);
}

- (NSDictionary *)dictionaryOfDataObjectsForClass:(Class)dataObjectClass
{
  return [_dictionaries objectForKey:(id)dataObjectClass];
}

- (NSArray *)dataObjectsForClass:(Class)dataObjectClass
{
  return [[self dictionaryOfDataObjectsForClass:dataObjectClass] allValues];
}

- (void)addDataObject:(VSDataObject *)dataObject
{
  if ([[VSDataModel sharedModel] dataManager:self setAllValuesForDataObject:dataObject]) {
    NSMutableDictionary *dict = [_dictionaries objectForKey:(id)[dataObject class]];
    if (dict != nil) {
      [dict setObject:dataObject forKey:[dataObject uniqueIdentifier]];
    }
  }
}

- (void)removeDataObject:(VSDataObject *)dataObject
{
  if ([[VSDataModel sharedModel] dataManager:self eraseAllValuesForDataObject:dataObject]) {
    NSMutableDictionary *dict = [_dictionaries objectForKey:(id)[dataObject class]];
    if (dict != nil) {
      [dict removeObjectForKey:[dataObject uniqueIdentifier]];
    }
  }
}

@end

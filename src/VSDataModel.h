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

#import <Foundation/Foundation.h>

@class VSDataObject;
@class VSDataManager;

@interface VSDataModel : NSObject

+ (VSDataModel *)sharedModel;

- (NSArray *)modelClasses;

- (VSDataObject *)copyDataObject:(VSDataObject *)dataObject withZone:(NSZone *)zone;
- (void)decodeDataObject:(VSDataObject *)dataObject withCoder:(NSCoder *)aDecoder;
- (void)encodeDataObject:(VSDataObject *)dataObject withCoder:(NSCoder *)aCoder;
- (NSString *)descriptionForDataObject:(VSDataObject *)dataObject;

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector forDataObject:(VSDataObject *)object;
- (BOOL)forwardInvocation:(NSInvocation *)anInvocation forDataObject:(VSDataObject *)object;

- (void)dataObject:(VSDataObject *)dataObject willChangeValueForKey:(NSString *)key;
- (void)dataObject:(VSDataObject *)dataObject didChangeValueForKey:(NSString *)key;

- (BOOL)dataObject:(VSDataObject *)dataObject getValue:(__strong id *)value forKey:(NSString *)key;
- (BOOL)dataObject:(VSDataObject *)dataObject setValue:(id)value forKey:(NSString *)key;

- (BOOL)dataManager:(VSDataManager *)dataManager eraseAllValuesForDataObject:(VSDataObject *)dataObject;
- (BOOL)dataManager:(VSDataManager *)dataManager setAllValuesForDataObject:(VSDataObject *)dataObject;

- (NSString *)uniqueIdentifierForDataObject:(VSDataObject *)dataObject;
- (VSDataObject *)dataObjectWithClass:(Class)class dictionary:(NSDictionary *)dictionary dataManager:(VSDataManager *)dataManager;

@end

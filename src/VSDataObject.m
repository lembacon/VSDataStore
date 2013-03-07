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

#import "VSDataObject.h"
#import "VSDataModel.h"

@implementation VSDataObject

- (id)copyWithZone:(NSZone *)zone
{
  return [[VSDataModel sharedModel] copyDataObject:self withZone:zone];
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
  return [self copyWithZone:zone];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
  [[VSDataModel sharedModel] encodeDataObject:self withCoder:aCoder];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
  self = [self init];
  if (self) {
    [[VSDataModel sharedModel] decodeDataObject:self withCoder:aDecoder];
  }

  return self;
}

+ (NSString *)modelIdentifier
{
  return NSStringFromClass(self);
}

+ (NSString *)nameForUniqueIdentifier
{
  return nil;
}

- (NSString *)description
{
  return [[VSDataModel sharedModel] descriptionForDataObject:self];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
  NSMethodSignature *methodSignature = [[VSDataModel sharedModel] methodSignatureForSelector:aSelector forDataObject:self];
  if (methodSignature != nil) {
    return methodSignature;
  }

  return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
  if (![[VSDataModel sharedModel] forwardInvocation:anInvocation forDataObject:self]) {
    [super forwardInvocation:anInvocation];
  }
}

- (NSString *)uniqueIdentifier
{
  return [[VSDataModel sharedModel] uniqueIdentifierForDataObject:self];
}

- (BOOL)isEqual:(id)object
{
  if (![object isKindOfClass:[self class]]) {
    return [super isEqual:object];
  }

  return [[self uniqueIdentifier] isEqual:[object uniqueIdentifier]];
}

- (NSUInteger)hash
{
  return [[self uniqueIdentifier] hash];
}

- (void)willChangeValueForKey:(NSString *)key
{
  [super willChangeValueForKey:key];
  [[VSDataModel sharedModel] dataObject:self willChangeValueForKey:key];
}

- (void)didChangeValueForKey:(NSString *)key
{
  [[VSDataModel sharedModel] dataObject:self didChangeValueForKey:key];
  [super didChangeValueForKey:key];
}

- (void)willChange:(NSKeyValueChange)changeKind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
  [super willChange:changeKind valuesAtIndexes:indexes forKey:key];
  [[VSDataModel sharedModel] dataObject:self willChangeValueForKey:key];
}

- (void)didChange:(NSKeyValueChange)changeKind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key
{
  [[VSDataModel sharedModel] dataObject:self didChangeValueForKey:key];
  [super didChange:changeKind valuesAtIndexes:indexes forKey:key];
}

- (void)willChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutationKind usingObjects:(NSSet *)objects
{
  [super willChangeValueForKey:key withSetMutation:mutationKind usingObjects:objects];
  [[VSDataModel sharedModel] dataObject:self willChangeValueForKey:key];
}

- (void)didChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutationKind usingObjects:(NSSet *)objects
{
  [[VSDataModel sharedModel] dataObject:self didChangeValueForKey:key];
  [super didChangeValueForKey:key withSetMutation:mutationKind usingObjects:objects];
}

- (id)valueForKey:(NSString *)key
{
  id value = nil;
  if ([[VSDataModel sharedModel] dataObject:self getValue:&value forKey:key]) {
    return value;
  }

  return [super valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key
{
  if (![[VSDataModel sharedModel] dataObject:self setValue:value forKey:key]) {
    [super setValue:value forKey:key];
  }
}

@end

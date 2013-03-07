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

#import "VSDataModel.h"
#import "VSDataManager.h"
#import "VSDataManager+Private.h"
#import "VSDataObject.h"
#include <objc/runtime.h>

#ifdef DEBUG
#define VSDMLog(...) NSLog(@"[VSDataModel] %@", [NSString stringWithFormat:__VA_ARGS__])
#else /* DEBUG */
#define VSDMLog(...) ((void)0)
#endif /* DEBUG */

typedef NS_OPTIONS(NSUInteger, VSDataObjectPropertyFlags) {
  VSDynamicProperty = 1 << 0,
  VSSynthesizedProperty = 1 << 1,
  VSNonatomicProperty = 1 << 2,

  VSReadonlyProperty = 1 << 3,
  VSStrongProperty = 1 << 4,
  VSWeakProperty = 1 << 5,
  VSCopyProperty = 1 << 6,
  VSAssignProperty = 1 << 7,

  VSRetainProperty = VSStrongProperty,
  VSUnsafeUnretainedProperty = VSAssignProperty,

  VSPrimitiveTypedProperty = 1 << 15,
  VSStructTypedProperty = 1 << 16,
  VSObjectTypedProperty = 1 << 17,

  VSMutableVariantProperty = 1 << 31
};

static inline void analyzePropertyAttributes(const objc_property_attribute_t *attributes,
                                             unsigned int count,
                                             const char **setterName,
                                             const char **getterName,
                                             const char **typeSignature,
                                             VSDataObjectPropertyFlags *flags)
{
  unsigned int i;

  *setterName = NULL;
  *getterName = NULL;
  *typeSignature = NULL;
  *flags = 0;

  for (i = 0; i < count; i++) {
    switch (attributes[i].name[0]) {
    case 'D':
      *flags |= VSDynamicProperty;
      break;
    case 'N':
      *flags |= VSNonatomicProperty;
      break;
    case 'R':
      *flags |= VSReadonlyProperty;
      break;
    case '&':
      *flags |= VSStrongProperty;
      break;
    case 'W':
      *flags |= VSWeakProperty;
      break;
    case 'C':
      *flags |= VSCopyProperty;
      break;
    case 'S':
      *setterName = attributes[i].value;
      break;
    case 'G':
      *getterName = attributes[i].value;
      break;
    case 'T':
      *typeSignature = attributes[i].value;
      break;
    default:
      break;
    }
  }

  if (!(*flags & VSDynamicProperty)) {
    *flags |= VSSynthesizedProperty;
  }

  if (!(*flags & VSStrongProperty) && !(*flags & VSWeakProperty) && !(*flags & VSCopyProperty)) {
    *flags |= VSAssignProperty;
  }

  if (*typeSignature != NULL) {
    switch (**typeSignature) {
    case '@':
      *flags |= VSObjectTypedProperty;
      break;
    case '{':
      *flags |= VSStructTypedProperty;
      break;
    default:
      *flags |= VSPrimitiveTypedProperty;
      break;
    }
  }
}

static inline Class getClassFromPropertyTypeSignature(const char *typeSignature)
{
  size_t length;
  char *className;
  Class class;

  if (typeSignature == NULL || typeSignature[0] != '@') {
    return NULL;
  }

  length = strlen(typeSignature);
  if (length == 1) {
    return [NSObject class];
  }
  else if (length <= 3) {
    return NULL;
  }

  className = (char *)malloc(length - 3 + 1);
  className[length - 3] = '\0';
  strncpy(className, typeSignature + 2, length - 3);
  class = objc_getClass(className);
  free(className);

  return class;
}

@interface VSDataObjectPropertyInfo : NSObject
@property (nonatomic, assign) VSDataObjectPropertyFlags flags;
@property (nonatomic, assign) Class typeClass;
@property (nonatomic, strong) NSString *propertyName;
@property (nonatomic, strong) NSMethodSignature *getterSignature;
@property (nonatomic, strong) NSMethodSignature *setterSignature;
@property (nonatomic, strong) NSString *getterName;
@property (nonatomic, strong) NSString *setterName;
@property (nonatomic, assign) SEL getter;
@property (nonatomic, assign) SEL setter;
@end
@implementation VSDataObjectPropertyInfo
@end

static const void *kDataObjectExtraInfoAssocKey = &kDataObjectExtraInfoAssocKey;
static NSString *const kDataObjectExtraDictionaryCoderKey = @"ExtraDictionary";

@interface VSDataObjectExtraInfo : NSObject
@property (nonatomic, strong) NSMutableDictionary *extraDictionary;
@property (nonatomic, weak) VSDataManager *dataManager;
@end
@implementation VSDataObjectExtraInfo
@end

@interface VSDataObject (DataModel)
- (id)initWithExtraDictionary:(NSDictionary *)dictionary dataManager:(VSDataManager *)dataManager properties:(NSDictionary *)properties;
@property (nonatomic, strong, readonly) NSMutableDictionary *extraDictionary;
@property (nonatomic, weak) VSDataManager *dataManager;
@end
@implementation VSDataObject (DataModel)
- (VSDataObjectExtraInfo *)_extraInfo
{
  VSDataObjectExtraInfo *extraInfo = objc_getAssociatedObject(self, kDataObjectExtraInfoAssocKey);
  if (extraInfo == nil) {
    extraInfo = [[VSDataObjectExtraInfo alloc] init];
    objc_setAssociatedObject(self, kDataObjectExtraInfoAssocKey, extraInfo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }

  return extraInfo;
}

- (id)initWithExtraDictionary:(NSDictionary *)dictionary dataManager:(VSDataManager *)dataManager properties:(NSDictionary *)properties
{
  self = [self init];
  if (self) {
    NSMutableDictionary *mutableDict;
    if (properties == nil) {
      mutableDict = [dictionary mutableCopy];
    }
    else {
      mutableDict = [[NSMutableDictionary alloc] initWithCapacity:[dictionary count]];
      for (NSString *propertyName in dictionary) {
        id object = [dictionary objectForKey:propertyName];
        VSDataObjectPropertyInfo *propInfo = [properties objectForKey:propertyName];
        if (propInfo != nil) {
          if ([propInfo flags] & VSMutableVariantProperty) {
            object = [object mutableCopy];
          }
          else {
            object = [object copy];
          }
        }

        [mutableDict setObject:object forKey:propertyName];
      }
    }

    VSDataObjectExtraInfo *extraInfo = [self _extraInfo];
    [extraInfo setExtraDictionary:mutableDict];
    [extraInfo setDataManager:dataManager];
  }

  return self;
}

- (NSMutableDictionary *)extraDictionary
{
  VSDataObjectExtraInfo *extraInfo = [self _extraInfo];
  NSMutableDictionary *extraDict = [extraInfo extraDictionary];
  if (extraDict == nil) {
    extraDict = [[NSMutableDictionary alloc] init];
    [extraInfo setExtraDictionary:extraDict];
  }

  return extraDict;
}

- (void)setDataManager:(VSDataManager *)dataManager
{
  [[self _extraInfo] setDataManager:dataManager];
}

- (VSDataManager *)dataManager
{
  return [[self _extraInfo] dataManager];
}
@end

@interface VSDataObject (PropertyInvocation)
- (void)invokeProperty:(VSDataObjectPropertyInfo *)propertyInfo withInvocation:(NSInvocation *)invocation;
@end
@implementation VSDataObject (PropertyInvocation)
- (void)_getNonatomicProperty:(VSDataObjectPropertyInfo *)propertyInfo withInvocation:(NSInvocation *)invocation
{
  id object = [[self extraDictionary] objectForKey:[propertyInfo propertyName]];
  [invocation setReturnValue:&object];
}

- (void)_setNonatomicProperty:(VSDataObjectPropertyInfo *)propertyInfo withInvocation:(NSInvocation *)invocation
{
  __unsafe_unretained id object = nil;
  [invocation getArgument:&object atIndex:2];

  [self willChangeValueForKey:[propertyInfo propertyName]];
  if (object == nil) {
    [[self extraDictionary] removeObjectForKey:[propertyInfo propertyName]];
  }
  else {
    if ([propertyInfo flags] & VSCopyProperty) {
      if ([propertyInfo flags] & VSMutableVariantProperty) {
        [[self extraDictionary] setObject:[object mutableCopy] forKey:[propertyInfo propertyName]];
      }
      else {
        [[self extraDictionary] setObject:[object copy] forKey:[propertyInfo propertyName]];
      }
    }
    else {
      [[self extraDictionary] setObject:object forKey:[propertyInfo propertyName]];
    }
  }
  [self didChangeValueForKey:[propertyInfo propertyName]];
}

- (void)invokeProperty:(VSDataObjectPropertyInfo *)propertyInfo withInvocation:(NSInvocation *)invocation
{
  if ([invocation selector] == [propertyInfo getter]) {
    if ([propertyInfo flags] & VSNonatomicProperty) {
      [self _getNonatomicProperty:propertyInfo withInvocation:invocation];
    }
    else {
      @synchronized([self extraDictionary]) {
        [self _getNonatomicProperty:propertyInfo withInvocation:invocation];
      }
    }
  }
  else {
    if ([propertyInfo flags] & VSNonatomicProperty) {
      [self _setNonatomicProperty:propertyInfo withInvocation:invocation];
    }
    else {
      @synchronized([self extraDictionary]) {
        [self _setNonatomicProperty:propertyInfo withInvocation:invocation];
      }
    }
  }
}
@end

@interface VSDataObjectModelInfo : NSObject {
@private
  __weak VSDataObjectPropertyInfo *_uniqueIdentifierProperty;
  NSDictionary *_selectors;
  NSDictionary *_properties;
}
- (id)initWithModelClass:(Class)class;

- (NSDictionary *)properties;
- (NSString *)nameForUniqueIdentifier;

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector forDataObject:(VSDataObject *)object;
- (BOOL)forwardInvocation:(NSInvocation *)anInvocation forDataObject:(VSDataObject *)object;
@end
@implementation VSDataObjectModelInfo
+ (NSArray *)_propertiesForModelClass:(Class)class
{
  NSMutableArray *array;
  VSDataObjectPropertyInfo *info;
  NSMethodSignature *getterSignature, *setterSignature;
  objc_property_t *properties;
  objc_property_attribute_t *attributes;
  unsigned int propCount = 0, attrCount, i;
  const char *propertyName, *setterName, *getterName, *typeSignature;
  VSDataObjectPropertyFlags flags;
  Class typeClass;

  array = [NSMutableArray array];
  getterSignature = [NSMethodSignature signatureWithObjCTypes:"@@:"];
  setterSignature = [NSMethodSignature signatureWithObjCTypes:"v@:@"];
  properties = class_copyPropertyList(class, &propCount);

  for (i = 0; i < propCount; i++) {
    attrCount = 0;
    attributes = property_copyAttributeList(properties[i], &attrCount);
    propertyName = property_getName(properties[i]);
    analyzePropertyAttributes(attributes, attrCount, &setterName, &getterName, &typeSignature, &flags);

    if (flags & VSSynthesizedProperty) {
      goto nextAttribute;
    }
    else if (flags & VSReadonlyProperty) {
      VSDMLog(@"unsupported 'readonly' property '%s' found in '%@'", propertyName, NSStringFromClass(class));
      goto nextAttribute;
    }
    else if (flags & VSWeakProperty) {
      VSDMLog(@"unsupported 'weak' property '%s' found in '%@'", propertyName, NSStringFromClass(class));
      goto nextAttribute;
    }
    else if (flags & VSAssignProperty) {
      VSDMLog(@"unsupported 'assign/unsafe_unretained' property '%s' found in '%@'", propertyName, NSStringFromClass(class));
      goto nextAttribute;
    }
    else if (!(flags & VSObjectTypedProperty)) {
      VSDMLog(@"unsupported type of property '%s' found in '%@'", propertyName, NSStringFromClass(class));
      goto nextAttribute;
    }

    typeClass = getClassFromPropertyTypeSignature(typeSignature);
    if (typeClass == NULL || typeClass == [NSObject class]) {
      VSDMLog(@"unsupported type of property '%s' found in '%@'", propertyName, NSStringFromClass(class));
      goto nextAttribute;
    }

    if (flags & VSCopyProperty) {
      if (![typeClass conformsToProtocol:objc_getProtocol("NSCopying")]) {
        VSDMLog(@"cannot use 'copy' attribute on property '%s' found in '%@'", propertyName, NSStringFromClass(class));
        goto nextAttribute;
      }
    }

    if ([typeClass isSubclassOfClass:[NSString class]] ||
        [typeClass isSubclassOfClass:[NSData class]] ||
        [typeClass isSubclassOfClass:[NSNumber class]] ||
        [typeClass isSubclassOfClass:[NSNull class]] ||
        [typeClass isSubclassOfClass:[NSDate class]] ||
        [typeClass isSubclassOfClass:[NSSet class]] ||
        [typeClass isSubclassOfClass:[NSArray class]] ||
        [typeClass isSubclassOfClass:[NSDictionary class]]) {
      if ([typeClass isSubclassOfClass:[NSMutableString class]] ||
          [typeClass isSubclassOfClass:[NSMutableData class]] ||
          [typeClass isSubclassOfClass:[NSMutableSet class]] ||
          [typeClass isSubclassOfClass:[NSMutableArray class]] ||
          [typeClass isSubclassOfClass:[NSMutableDictionary class]]) {
        flags |= VSMutableVariantProperty;
      }
    }
    else {
      VSDMLog(@"unsupported type of property '%s' found in '%@'", propertyName, NSStringFromClass(class));
      goto nextAttribute;
    }

    info = [[VSDataObjectPropertyInfo alloc] init];
    [info setFlags:flags];
    [info setTypeClass:typeClass];
    [info setPropertyName:[NSString stringWithUTF8String:propertyName]];
    [info setGetterSignature:getterSignature];
    [info setSetterSignature:setterSignature];

    if (getterName == NULL) {
      [info setGetterName:[NSString stringWithUTF8String:propertyName]];
      [info setGetter:sel_registerName(propertyName)];
    }
    else {
      [info setGetterName:[NSString stringWithUTF8String:getterName]];
      [info setGetter:sel_registerName(getterName)];
    }

    if (setterName == NULL) {
      char *realSetterName = (char *)malloc(3 + strlen(propertyName) + 1 + 1);
      sprintf(realSetterName, "set%c%s:", (char)toupper(propertyName[0]), propertyName + 1);

      [info setSetterName:[NSString stringWithUTF8String:realSetterName]];
      [info setSetter:sel_registerName(realSetterName)];
      free(realSetterName);
    }
    else {
      [info setSetterName:[NSString stringWithUTF8String:setterName]];
      [info setSetter:sel_registerName(setterName)];
    }

    [array addObject:info];

nextAttribute:
    free(attributes);
  }

  free(properties);
  return array;
}

- (id)initWithModelClass:(Class)class
{
  self = [super init];
  if (self) {
    NSArray *properties = [[self class] _propertiesForModelClass:class];

    NSMutableDictionary *propDict = [NSMutableDictionary dictionaryWithCapacity:[properties count]];
    NSMutableDictionary *selDict = [NSMutableDictionary dictionaryWithCapacity:([properties count] * 2)];
    for (VSDataObjectPropertyInfo *info in properties) {
      [propDict setObject:info forKey:[info propertyName]];
      [selDict setObject:info forKey:[info getterName]];
      [selDict setObject:info forKey:[info setterName]];
    }
    _properties = propDict;
    _selectors = selDict;

    NSString *nameForUniqueIdentifier = [class nameForUniqueIdentifier];
    if (nameForUniqueIdentifier == nil) {
      if ([properties count] > 0) {
        _uniqueIdentifierProperty = [properties objectAtIndex:0];
      }
      else {
        VSDMLog(@"model class '%@' is empty", NSStringFromClass(class));
      }
    }
    else {
      _uniqueIdentifierProperty = [_properties objectForKey:nameForUniqueIdentifier];
      if (_uniqueIdentifierProperty == nil) {
        VSDMLog(@"cannot find property named '%@' in '%@'", nameForUniqueIdentifier, NSStringFromClass(class));
      }
    }

    if (_uniqueIdentifierProperty != nil && [_uniqueIdentifierProperty typeClass] != [NSString class]) {
      VSDMLog(@"unique identifier '%@' is not an NSString in '%@'", [_uniqueIdentifierProperty propertyName], NSStringFromClass(class));
    }
  }

  return self;
}

- (NSDictionary *)properties
{
  return _properties;
}

- (NSString *)nameForUniqueIdentifier
{
  return [_uniqueIdentifierProperty propertyName];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector forDataObject:(VSDataObject *)object
{
  NSString *selectorName = NSStringFromSelector(aSelector);
  if (selectorName == nil)
    return nil;

  VSDataObjectPropertyInfo *propInfo = [_selectors objectForKey:selectorName];
  if (propInfo == nil)
    return nil;

  if (aSelector == [propInfo getter]) {
    return [propInfo getterSignature];
  }
  else {
    return [propInfo setterSignature];
  }
}

- (BOOL)forwardInvocation:(NSInvocation *)anInvocation forDataObject:(VSDataObject *)object
{
  SEL aSelector = [anInvocation selector];
  NSString *selectorName = NSStringFromSelector(aSelector);
  if (selectorName == nil)
    return NO;

  VSDataObjectPropertyInfo *propInfo = [_selectors objectForKey:selectorName];
  if (propInfo == nil)
    return NO;

  [object invokeProperty:propInfo withInvocation:anInvocation];
  return YES;
}
@end

@interface VSDataModel () {
@private
  NSArray *_modelClasses;
  NSDictionary *_models;
}
@end

@implementation VSDataModel

+ (VSDataModel *)sharedModel
{
  static VSDataModel *dataModel = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dataModel = [[VSDataModel alloc] init];
  });

  return dataModel;
}

+ (NSArray *)_classesForAllModels
{
  NSMutableArray *array;
  Class dataObjectClass;
  Class *classes;
  unsigned int count = 0, i;

  array = [NSMutableArray array];
  dataObjectClass = [VSDataObject class];
  classes = objc_copyClassList(&count);

  for (i = 0; i < count; i++) {
    if (class_getSuperclass(classes[i]) == dataObjectClass) {
      [array addObject:(id)classes[i]];
    }
  }

  free(classes);
  return array;
}

- (id)init
{
  self = [super init];
  if (self) {
    _modelClasses = [[self class] _classesForAllModels];
    NSMutableDictionary *models = [[NSMutableDictionary alloc] initWithCapacity:[_modelClasses count]];
    for (id class in _modelClasses) {
      [models setObject:[[VSDataObjectModelInfo alloc] initWithModelClass:(Class)class] forKey:class];
    }
    _models = models;
  }

  return self;
}

- (NSArray *)modelClasses
{
  return _modelClasses;
}

- (NSDictionary *)_propertiesForDataObjectClass:(Class)class
{
  VSDataObjectModelInfo *modelInfo = [_models objectForKey:(id)class];
  if (modelInfo != nil) {
    return [modelInfo properties];
  }

  return nil;
}

- (VSDataObject *)copyDataObject:(VSDataObject *)dataObject withZone:(NSZone *)zone
{
  return [[[dataObject class] allocWithZone:zone] initWithExtraDictionary:[dataObject extraDictionary]
                                                              dataManager:nil
                                                               properties:[self _propertiesForDataObjectClass:[dataObject class]]];
}

- (void)decodeDataObject:(VSDataObject *)dataObject withCoder:(NSCoder *)aDecoder
{
  NSDictionary *extraDict = [aDecoder decodeObjectForKey:kDataObjectExtraDictionaryCoderKey];
  if (extraDict != nil) {
    [[dataObject extraDictionary] setDictionary:extraDict];
  }
}

- (void)encodeDataObject:(VSDataObject *)dataObject withCoder:(NSCoder *)aCoder
{
  [aCoder encodeObject:[dataObject extraDictionary] forKey:kDataObjectExtraDictionaryCoderKey];
}

- (NSString *)descriptionForDataObject:(VSDataObject *)dataObject
{
  return [[dataObject extraDictionary] description];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector forDataObject:(VSDataObject *)object
{
  if (aSelector == NULL || object == nil)
    return nil;

  VSDataObjectModelInfo *modelInfo = [_models objectForKey:(id)[object class]];
  if (modelInfo == nil)
    return nil;

  return [modelInfo methodSignatureForSelector:aSelector forDataObject:object];
}

- (BOOL)forwardInvocation:(NSInvocation *)anInvocation forDataObject:(VSDataObject *)object
{
  if (anInvocation == nil || object == nil)
    return NO;

  VSDataObjectModelInfo *modelInfo = [_models objectForKey:(id)[object class]];
  if (modelInfo == nil)
    return NO;

  return [modelInfo forwardInvocation:anInvocation forDataObject:object];
}

- (void)dataObject:(VSDataObject *)dataObject willChangeValueForKey:(NSString *)key
{
}

- (void)dataObject:(VSDataObject *)dataObject didChangeValueForKey:(NSString *)key
{
  if ([dataObject dataManager] != nil) {
    [[dataObject dataManager] setValue:[[dataObject extraDictionary] objectForKey:key]
                           forProperty:key
                      uniqueIdentifier:[self uniqueIdentifierForDataObject:dataObject]
                       modelIdentifier:[[dataObject class] modelIdentifier]];
  }
}

- (BOOL)dataManager:(VSDataManager *)dataManager eraseAllValuesForDataObject:(VSDataObject *)dataObject
{
  if ([dataObject dataManager] != dataManager) {
    return NO;
  }

  NSString *uniqueIdentifier = [self uniqueIdentifierForDataObject:dataObject];
  NSString *modelIdentifier = [[dataObject class] modelIdentifier];

  if (uniqueIdentifier == nil) {
    VSDMLog(@"unique identifier is not set in '%@'", NSStringFromClass([dataObject class]));
    return NO;
  }

  for (NSString *propertyName in [dataObject extraDictionary]) {
    [dataManager setValue:nil forProperty:propertyName uniqueIdentifier:uniqueIdentifier modelIdentifier:modelIdentifier];
  }

  [dataObject setDataManager:nil];
  return YES;
}

- (BOOL)dataManager:(VSDataManager *)dataManager setAllValuesForDataObject:(VSDataObject *)dataObject
{
  if ([dataObject dataManager] != nil) {
    return NO;
  }

  NSString *uniqueIdentifier = [self uniqueIdentifierForDataObject:dataObject];
  NSString *modelIdentifier = [[dataObject class] modelIdentifier];

  if (uniqueIdentifier == nil) {
    VSDMLog(@"unique identifier is not set in '%@'", NSStringFromClass([dataObject class]));
    return NO;
  }

  if ([[dataManager dictionaryOfDataObjectsForClass:[dataObject class]] objectForKey:uniqueIdentifier] != nil) {
    VSDMLog(@"duplicated unique identifier '%@' in '%@'", uniqueIdentifier, NSStringFromClass([dataObject class]));
    return NO;
  }

  for (NSString *propertyName in [dataObject extraDictionary]) {
    [dataManager setValue:[[dataObject extraDictionary] objectForKey:propertyName]
              forProperty:propertyName
         uniqueIdentifier:uniqueIdentifier
          modelIdentifier:modelIdentifier];
  }

  [dataObject setDataManager:dataManager];
  return YES;
}

- (NSString *)uniqueIdentifierForDataObject:(VSDataObject *)dataObject
{
  VSDataObjectModelInfo *modelInfo = [_models objectForKey:(id)[dataObject class]];
  if (modelInfo == nil)
    return nil;

  return [[dataObject extraDictionary] objectForKey:[modelInfo nameForUniqueIdentifier]];
}

- (VSDataObject *)dataObjectWithClass:(Class)class dictionary:(NSDictionary *)dictionary dataManager:(VSDataManager *)dataManager
{
  return [[class alloc] initWithExtraDictionary:dictionary
                                    dataManager:dataManager
                                     properties:[self _propertiesForDataObjectClass:class]];
}

@end

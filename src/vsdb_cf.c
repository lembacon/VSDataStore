/* vim: set ft=c fenc=utf-8 sw=2 ts=2 et: */
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

#include "vsdb_cf.h"

static void get_utf8_bytes(CFStringRef string, char **utf8, size_t *utf8_length)
{
  CFIndex string_length;
  CFIndex utf8_max_length;
  CFIndex used_buf_length;

  string_length = CFStringGetLength(string);
  utf8_max_length = CFStringGetMaximumSizeForEncoding(string_length, kCFStringEncodingUTF8);

  *utf8 = (char *)malloc(sizeof(char) * (utf8_max_length + 1));
  CFStringGetBytes(string, CFRangeMake(0, string_length), kCFStringEncodingUTF8, 0, FALSE, (UInt8 *)*utf8, utf8_max_length, &used_buf_length);

  if (used_buf_length < utf8_max_length) {
    *utf8 = (char *)realloc(*utf8, (used_buf_length + 1) * sizeof(char));
  }

  (*utf8)[used_buf_length] = '\0';
  *utf8_length = used_buf_length;
}

static inline CF_RETURNS_RETAINED CFStringRef create_cfstring(const char *utf8, size_t utf8_length);
static inline CFStringRef create_cfstring(const char *utf8, size_t utf8_length)
{
  return CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)utf8, utf8_length, kCFStringEncodingUTF8, FALSE);
}

static inline CF_RETURNS_RETAINED CFStringRef create_cfstring_nocopy(const char *utf8, size_t utf8_length);
static inline CFStringRef create_cfstring_nocopy(const char *utf8, size_t utf8_length)
{
  return CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, (const UInt8 *)utf8, utf8_length, kCFStringEncodingUTF8, FALSE, kCFAllocatorMalloc);
}

typedef struct {
  uint8_t *bytes;
  size_t size;
  size_t capacity;
  size_t cursor;
  int owns;
} stream_buffer_t;

static void stream_buffer_open(stream_buffer_t *sb)
{
  sb->capacity = 512;
  sb->bytes = (uint8_t *)malloc(sb->capacity);
  sb->size = 0;
  sb->cursor = 0;
  sb->owns = 1;
}

static void stream_buffer_open2(stream_buffer_t *sb, const void *buf, size_t bufsize)
{
  sb->bytes = (uint8_t *)buf;
  sb->size = bufsize;
  sb->capacity = bufsize;
  sb->cursor = bufsize;
  sb->owns = 0;
}

static void stream_buffer_close(stream_buffer_t *sb)
{
  if (sb->owns) {
    free(sb->bytes);
  }
}

static inline void stream_buffer_reset_cusor(stream_buffer_t *sb)
{
  sb->cursor = 0;
}

static inline void stream_buffer_move_cursor(stream_buffer_t *sb, size_t offset)
{
  sb->cursor += offset;
}

static inline void stream_buffer_copy(stream_buffer_t *sb, uint8_t **outbuf, size_t *outbuf_size)
{
  if (sb->owns) {
    sb->owns = 0;

    if (sb->size < sb->capacity) {
      sb->bytes = (uint8_t *)realloc(sb->bytes, sb->size);
      sb->capacity = sb->size;
    }

    *outbuf = sb->bytes;
    *outbuf_size = sb->size;
  }
  else {
    *outbuf = (uint8_t *)malloc(sb->size);
    memcpy(*outbuf, sb->bytes, sb->size);
    *outbuf_size = sb->size;
  }
}

static inline void stream_buffer_read(stream_buffer_t *sb, void *data, size_t size)
{
  if (sb->cursor + size > sb->size) {
    bzero(data, size);
    return;
  }

  memmove(data, sb->bytes + sb->cursor, size);
  sb->cursor += size;
}

static inline CF_RETURNS_RETAINED CFDataRef stream_buffer_read_cfdata(stream_buffer_t *sb, size_t size);
static inline CFDataRef stream_buffer_read_cfdata(stream_buffer_t *sb, size_t size)
{
  CFDataRef cfdata;

  if (sb->cursor + size > sb->size) {
    return NULL;
  }

  cfdata = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)(sb->bytes + sb->cursor), size);
  sb->cursor += size;

  return cfdata;
}

static inline void stream_buffer_write(stream_buffer_t *sb, const void *data, size_t size)
{
  if (sb->size + size > sb->capacity) {
    while (sb->size + size > sb->capacity) {
      sb->capacity <<= 1;
    }

    if (!sb->owns) {
      const uint8_t *tmp = sb->bytes;
      sb->bytes = (uint8_t *)malloc(sb->capacity);
      memcpy(sb->bytes, tmp, sb->size);
      sb->owns = 1;
    }
    else {
      sb->bytes = (uint8_t *)realloc(sb->bytes, sb->capacity);
    }
  }

  memmove(sb->bytes + sb->cursor, data, size);
  sb->size += size;
  sb->cursor += size;
}

enum {
  trait_string,
  trait_data,
  trait_number_long_long,
  trait_number_double,
  trait_boolean_true,
  trait_boolean_false,
  trait_date,
  trait_dictionary,
  trait_array,
  trait_set,
  trait_null
};
typedef uint32_t trait_t;

static inline CF_RETURNS_RETAINED CFStringRef decode_simple_cfstring(stream_buffer_t *sb);
static inline CFStringRef decode_simple_cfstring(stream_buffer_t *sb)
{
  char *utf8;
  size_t utf8_length;

  stream_buffer_read(sb, &utf8_length, sizeof(utf8_length));
  utf8 = (char *)malloc(utf8_length);
  stream_buffer_read(sb, utf8, utf8_length);

  return create_cfstring_nocopy(utf8, utf8_length);
}

static CF_RETURNS_RETAINED CFTypeRef decode_cfvalue_sb(stream_buffer_t *sb);
static CFTypeRef decode_cfvalue_sb(stream_buffer_t *sb)
{
  trait_t trait;
  long number_long_long;
  double number_double;
  CFAbsoluteTime absolute_time;
  CFTypeRef *keys, *values;
  CFIndex count, i;
  CFTypeRef cfvalue;

  stream_buffer_read(sb, &trait, sizeof(trait));

  if (trait == trait_string) {
    return decode_simple_cfstring(sb);
  }
  else if (trait == trait_data) {
    stream_buffer_read(sb, &count, sizeof(count));
    cfvalue = stream_buffer_read_cfdata(sb, count);
    if (cfvalue == NULL) {
      return CFRetain(kCFNull);
    }
    return cfvalue;
  }
  else if (trait == trait_number_long_long || trait == trait_number_double) {
    if (trait == trait_number_long_long) {
      stream_buffer_read(sb, &number_long_long, sizeof(number_long_long));
      return CFNumberCreate(kCFAllocatorDefault, kCFNumberLongLongType, &number_long_long);
    }
    else {
      stream_buffer_read(sb, &number_double, sizeof(number_double));
      return CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &number_double);
    }
  }
  else if (trait == trait_boolean_true || trait == trait_boolean_false) {
    return CFRetain((trait == trait_boolean_true) ? kCFBooleanTrue : kCFBooleanFalse);
  }
  else if (trait == trait_date) {
    stream_buffer_read(sb, &absolute_time, sizeof(absolute_time));
    return CFDateCreate(kCFAllocatorDefault, absolute_time);
  }
  else if (trait == trait_dictionary) {
    stream_buffer_read(sb, &count, sizeof(count));
    keys = (CFTypeRef *)malloc(sizeof(CFTypeRef) * count);
    values = (CFTypeRef *)malloc(sizeof(CFTypeRef) * count);

    for (i = 0; i < count; i++) {
      stream_buffer_move_cursor(sb, sizeof(trait));
      keys[i] = decode_simple_cfstring(sb);
      values[i] = decode_cfvalue_sb(sb);
    }

    cfvalue = CFDictionaryCreate(kCFAllocatorDefault, keys, values, count, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    free(keys);
    free(values);

    return cfvalue;
  }
  else if (trait == trait_array || trait == trait_set) {
    stream_buffer_read(sb, &count, sizeof(count));
    values = (CFTypeRef *)malloc(sizeof(CFTypeRef) * count);

    for (i = 0; i < count; i++) {
      values[i] = decode_cfvalue_sb(sb);
    }

    if (trait == trait_array) {
      cfvalue = CFArrayCreate(kCFAllocatorDefault, values, count, &kCFTypeArrayCallBacks);
    }
    else {
      cfvalue = CFSetCreate(kCFAllocatorDefault, values, count, &kCFTypeSetCallBacks);
    }

    free(values);
    return cfvalue;
  }
  else {
    return CFRetain(kCFNull);
  }
}

static CF_RETURNS_RETAINED CFTypeRef decode_cfvalue(const void *value, size_t value_size);
static CFTypeRef decode_cfvalue(const void *value, size_t value_size)
{
  stream_buffer_t sb;
  CFTypeRef cfvalue;

  stream_buffer_open2(&sb, value, value_size);
  stream_buffer_reset_cusor(&sb);
  cfvalue = decode_cfvalue_sb(&sb);
  stream_buffer_close(&sb);

  return cfvalue;
}

static inline void encode_simple_cfstring(CFStringRef string, stream_buffer_t *sb)
{
  char *utf8;
  size_t utf8_length;
  trait_t trait;

  trait = trait_string;
  get_utf8_bytes(string, &utf8, &utf8_length);
  
  stream_buffer_write(sb, &trait, sizeof(trait));
  stream_buffer_write(sb, &utf8_length, sizeof(utf8_length));
  stream_buffer_write(sb, utf8, utf8_length);
  free(utf8);
}

static void encode_cfvalue_sb(CFTypeRef cfvalue, stream_buffer_t *sb)
{
  CFTypeID typeid;
  trait_t trait;
  double number_double;
  long long number_long_long;
  CFAbsoluteTime absolute_time;
  CFTypeRef *keys, *values;
  CFIndex count, i;

  typeid = CFGetTypeID(cfvalue);

  if (typeid == CFStringGetTypeID()) {
    encode_simple_cfstring((CFStringRef)cfvalue, sb);
  }
  else if (typeid == CFDataGetTypeID()) {
    trait = trait_data;
    count = CFDataGetLength((CFDataRef)cfvalue);
    stream_buffer_write(sb, &trait, sizeof(trait));
    stream_buffer_write(sb, &count, sizeof(count));
    stream_buffer_write(sb, CFDataGetBytePtr((CFDataRef)cfvalue), count);
  }
  else if (typeid == CFNumberGetTypeID()) {
    if (CFNumberIsFloatType((CFNumberRef)cfvalue)) {
      trait = trait_number_double;
      CFNumberGetValue((CFNumberRef)cfvalue, kCFNumberDoubleType, &number_double);

      stream_buffer_write(sb, &trait, sizeof(trait));
      stream_buffer_write(sb, &number_double, sizeof(number_double));
    }
    else {
      trait = trait_number_long_long;
      CFNumberGetValue((CFNumberRef)cfvalue, kCFNumberLongLongType, &number_long_long);

      stream_buffer_write(sb, &trait, sizeof(trait));
      stream_buffer_write(sb, &number_long_long, sizeof(number_long_long));
    }
  }
  else if (typeid == CFBooleanGetTypeID()) {
    if (CFBooleanGetValue((CFBooleanRef)cfvalue))
      trait = trait_boolean_true;
    else
      trait = trait_boolean_false;

    stream_buffer_write(sb, &trait, sizeof(trait));
  }
  else if (typeid == CFDateGetTypeID()) {
    trait = trait_date;
    absolute_time = CFDateGetAbsoluteTime((CFDateRef)cfvalue);
    stream_buffer_write(sb, &trait, sizeof(trait));
    stream_buffer_write(sb, &absolute_time, sizeof(absolute_time));
  }
  else if (typeid == CFDictionaryGetTypeID()) {
    trait = trait_dictionary;
    count = CFDictionaryGetCount((CFDictionaryRef)cfvalue);
    keys = (CFTypeRef *)malloc(sizeof(CFTypeRef) * count);
    values = (CFTypeRef *)malloc(sizeof(CFTypeRef) * count);
    CFDictionaryGetKeysAndValues((CFDictionaryRef)cfvalue, keys, values);

    stream_buffer_write(sb, &trait, sizeof(trait));
    stream_buffer_write(sb, &count, sizeof(count));

    for (i = 0; i < count; i++) {
      encode_simple_cfstring((CFStringRef)keys[i], sb);
      encode_cfvalue_sb(values[i], sb);
    }

    free(keys);
    free(values);
  }
  else if (typeid == CFArrayGetTypeID()) {
    trait = trait_array;
    count = CFArrayGetCount((CFArrayRef)cfvalue);

    stream_buffer_write(sb, &trait, sizeof(trait));
    stream_buffer_write(sb, &count, sizeof(count));

    for (i = 0; i < count; i++) {
      encode_cfvalue_sb(CFArrayGetValueAtIndex((CFArrayRef)cfvalue, i), sb);
    }
  }
  else if (typeid == CFSetGetTypeID()) {
    trait = trait_set;
    count = CFSetGetCount((CFSetRef)cfvalue);
    values = (CFTypeRef *)malloc(sizeof(CFTypeRef) * count);
    CFSetGetValues((CFSetRef)cfvalue, values);

    stream_buffer_write(sb, &trait, sizeof(trait));
    stream_buffer_write(sb, &count, sizeof(count));

    for (i = 0; i < count; i++) {
      encode_cfvalue_sb(values[i], sb);
    }

    free(values);
  }
  else {
    trait = trait_null;
    stream_buffer_write(sb, &trait, sizeof(trait));
  }
}

static void encode_cfvalue(CFTypeRef cfvalue, uint8_t **value, size_t *value_size)
{
  stream_buffer_t sb;

  stream_buffer_open(&sb);
  encode_cfvalue_sb(cfvalue, &sb);
  stream_buffer_copy(&sb, value, value_size);
  stream_buffer_close(&sb);
}

static CF_RETURNS_RETAINED CFTypeRef copy_simple_cfvalue(vsdb_t vsdb, CFStringRef key);
static CFTypeRef copy_simple_cfvalue(vsdb_t vsdb, CFStringRef key)
{
  char *utf8_key;
  size_t utf8_key_length;
  const void *value;
  size_t value_size;
  vsdb_ret_t ret;
  CFTypeRef cfvalue;

  get_utf8_bytes(key, &utf8_key, &utf8_key_length);
  ret = vsdb_get(vsdb, utf8_key, utf8_key_length, &value, &value_size);
  free(utf8_key);

  if (ret == vsdb_failed) {
    return NULL;
  }

  cfvalue = decode_cfvalue(value, value_size);
  vsdb_free((void *)value);
  return cfvalue;
}

static CF_RETURNS_RETAINED CFTypeRef copy_glob_cfvalue(vsdb_t vsdb, CFStringRef glob);
static CFTypeRef copy_glob_cfvalue(vsdb_t vsdb, CFStringRef glob)
{
  char *utf8_glob;
  size_t utf8_glob_length;
  const char **keys;
  const void **values;
  size_t *key_lengths, *value_sizes;
  size_t count;
  vsdb_ret_t ret;
  size_t i;
  CFMutableDictionaryRef mutable_dictionary;
  CFDictionaryRef dictionary;
  CFStringRef cfkey;
  CFTypeRef cfvalue;

  get_utf8_bytes(glob, &utf8_glob, &utf8_glob_length);
  ret = vsdb_glob(vsdb, utf8_glob, utf8_glob_length, &keys, &key_lengths, &values, &value_sizes, &count);
  free(utf8_glob);

  if (ret == vsdb_failed) {
    return NULL;
  }

  mutable_dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, count, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  for (i = 0; i < count; i++) {
    cfkey = create_cfstring(keys[i], key_lengths[i]);
    cfvalue = decode_cfvalue(values[i], value_sizes[i]);

    CFDictionaryAddValue(mutable_dictionary, cfkey, cfvalue);
    CFRelease(cfkey); 
    CFRelease(cfvalue);
  }

  vsdb_free2((void **)keys, count);
  vsdb_free2((void **)values, count);
  vsdb_free(key_lengths);
  vsdb_free(value_sizes);

  dictionary = CFDictionaryCreateCopy(kCFAllocatorDefault, mutable_dictionary);
  CFRelease(mutable_dictionary);

  return dictionary;
}

CFTypeRef vsdb_copy_cfvalue(vsdb_t vsdb, CFStringRef key)
{
  if (vsdb == NULL || key == NULL) {
    return NULL;
  }

  if (CFStringFind(key, CFSTR("*"), kCFCompareBackwards).location != kCFNotFound) {
    return copy_glob_cfvalue(vsdb, key);
  }
  else {
    return copy_simple_cfvalue(vsdb, key);
  }
}

#ifndef __clang_analyzer__
void vsdb_set_cfvalue(vsdb_t vsdb, CFStringRef key, CFTypeRef value)
{
  char *utf8_key;
  size_t utf8_key_length;
  uint8_t *raw_value;
  size_t raw_value_size;
  
  if (vsdb == NULL || key == NULL) {
    return;
  }

  get_utf8_bytes(key, &utf8_key, &utf8_key_length);

  if (value == NULL) {
    raw_value = NULL;
    raw_value_size = 0;
  }
  else {
    encode_cfvalue(value, &raw_value, &raw_value_size);
  }

  vsdb_set(vsdb, utf8_key, utf8_key_length, raw_value, raw_value_size);

  free(utf8_key);
  if (raw_value != NULL)
    free(raw_value);
}
#endif /* __clang_analyzer__ */

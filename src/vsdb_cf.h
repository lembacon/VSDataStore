/* vim: set ft=c fenc=utf-8 sw=2 ts=2 et: */
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

#ifndef __vsdatastore_vsdb_cf_h__
#define __vsdatastore_vsdb_cf_h__

#include <CoreFoundation/CoreFoundation.h>
#include "vsdb.h"

/*
 * Supported Core Foundation primitive value types:
 * - CFString
 * - CFData
 * - CFNumber
 * - CFBoolean
 * - CFDate
 * - CFDictionary (key must be CFString, value must be any of
 *                 supported primitive types)
 * - CFArray (value must be any of supported primitive types)
 * - CFSet (value must be any of supported primitive types)
 * - CFNull
 *
 * Unrecognized values will be considered as CFNull.
 *
 * If key contains '*', then that key will be regarded
 * as a glob, the returned value type will be CFDictionary.
 */

VSDB_EXTERN CF_RETURNS_RETAINED CFTypeRef vsdb_copy_cfvalue(vsdb_t vsdb, CFStringRef key);
VSDB_EXTERN void vsdb_set_cfvalue(vsdb_t vsdb, CFStringRef key, CFTypeRef value);

#endif /* __vsdatastore_vsdb_cf_h__ */

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

#ifndef __vsdatastore_vsdb_h__
#define __vsdatastore_vsdb_h__

#include <sys/types.h>

#ifdef __cplusplus
#define VSDB_EXTERN extern "C"
#else /* __cplusplus */
#define VSDB_EXTERN extern
#endif /* __cplusplus */

typedef struct _vsdb *vsdb_t;

typedef enum {
  vsdb_okay = 0,
  vsdb_failed = -1
} vsdb_ret_t;

VSDB_EXTERN vsdb_t vsdb_open(const char *filename);
VSDB_EXTERN void vsdb_close(vsdb_t vsdb);

VSDB_EXTERN vsdb_ret_t vsdb_sync(vsdb_t vsdb);

VSDB_EXTERN void vsdb_free(void *ptr);
VSDB_EXTERN void vsdb_free2(void **ptrs, size_t count);

VSDB_EXTERN vsdb_ret_t vsdb_get(vsdb_t vsdb, const char *key, size_t key_length,
                                             const void **value, size_t *value_size);
VSDB_EXTERN vsdb_ret_t vsdb_set(vsdb_t vsdb, const char *key, size_t key_length,
                                             const void *value, size_t value_size);

VSDB_EXTERN vsdb_ret_t vsdb_glob(vsdb_t vsdb, const char *glob, size_t glob_length,
                                              const char ***keys, size_t **key_lengths,
                                              const void ***values, size_t **value_sizes,
                                              size_t *count);

#endif /* __vsdatastore_vsdb_h__ */

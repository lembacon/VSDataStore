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

#include "vsdb.h"
#include <db.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <memory.h>
#include <string.h>
#include <libkern/OSAtomic.h>

struct _vsdb {
  DB *db;
  OSSpinLock spinlock;
};

static inline vsdb_t newvsdb(DB *db)
{
  vsdb_t vsdb;
  vsdb = (vsdb_t)malloc(sizeof(struct _vsdb));
  vsdb->db = db;
  vsdb->spinlock = OS_SPINLOCK_INIT;
  return vsdb;
}

static inline void freevsdb(vsdb_t vsdb)
{
  if (vsdb != NULL) {
    free(vsdb);
  }
}

static inline void lockdb(vsdb_t vsdb)
{
  OSSpinLockLock(&vsdb->spinlock);
}

static inline void unlockdb(vsdb_t vsdb)
{
  OSSpinLockUnlock(&vsdb->spinlock);
}

static inline DB *getdb(vsdb_t vsdb)
{
  if (vsdb == NULL)
    return NULL;
  return vsdb->db;
}

vsdb_t vsdb_open(const char *filename)
{
  DB *db;

  if (filename == NULL)
    return NULL;
  if ((db = dbopen(filename, O_RDWR | O_CREAT, 0644, DB_BTREE, NULL)) == NULL)
    return NULL;

  return newvsdb(db);
}

void vsdb_close(vsdb_t vsdb)
{
  DB *db;
  if ((db = getdb(vsdb)) != NULL) {
    db->close(db);
  }

  freevsdb(vsdb);
}

vsdb_ret_t vsdb_sync(vsdb_t vsdb)
{
  DB *db;
  int ret;

  if ((db = getdb(vsdb)) != NULL) {
    lockdb(vsdb);
    ret = db->sync(db, 0);
    unlockdb(vsdb);

    if (ret == 0) {
      return vsdb_okay;
    }
  }

  return vsdb_failed;
}

void vsdb_free(void *ptr)
{
  if (ptr != NULL) {
    free(ptr);
  }
}

void vsdb_free2(void **ptrs, size_t count)
{
  size_t i;

  if (ptrs == NULL)
    return;

  for (i = 0; i < count; i++) {
    if (ptrs[i] != NULL)
      free(ptrs[i]);
  }

  free(ptrs);
}

static inline void dup_dbt(DBT *dst, const DBT *src)
{
  dst->size = src->size;
  dst->data = malloc(dst->size);
  memcpy(dst->data, src->data, dst->size);
}

vsdb_ret_t vsdb_get(vsdb_t vsdb, const char *key, size_t key_length,
                                 const void **value, size_t *value_size)
{
  DB *db;
  DBT kt, dt;
  DBT newdt;
  int ret;

  if ((db = getdb(vsdb)) == NULL)
    goto failed;
  if (key == NULL || value == NULL || value_size == NULL)
    goto failed;
  if (key_length == SIZE_T_MAX)
    key_length = strlen(key);
  if (key_length == 0)
    goto failed;

  kt.data = (void *)key;
  kt.size = key_length;

  lockdb(vsdb);
  ret = db->get(db, &kt, &dt, 0);
  unlockdb(vsdb);

  if (ret == 0) {
    dup_dbt(&newdt, &dt);
    *value = newdt.data;
    *value_size = newdt.size;
    return vsdb_okay;
  }

failed:
  if (value != NULL)
    *value = NULL;
  if (value_size != NULL)
    *value_size = 0;
  return vsdb_failed;
}

vsdb_ret_t vsdb_set(vsdb_t vsdb, const char *key, size_t key_length,
                                 const void *value, size_t value_size)
{
  DB *db;
  DBT kt, dt;
  int ret;

  if ((db = getdb(vsdb)) == NULL)
    goto failed;
  if (key == NULL)
    goto failed;
  if (key_length == SIZE_T_MAX)
    key_length = strlen(key);
  if (key_length == 0)
    goto failed;

  kt.data = (void *)key;
  kt.size = key_length;

  if (value != NULL) {
    dt.data = (void *)value;
    dt.size = value_size;

    lockdb(vsdb);
    ret = db->put(db, &kt, &dt, 0);
    unlockdb(vsdb);

    if (ret != 0) {
      goto failed;
    }
  }
  else {
    lockdb(vsdb);
    ret = db->del(db, &kt, 0);
    unlockdb(vsdb);

    if (ret != 0) {
      goto failed;
    }
  }

  return vsdb_okay;

failed:
  return vsdb_failed;
}

#ifndef __clang_analyzer__
vsdb_ret_t vsdb_glob(vsdb_t vsdb, const char *glob, size_t glob_length,
                                  const char ***keys, size_t **key_lengths,
                                  const void ***values, size_t **value_sizes,
                                  size_t *count)
{
  DB *db;
  DBT kt, dt;
  vsdb_ret_t vsdb_ret;
  int ret;
  size_t i;
  struct {
    DBT *kts, *dts;
    size_t count;
    size_t capacity;
  } buf;

  vsdb_ret = vsdb_okay;
  bzero(&buf, sizeof(buf));
  lockdb(vsdb);

  if ((db = getdb(vsdb)) == NULL)
    goto failed;
  if (glob == NULL)
    goto failed;
  if (glob_length == SIZE_T_MAX)
    glob_length = strlen(glob);
  if (glob_length == 0)
    goto failed;
  if (keys == NULL || key_lengths == NULL || values == NULL || value_sizes == NULL)
    goto failed;
  if (count == NULL)
    goto failed;

  if (glob_length == 1 && glob[0] == '*') {
    if ((ret = db->seq(db, &kt, &dt, R_FIRST)) < 0) {
      goto failed;
    }
    else if (ret == 0) {
      do {
        if (buf.count == buf.capacity) {
          if (buf.capacity == 0) {
            buf.capacity = 16;
            buf.kts = (DBT *)malloc(sizeof(DBT) * buf.capacity);
            buf.dts = (DBT *)malloc(sizeof(DBT) * buf.capacity);
          }
          else {
            buf.capacity <<= 1;
            buf.kts = (DBT *)realloc(buf.kts, sizeof(DBT) * buf.capacity);
            buf.dts = (DBT *)realloc(buf.dts, sizeof(DBT) * buf.capacity);
          }
        }

        dup_dbt(&buf.kts[buf.count], &kt);
        dup_dbt(&buf.dts[buf.count], &dt);
        buf.count++;
      } while ((ret = db->seq(db, &kt, &dt, R_NEXT)) == 0);

      if (ret < 0) {
        goto failed;
      }
    }
  }
  else if (glob_length > 0 && glob[glob_length - 1] == '*') {
    kt.data = (void *)glob;
    kt.size = glob_length - 1;

    if ((ret = db->seq(db, &kt, &dt, R_CURSOR)) < 0) {
      goto failed;
    }
    else if (ret == 0) {
      do {
        if (buf.count == buf.capacity) {
          if (buf.capacity == 0) {
            buf.capacity = 16;
            buf.kts = (DBT *)malloc(sizeof(DBT) * buf.capacity);
            buf.dts = (DBT *)malloc(sizeof(DBT) * buf.capacity);
          }
          else {
            buf.capacity <<= 1;
            buf.kts = (DBT *)realloc(buf.kts, sizeof(DBT) * buf.capacity);
            buf.dts = (DBT *)realloc(buf.dts, sizeof(DBT) * buf.capacity);
          }
        }

        if (strncmp((const char *)kt.data, glob, ((glob_length - 1) < kt.size) ? (glob_length - 1) : kt.size) != 0) {
          break;
        }

        dup_dbt(&buf.kts[buf.count], &kt);
        dup_dbt(&buf.dts[buf.count], &dt);
        buf.count++;
      } while ((ret = db->seq(db, &kt, &dt, R_NEXT)) == 0);

      if (ret < 0) {
        goto failed;
      }
    }
  }
  else {
    goto failed;
  }

  if (buf.count > 0) {
    *keys = (const char **)malloc(sizeof(const char *) * buf.count);
    *key_lengths = (size_t *)malloc(sizeof(size_t) * buf.count);
    *values = (const void **)malloc(sizeof(const void *) * buf.count);
    *value_sizes = (size_t *)malloc(sizeof(size_t) * buf.count);
    *count = buf.count;
    
    for (i = 0; i < buf.count; i++) {
      (*keys)[i] = (const char *)buf.kts[i].data;
      (*key_lengths)[i] = buf.kts[i].size;
      (*values)[i] = buf.dts[i].data;
      (*value_sizes)[i] = buf.dts[i].size;
    }

    goto cleanup;
  }
  else {
    goto reset;
  }

failed:
  vsdb_ret = vsdb_failed;
reset:
  if (keys != NULL)
    *keys = NULL;
  if (key_lengths != NULL)
    *key_lengths = NULL;
  if (values != NULL)
    *values = NULL;
  if (value_sizes != NULL)
    *value_sizes = NULL;
  if (count != NULL)
    *count = 0;
cleanup:
  unlockdb(vsdb);
  if (buf.capacity > 0) {
    free(buf.kts);
    free(buf.dts);
  }
  return vsdb_ret;
}
#endif /* __clang_analyzer__ */

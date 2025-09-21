#ifndef FINDER_CORE_H
#define FINDER_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *path;
    const char *name;
    const char *ext;
    int64_t mtime;
    uint64_t size;
    uint64_t inode;
    uint64_t dev;
} FCFileMeta;

typedef struct {
    const char *q;
    const char *glob;
    int32_t scope;
    int32_t limit;
} FCQuery;

typedef struct {
    char *path;
    char *name;
    int64_t mtime;
    uint64_t size;
    float score;
} FCHit;

typedef struct {
    FCHit *hits;
    int32_t count;
} FCResults;

bool fc_init_index(const char *index_dir);
void fc_close_index(void);
bool fc_add_or_update(const FCFileMeta *meta, const char *utf8_content_or_null);
bool fc_commit_and_refresh(void);
FCResults fc_search(const FCQuery *query);
void fc_free_results(FCResults *results);

#ifdef __cplusplus
}
#endif

#endif /* FINDER_CORE_H */

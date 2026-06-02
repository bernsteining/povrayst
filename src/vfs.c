/*
 * vfs.c — In-memory virtual filesystem for POV-Ray WASM plugin.
 *
 * Overrides libc's fopen/fclose/fread/fwrite/fgetc/fseek/ftell/feof/ungetc
 * so that POV-Ray can read scene data from a wasm linear memory buffer
 * and write rendered output (PNG) to another buffer — all without any
 * actual WASI filesystem calls.
 *
 * Usage:
 *   1. Call vfs_register("input.pov", data, len) to make a read-only file.
 *   2. Call vfs_create_output("output.png") to make a writable capture buffer.
 *   3. Run POV-Ray normally — it calls fopen("input.pov", "r") etc.
 *   4. After render, retrieve output via vfs_get_output()/vfs_get_output_size().
 */

#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* --- Internal file descriptor table ----------------------------------- */

#define VFS_MAX_FILES 8

typedef struct {
    const char *name;          /* filename (static, not owned) */
    const unsigned char *rdata;/* read data (NULL for write-only) */
    unsigned char *wdata;      /* write buffer (NULL for read-only) */
    size_t size;               /* current data size */
    size_t wcap;               /* write buffer capacity */
    size_t pos;                /* current read/write position */
    int is_open;               /* currently opened? */
    int is_write;              /* opened for writing? */
    int eof_flag;              /* feof() state */
    int ungetc_buf;            /* ungetc buffer (-1 = empty) */
} vfs_entry;

static vfs_entry g_vfs[VFS_MAX_FILES];

/* Sentinel addresses used as fake FILE* values.  We use &g_vfs[i]
 * cast to FILE* — they're unique non-NULL pointers we can map back. */
static vfs_entry *file_to_entry(FILE *f) {
    vfs_entry *e = (vfs_entry *)f;
    if (e >= &g_vfs[0] && e < &g_vfs[VFS_MAX_FILES] && e->is_open)
        return e;
    return NULL;
}

/* --- Public API (called from povray_plugin.cpp) ----------------------- */

void vfs_register(const char *name, const void *data, size_t size) {
    for (int i = 0; i < VFS_MAX_FILES; i++) {
        if (g_vfs[i].name == NULL) {
            g_vfs[i].name = name;
            g_vfs[i].rdata = (const unsigned char *)data;
            g_vfs[i].size = size;
            g_vfs[i].wdata = NULL;
            g_vfs[i].wcap = 0;
            g_vfs[i].pos = 0;
            g_vfs[i].is_open = 0;
            g_vfs[i].is_write = 0;
            g_vfs[i].eof_flag = 0;
            g_vfs[i].ungetc_buf = -1;
            return;
        }
    }
}

void vfs_create_output(const char *name) {
    for (int i = 0; i < VFS_MAX_FILES; i++) {
        if (g_vfs[i].name == NULL) {
            g_vfs[i].name = name;
            g_vfs[i].rdata = NULL;
            g_vfs[i].wdata = NULL;
            g_vfs[i].wcap = 0;
            g_vfs[i].size = 0;
            g_vfs[i].pos = 0;
            g_vfs[i].is_open = 0;
            g_vfs[i].is_write = 0;
            g_vfs[i].eof_flag = 0;
            g_vfs[i].ungetc_buf = -1;
            return;
        }
    }
}

const void *vfs_get_output(const char *name) {
    for (int i = 0; i < VFS_MAX_FILES; i++) {
        if (g_vfs[i].name && strcmp(g_vfs[i].name, name) == 0)
            return g_vfs[i].wdata;
    }
    return NULL;
}

size_t vfs_get_output_size(const char *name) {
    for (int i = 0; i < VFS_MAX_FILES; i++) {
        if (g_vfs[i].name && strcmp(g_vfs[i].name, name) == 0)
            return g_vfs[i].size;
    }
    return 0;
}

void vfs_reset(void) {
    for (int i = 0; i < VFS_MAX_FILES; i++) {
        if (g_vfs[i].wdata) free(g_vfs[i].wdata);
        memset(&g_vfs[i], 0, sizeof(vfs_entry));
        g_vfs[i].ungetc_buf = -1;
    }
}

/* --- VFS-aware file operations ---------------------------------------- */
/*
 * We can't directly override libc's fopen/fread etc. because wasm-ld
 * treats them as strong symbols. Instead, we use names prefixed with
 * vfs_ and patch POV-Ray's OpenLocalFile to call vfs_fopen instead.
 * All operations on VFS file handles are routed through these functions.
 */

static vfs_entry *vfs_find(const char *name) {
    if (!name) return NULL;
    /* Strip leading "./" if present */
    if (name[0] == '.' && name[1] == '/') name += 2;
    for (int i = 0; i < VFS_MAX_FILES; i++) {
        if (g_vfs[i].name && strcmp(g_vfs[i].name, name) == 0)
            return &g_vfs[i];
    }
    return NULL;
}

/* Check if a FILE* is a VFS handle (as opposed to a real libc FILE*). */
int vfs_is_vfs_file(void *f) {
    vfs_entry *e = (vfs_entry *)f;
    return (e >= &g_vfs[0] && e < &g_vfs[VFS_MAX_FILES] && e->is_open);
}

/* Open a VFS file. Returns a vfs_entry* cast to FILE*, or NULL. */
void *vfs_fopen(const char *path, const char *mode) {
    vfs_entry *e = vfs_find(path);
    if (!e) return NULL;

    int writing = (mode[0] == 'w' || strchr(mode, '+') != NULL);
    e->pos = 0;
    e->eof_flag = 0;
    e->ungetc_buf = -1;
    e->is_open = 1;
    e->is_write = writing;

    if (writing && !e->rdata) {
        if (e->wdata) { free(e->wdata); e->wdata = NULL; }
        e->wcap = 65536;
        e->wdata = (unsigned char *)malloc(e->wcap);
        e->size = 0;
    }

    return (void *)e;
}

int vfs_fclose(void *stream) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    if (!e) return -1;
    e->is_open = 0;
    return 0;
}

int vfs_fgetc(void *stream) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    if (!e) return EOF;

    if (e->ungetc_buf >= 0) {
        int c = e->ungetc_buf;
        e->ungetc_buf = -1;
        return c;
    }

    const unsigned char *data = e->rdata ? e->rdata : e->wdata;
    if (!data || e->pos >= e->size) {
        e->eof_flag = 1;
        return EOF;
    }
    return data[e->pos++];
}

int vfs_ungetc(int c, void *stream) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    if (!e || c == EOF) return EOF;
    e->ungetc_buf = c;
    e->eof_flag = 0;
    return c;
}

size_t vfs_fread(void *ptr, size_t size, size_t count, void *stream) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    if (!e || size == 0 || count == 0) return 0;

    const unsigned char *data = e->rdata ? e->rdata : e->wdata;
    if (!data) return 0;

    size_t total = size * count;
    size_t avail = (e->pos < e->size) ? (e->size - e->pos) : 0;
    size_t to_read = (total < avail) ? total : avail;

    if (to_read > 0) {
        memcpy(ptr, data + e->pos, to_read);
        e->pos += to_read;
    }
    if (to_read < total) e->eof_flag = 1;
    return to_read / size;
}

size_t vfs_fwrite(const void *ptr, size_t size, size_t count, void *stream) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    if (!e || !e->is_write || size == 0 || count == 0) return 0;

    size_t total = size * count;

    while (e->pos + total > e->wcap) {
        size_t newcap = e->wcap * 2;
        if (newcap < e->pos + total) newcap = e->pos + total;
        unsigned char *newbuf = (unsigned char *)realloc(e->wdata, newcap);
        if (!newbuf) return 0;
        e->wdata = newbuf;
        e->wcap = newcap;
    }

    memcpy(e->wdata + e->pos, ptr, total);
    e->pos += total;
    if (e->pos > e->size) e->size = e->pos;
    return count;
}

int vfs_fseek(void *stream, long offset, int whence) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    if (!e) return -1;

    long newpos;
    switch (whence) {
        case SEEK_SET: newpos = offset; break;
        case SEEK_CUR: newpos = (long)e->pos + offset; break;
        case SEEK_END: newpos = (long)e->size + offset; break;
        default: return -1;
    }
    if (newpos < 0) return -1;
    e->pos = (size_t)newpos;
    e->eof_flag = 0;
    e->ungetc_buf = -1;
    return 0;
}

long vfs_ftell(void *stream) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    if (!e) return -1;
    return (long)e->pos;
}

int vfs_feof(void *stream) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    if (!e) return 1;
    return e->eof_flag;
}

int vfs_ferror(void *stream) {
    vfs_entry *e = file_to_entry((FILE *)stream);
    return (e == NULL) ? 1 : 0;
}

/*
 * vfs_redirect.h — Macro-based redirection of stdio calls to VFS.
 *
 * Included via -include flag in the compiler command line, this header
 * wraps every fopen/fread/fclose/etc. call with a VFS-aware version
 * that checks if the FILE* is a VFS handle and routes accordingly.
 *
 * This avoids patching every individual call site in POV-Ray.
 */
#ifndef VFS_REDIRECT_H
#define VFS_REDIRECT_H

#ifdef POVRAY_WASM

#include <stdio.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* VFS API */
int   vfs_is_vfs_file(void *f);
void *vfs_fopen(const char *path, const char *mode);
int   vfs_fclose(void *stream);
int   vfs_fgetc(void *stream);
int   vfs_ungetc(int c, void *stream);
size_t vfs_fread(void *ptr, size_t size, size_t count, void *stream);
size_t vfs_fwrite(const void *ptr, size_t size, size_t count, void *stream);
int   vfs_fseek(void *stream, long offset, int whence);
long  vfs_ftell(void *stream);
int   vfs_feof(void *stream);
int   vfs_ferror(void *stream);

#ifdef __cplusplus
}
#endif

/* Inline wrappers that try VFS first, fall back to real libc */

static inline FILE *vfs_wrap_fopen(const char *path, const char *mode) {
    void *vf = vfs_fopen(path, mode);
    if (vf) return (FILE *)vf;
    return NULL;
}

/* For non-VFS files (stdout, stderr, etc.), we return "success" values
 * so that code doesn't enter retry loops. Output to non-VFS files is
 * silently discarded. Reads from non-VFS files return EOF. */

static inline int vfs_wrap_fclose(FILE *f) {
    if (vfs_is_vfs_file(f)) return vfs_fclose(f);
    return 0;  /* pretend success */
}

static inline int vfs_wrap_fgetc(FILE *f) {
    if (vfs_is_vfs_file(f)) return vfs_fgetc(f);
    return EOF;
}

static inline int vfs_wrap_ungetc(int c, FILE *f) {
    if (vfs_is_vfs_file(f)) return vfs_ungetc(c, f);
    return c;  /* pretend success */
}

static inline size_t vfs_wrap_fread(void *ptr, size_t sz, size_t n, FILE *f) {
    if (vfs_is_vfs_file(f)) return vfs_fread(ptr, sz, n, f);
    return 0;  /* EOF for non-VFS reads */
}

static inline size_t vfs_wrap_fwrite(const void *ptr, size_t sz, size_t n, FILE *f) {
    if (vfs_is_vfs_file(f)) return vfs_fwrite(ptr, sz, n, f);
    return n;  /* pretend all items written (discard) */
}

static inline int vfs_wrap_fseek(FILE *f, long off, int whence) {
    if (vfs_is_vfs_file(f)) return vfs_fseek(f, off, whence);
    return 0;  /* pretend success */
}

static inline long vfs_wrap_ftell(FILE *f) {
    if (vfs_is_vfs_file(f)) return vfs_ftell(f);
    return 0;
}

static inline int vfs_wrap_feof(FILE *f) {
    if (vfs_is_vfs_file(f)) return vfs_feof(f);
    return 0;  /* not at EOF (avoid triggering retry) */
}

static inline int vfs_wrap_ferror(FILE *f) {
    if (vfs_is_vfs_file(f)) return vfs_ferror(f);
    return 0;  /* no error */
}

/* Redirect libc calls to our wrappers via macros.
 * This works because these macros are expanded in every .cpp/.c file
 * that includes this header (via -include). */
#define fopen   vfs_wrap_fopen
#define fclose  vfs_wrap_fclose
#define fgetc   vfs_wrap_fgetc
#define ungetc  vfs_wrap_ungetc
#define fread   vfs_wrap_fread
#define fwrite  vfs_wrap_fwrite
#define fseek   vfs_wrap_fseek
#define ftell   vfs_wrap_ftell
#define feof    vfs_wrap_feof
#define ferror  vfs_wrap_ferror

#endif /* POVRAY_WASM */
#endif /* VFS_REDIRECT_H */

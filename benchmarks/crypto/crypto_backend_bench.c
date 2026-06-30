/*
 * Pure libcrypto microbenchmark for Apple Silicon.
 *
 * Benchmarks:
 *   - AES-256-GCM encrypt/decrypt throughput through EVP.
 *   - curve25519-sha256 style KEX cost as X25519 derive + SHA256.
 *
 * This intentionally avoids compile-time OpenSSL/LibreSSL/AWS-LC headers so one
 * binary can dlopen Homebrew AWS-LC, Homebrew OpenSSL, and macOS LibreSSL.
 */

#include <dlfcn.h>
#include <errno.h>
#include <mach/mach_time.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>

typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;
typedef struct evp_cipher_st EVP_CIPHER;
typedef struct evp_aead_st EVP_AEAD;
typedef struct evp_aead_ctx_st EVP_AEAD_CTX;
typedef struct engine_st ENGINE;
typedef struct evp_pkey_ctx_st EVP_PKEY_CTX;
typedef struct evp_pkey_st EVP_PKEY;

#define OPENSSL_VERSION_SELECTOR 0
#define EVP_CTRL_GCM_SET_IVLEN 0x9
#define EVP_CTRL_GCM_GET_TAG 0x10
#define EVP_CTRL_GCM_SET_TAG 0x11

#define AES_GCM_KEY_LEN 32
#define AES_GCM_IV_LEN 12
#define AES_GCM_TAG_LEN 16
#define X25519_SECRET_LEN 32
#define SHA256_LEN 32

struct backend_spec {
    const char *name;
    const char *path;
};

struct crypto_api {
    const char *name;
    const char *path;
    void *handle;

    const char *(*OpenSSL_version)(int);
    const char *(*SSLeay_version)(int);
    unsigned long (*ERR_get_error)(void);
    void (*ERR_error_string_n)(unsigned long, char *, size_t);
    int (*OPENSSL_init_crypto)(uint64_t, const void *);
    void (*OpenSSL_add_all_ciphers)(void);

    EVP_CIPHER_CTX *(*EVP_CIPHER_CTX_new)(void);
    int (*EVP_CIPHER_CTX_reset)(EVP_CIPHER_CTX *);
    void (*EVP_CIPHER_CTX_free)(EVP_CIPHER_CTX *);
    const EVP_CIPHER *(*EVP_aes_256_gcm)(void);
    const EVP_CIPHER *(*EVP_get_cipherbyname)(const char *);
    int (*EVP_EncryptInit_ex)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *,
                              const unsigned char *, const unsigned char *);
    int (*EVP_EncryptUpdate)(EVP_CIPHER_CTX *, unsigned char *, int *,
                             const unsigned char *, int);
    int (*EVP_EncryptFinal_ex)(EVP_CIPHER_CTX *, unsigned char *, int *);
    int (*EVP_DecryptInit_ex)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *,
                              const unsigned char *, const unsigned char *);
    int (*EVP_DecryptUpdate)(EVP_CIPHER_CTX *, unsigned char *, int *,
                             const unsigned char *, int);
    int (*EVP_DecryptFinal_ex)(EVP_CIPHER_CTX *, unsigned char *, int *);
    int (*EVP_CIPHER_CTX_ctrl)(EVP_CIPHER_CTX *, int, int, void *);
    int (*EVP_CipherInit_ex)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *,
                             const unsigned char *, const unsigned char *, int);
    int (*EVP_CipherUpdate)(EVP_CIPHER_CTX *, unsigned char *, int *,
                            const unsigned char *, int);
    int (*EVP_CipherFinal_ex)(EVP_CIPHER_CTX *, unsigned char *, int *);
    int (*EVP_Cipher)(EVP_CIPHER_CTX *, unsigned char *, const unsigned char *, unsigned int);

    const EVP_AEAD *(*EVP_aead_aes_256_gcm)(void);
    size_t (*EVP_AEAD_nonce_length)(const EVP_AEAD *);
    size_t (*EVP_AEAD_max_overhead)(const EVP_AEAD *);
    int (*EVP_AEAD_CTX_init)(EVP_AEAD_CTX *, const EVP_AEAD *, const unsigned char *,
                             size_t, size_t, ENGINE *);
    void (*EVP_AEAD_CTX_cleanup)(EVP_AEAD_CTX *);
    int (*EVP_AEAD_CTX_seal)(const EVP_AEAD_CTX *, unsigned char *, size_t *, size_t,
                             const unsigned char *, size_t, const unsigned char *,
                             size_t, const unsigned char *, size_t);
    int (*EVP_AEAD_CTX_open)(const EVP_AEAD_CTX *, unsigned char *, size_t *, size_t,
                             const unsigned char *, size_t, const unsigned char *,
                             size_t, const unsigned char *, size_t);

    int (*OBJ_sn2nid)(const char *);
    EVP_PKEY_CTX *(*EVP_PKEY_CTX_new_id)(int, ENGINE *);
    EVP_PKEY_CTX *(*EVP_PKEY_CTX_new)(EVP_PKEY *, ENGINE *);
    void (*EVP_PKEY_CTX_free)(EVP_PKEY_CTX *);
    int (*EVP_PKEY_keygen_init)(EVP_PKEY_CTX *);
    int (*EVP_PKEY_keygen)(EVP_PKEY_CTX *, EVP_PKEY **);
    int (*EVP_PKEY_derive_init)(EVP_PKEY_CTX *);
    int (*EVP_PKEY_derive_set_peer)(EVP_PKEY_CTX *, EVP_PKEY *);
    int (*EVP_PKEY_derive)(EVP_PKEY_CTX *, unsigned char *, size_t *);
    void (*EVP_PKEY_free)(EVP_PKEY *);
    unsigned char *(*SHA256)(const unsigned char *, size_t, unsigned char *);
};

struct run_config {
    double seconds;
    int reps;
    size_t aes_message_len;
    const char *only_backend;
    bool no_aes;
    bool no_evp_aes;
    bool no_curve;
};

struct sample {
    double wall_s;
    double user_s;
    double sys_s;
    uint64_t ops;
    uint64_t bytes;
    uint64_t checksum;
    long maxrss_bytes;
};

static const struct backend_spec default_backends[] = {
    {"aws-lc-brew", "/opt/homebrew/opt/aws-lc/lib/libcrypto.dylib"},
    {"openssl3-brew", "/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib"},
    {"libressl-macos", "/usr/lib/libcrypto.46.dylib"},
};

static mach_timebase_info_data_t g_timebase;

static double now_s(void) {
    const uint64_t t = mach_absolute_time();
    const double ns = (double)t * (double)g_timebase.numer / (double)g_timebase.denom;
    return ns / 1000000000.0;
}

static double tv_to_s(const struct timeval *tv) {
    return (double)tv->tv_sec + (double)tv->tv_usec / 1000000.0;
}

static void get_usage(double *user_s, double *sys_s, long *maxrss_bytes) {
    struct rusage ru;
    memset(&ru, 0, sizeof(ru));
    if (getrusage(RUSAGE_SELF, &ru) != 0) {
        *user_s = 0.0;
        *sys_s = 0.0;
        *maxrss_bytes = 0;
        return;
    }
    *user_s = tv_to_s(&ru.ru_utime);
    *sys_s = tv_to_s(&ru.ru_stime);
    *maxrss_bytes = ru.ru_maxrss;
}

static void *xcalloc(size_t count, size_t size) {
    void *p = calloc(count, size);
    if (p == NULL) {
        fprintf(stderr, "calloc failed: %s\n", strerror(errno));
        exit(2);
    }
    return p;
}

static void *aligned_alloc_or_die(size_t align, size_t size) {
    void *p = NULL;
    if (posix_memalign(&p, align, size) != 0) {
        fprintf(stderr, "posix_memalign(%zu, %zu) failed\n", align, size);
        exit(2);
    }
    memset(p, 0, size);
    return p;
}

static void fill_pattern(unsigned char *buf, size_t len, uint32_t seed) {
    uint32_t x = seed;
    for (size_t i = 0; i < len; i++) {
        x = x * 1664525u + 1013904223u;
        buf[i] = (unsigned char)(x >> 24);
    }
}

static uint64_t mix_checksum(uint64_t acc, const unsigned char *buf, size_t len) {
    const size_t stride = len < 4096 ? 1 : len / 4096;
    for (size_t i = 0; i < len; i += stride) {
        acc ^= (uint64_t)buf[i] + 0x9e3779b97f4a7c15ULL + (acc << 6) + (acc >> 2);
    }
    if (len > 0) {
        acc ^= buf[len - 1];
    }
    return acc;
}

static void *sym_required(struct crypto_api *api, const char *name) {
    void *p = dlsym(api->handle, name);
    if (p == NULL) {
        fprintf(stderr, "%s: required symbol missing: %s\n", api->name, name);
        exit(3);
    }
    return p;
}

static void *sym_optional(struct crypto_api *api, const char *name) {
    return dlsym(api->handle, name);
}

static void load_api(struct crypto_api *api, const struct backend_spec *spec) {
    memset(api, 0, sizeof(*api));
    api->name = spec->name;
    api->path = spec->path;
    api->handle = dlopen(spec->path, RTLD_NOW | RTLD_LOCAL);
    if (api->handle == NULL) {
        fprintf(stderr, "%s: dlopen failed for %s: %s\n", spec->name, spec->path,
                dlerror());
        exit(3);
    }

    api->OpenSSL_version = (const char *(*)(int))sym_optional(api, "OpenSSL_version");
    api->SSLeay_version = (const char *(*)(int))sym_optional(api, "SSLeay_version");
    api->ERR_get_error = (unsigned long (*)(void))sym_optional(api, "ERR_get_error");
    api->ERR_error_string_n =
        (void (*)(unsigned long, char *, size_t))sym_optional(api, "ERR_error_string_n");
    api->OPENSSL_init_crypto =
        (int (*)(uint64_t, const void *))sym_optional(api, "OPENSSL_init_crypto");
    api->OpenSSL_add_all_ciphers =
        (void (*)(void))sym_optional(api, "OpenSSL_add_all_ciphers");

    if (api->OPENSSL_init_crypto != NULL && api->OPENSSL_init_crypto(0, NULL) != 1) {
        fprintf(stderr, "%s: OPENSSL_init_crypto failed\n", api->name);
        exit(3);
    }
    if (api->OpenSSL_add_all_ciphers != NULL) {
        api->OpenSSL_add_all_ciphers();
    }

    api->EVP_CIPHER_CTX_new =
        (EVP_CIPHER_CTX *(*)(void))sym_required(api, "EVP_CIPHER_CTX_new");
    api->EVP_CIPHER_CTX_reset =
        (int (*)(EVP_CIPHER_CTX *))sym_required(api, "EVP_CIPHER_CTX_reset");
    api->EVP_CIPHER_CTX_free =
        (void (*)(EVP_CIPHER_CTX *))sym_required(api, "EVP_CIPHER_CTX_free");
    api->EVP_aes_256_gcm =
        (const EVP_CIPHER *(*)(void))sym_required(api, "EVP_aes_256_gcm");
    api->EVP_get_cipherbyname =
        (const EVP_CIPHER *(*)(const char *))sym_required(api, "EVP_get_cipherbyname");
    api->EVP_EncryptInit_ex =
        (int (*)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *,
                 const unsigned char *, const unsigned char *))
            sym_required(api, "EVP_EncryptInit_ex");
    api->EVP_EncryptUpdate =
        (int (*)(EVP_CIPHER_CTX *, unsigned char *, int *, const unsigned char *, int))
            sym_required(api, "EVP_EncryptUpdate");
    api->EVP_EncryptFinal_ex =
        (int (*)(EVP_CIPHER_CTX *, unsigned char *, int *))
            sym_required(api, "EVP_EncryptFinal_ex");
    api->EVP_DecryptInit_ex =
        (int (*)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *,
                 const unsigned char *, const unsigned char *))
            sym_required(api, "EVP_DecryptInit_ex");
    api->EVP_DecryptUpdate =
        (int (*)(EVP_CIPHER_CTX *, unsigned char *, int *, const unsigned char *, int))
            sym_required(api, "EVP_DecryptUpdate");
    api->EVP_DecryptFinal_ex =
        (int (*)(EVP_CIPHER_CTX *, unsigned char *, int *))
            sym_required(api, "EVP_DecryptFinal_ex");
    api->EVP_CIPHER_CTX_ctrl =
        (int (*)(EVP_CIPHER_CTX *, int, int, void *))
            sym_required(api, "EVP_CIPHER_CTX_ctrl");
    api->EVP_CipherInit_ex =
        (int (*)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *,
                 const unsigned char *, const unsigned char *, int))
            sym_required(api, "EVP_CipherInit_ex");
    api->EVP_CipherUpdate =
        (int (*)(EVP_CIPHER_CTX *, unsigned char *, int *, const unsigned char *, int))
            sym_required(api, "EVP_CipherUpdate");
    api->EVP_CipherFinal_ex =
        (int (*)(EVP_CIPHER_CTX *, unsigned char *, int *))
            sym_required(api, "EVP_CipherFinal_ex");
    api->EVP_Cipher =
        (int (*)(EVP_CIPHER_CTX *, unsigned char *, const unsigned char *, unsigned int))
            sym_required(api, "EVP_Cipher");

    api->EVP_aead_aes_256_gcm =
        (const EVP_AEAD *(*)(void))sym_optional(api, "EVP_aead_aes_256_gcm");
    api->EVP_AEAD_nonce_length =
        (size_t (*)(const EVP_AEAD *))sym_optional(api, "EVP_AEAD_nonce_length");
    api->EVP_AEAD_max_overhead =
        (size_t (*)(const EVP_AEAD *))sym_optional(api, "EVP_AEAD_max_overhead");
    api->EVP_AEAD_CTX_init =
        (int (*)(EVP_AEAD_CTX *, const EVP_AEAD *, const unsigned char *, size_t,
                 size_t, ENGINE *))
            sym_optional(api, "EVP_AEAD_CTX_init");
    api->EVP_AEAD_CTX_cleanup =
        (void (*)(EVP_AEAD_CTX *))sym_optional(api, "EVP_AEAD_CTX_cleanup");
    api->EVP_AEAD_CTX_seal =
        (int (*)(const EVP_AEAD_CTX *, unsigned char *, size_t *, size_t,
                 const unsigned char *, size_t, const unsigned char *, size_t,
                 const unsigned char *, size_t))
            sym_optional(api, "EVP_AEAD_CTX_seal");
    api->EVP_AEAD_CTX_open =
        (int (*)(const EVP_AEAD_CTX *, unsigned char *, size_t *, size_t,
                 const unsigned char *, size_t, const unsigned char *, size_t,
                 const unsigned char *, size_t))
            sym_optional(api, "EVP_AEAD_CTX_open");

    api->OBJ_sn2nid = (int (*)(const char *))sym_required(api, "OBJ_sn2nid");
    api->EVP_PKEY_CTX_new_id =
        (EVP_PKEY_CTX *(*)(int, ENGINE *))sym_required(api, "EVP_PKEY_CTX_new_id");
    api->EVP_PKEY_CTX_new =
        (EVP_PKEY_CTX *(*)(EVP_PKEY *, ENGINE *))sym_required(api, "EVP_PKEY_CTX_new");
    api->EVP_PKEY_CTX_free =
        (void (*)(EVP_PKEY_CTX *))sym_required(api, "EVP_PKEY_CTX_free");
    api->EVP_PKEY_keygen_init =
        (int (*)(EVP_PKEY_CTX *))sym_required(api, "EVP_PKEY_keygen_init");
    api->EVP_PKEY_keygen =
        (int (*)(EVP_PKEY_CTX *, EVP_PKEY **))sym_required(api, "EVP_PKEY_keygen");
    api->EVP_PKEY_derive_init =
        (int (*)(EVP_PKEY_CTX *))sym_required(api, "EVP_PKEY_derive_init");
    api->EVP_PKEY_derive_set_peer =
        (int (*)(EVP_PKEY_CTX *, EVP_PKEY *))
            sym_required(api, "EVP_PKEY_derive_set_peer");
    api->EVP_PKEY_derive =
        (int (*)(EVP_PKEY_CTX *, unsigned char *, size_t *))
            sym_required(api, "EVP_PKEY_derive");
    api->EVP_PKEY_free = (void (*)(EVP_PKEY *))sym_required(api, "EVP_PKEY_free");
    api->SHA256 =
        (unsigned char *(*)(const unsigned char *, size_t, unsigned char *))
            sym_required(api, "SHA256");
}

static const char *version_string(struct crypto_api *api) {
    if (api->OpenSSL_version != NULL) {
        return api->OpenSSL_version(OPENSSL_VERSION_SELECTOR);
    }
    if (api->SSLeay_version != NULL) {
        return api->SSLeay_version(OPENSSL_VERSION_SELECTOR);
    }
    return "unknown";
}

static void backend_error(struct crypto_api *api, const char *what) {
    unsigned long err = 0;
    char errbuf[256];
    errbuf[0] = '\0';
    if (api->ERR_get_error != NULL) {
        err = api->ERR_get_error();
    }
    if (err != 0 && api->ERR_error_string_n != NULL) {
        api->ERR_error_string_n(err, errbuf, sizeof(errbuf));
    }
    fprintf(stderr, "%s: %s failed%s%s\n", api->name, what,
            errbuf[0] ? ": " : "", errbuf);
    exit(4);
}

static void aes_encrypt_message(struct crypto_api *api, EVP_CIPHER_CTX *ctx,
                                const unsigned char *key, const unsigned char *iv,
                                const unsigned char *in, unsigned char *out,
                                size_t len, unsigned char tag[AES_GCM_TAG_LEN]) {
    int out_len = 0;
    int final_len = 0;
    const EVP_CIPHER *cipher = api->EVP_aes_256_gcm();
    if (api->EVP_CIPHER_CTX_reset(ctx) != 1) {
        backend_error(api, "EVP_CIPHER_CTX_reset");
    }
    if (api->EVP_EncryptInit_ex(ctx, cipher, NULL, NULL, NULL) != 1) {
        backend_error(api, "EVP_EncryptInit_ex(aes-256-gcm/cipher)");
    }
    if (api->EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, AES_GCM_IV_LEN, NULL) != 1) {
        backend_error(api, "EVP_CIPHER_CTX_ctrl(SET_IVLEN)");
    }
    if (api->EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv) != 1) {
        backend_error(api, "EVP_EncryptInit_ex(aes-256-gcm/keyiv)");
    }
    if (api->EVP_EncryptUpdate(ctx, out, &out_len, in, (int)len) != 1) {
        backend_error(api, "EVP_EncryptUpdate(aes-256-gcm)");
    }
    if (api->EVP_EncryptFinal_ex(ctx, out + out_len, &final_len) != 1) {
        backend_error(api, "EVP_EncryptFinal_ex(aes-256-gcm)");
    }
    if (api->EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, AES_GCM_TAG_LEN, tag) != 1) {
        backend_error(api, "EVP_CIPHER_CTX_ctrl(GET_TAG)");
    }
}

static void aes_decrypt_message(struct crypto_api *api, EVP_CIPHER_CTX *ctx,
                                const unsigned char *key, const unsigned char *iv,
                                const unsigned char *in, unsigned char *out,
                                size_t len, const unsigned char tag[AES_GCM_TAG_LEN]) {
    int out_len = 0;
    int final_len = 0;
    const EVP_CIPHER *cipher = api->EVP_aes_256_gcm();
    unsigned char tag_copy[AES_GCM_TAG_LEN];
    memcpy(tag_copy, tag, sizeof(tag_copy));

    if (api->EVP_CIPHER_CTX_reset(ctx) != 1) {
        backend_error(api, "EVP_CIPHER_CTX_reset");
    }
    if (api->EVP_DecryptInit_ex(ctx, cipher, NULL, NULL, NULL) != 1) {
        backend_error(api, "EVP_DecryptInit_ex(aes-256-gcm/cipher)");
    }
    if (api->EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, AES_GCM_IV_LEN, NULL) != 1) {
        backend_error(api, "EVP_CIPHER_CTX_ctrl(SET_IVLEN)");
    }
    if (api->EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv) != 1) {
        backend_error(api, "EVP_DecryptInit_ex(aes-256-gcm/keyiv)");
    }
    if (api->EVP_DecryptUpdate(ctx, out, &out_len, in, (int)len) != 1) {
        backend_error(api, "EVP_DecryptUpdate(aes-256-gcm)");
    }
    if (api->EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, AES_GCM_TAG_LEN,
                                 tag_copy) != 1) {
        backend_error(api, "EVP_CIPHER_CTX_ctrl(SET_TAG)");
    }
    if (api->EVP_DecryptFinal_ex(ctx, out + out_len, &final_len) != 1) {
        backend_error(api, "EVP_DecryptFinal_ex(aes-256-gcm)");
    }
}

static struct sample bench_aes_gcm(struct crypto_api *api, const struct run_config *cfg,
                                   bool decrypt) {
    unsigned char key[AES_GCM_KEY_LEN];
    unsigned char iv[AES_GCM_IV_LEN];
    unsigned char tag[AES_GCM_TAG_LEN];
    fill_pattern(key, sizeof(key), 0x12345678u);
    fill_pattern(iv, sizeof(iv), 0x87654321u);

    unsigned char *plain = aligned_alloc_or_die(64, cfg->aes_message_len);
    unsigned char *cipher = aligned_alloc_or_die(64, cfg->aes_message_len);
    unsigned char *out = aligned_alloc_or_die(64, cfg->aes_message_len);
    fill_pattern(plain, cfg->aes_message_len, 0xc0ffeeu);

    EVP_CIPHER_CTX *ctx = api->EVP_CIPHER_CTX_new();
    if (ctx == NULL) {
        backend_error(api, "EVP_CIPHER_CTX_new");
    }
    aes_encrypt_message(api, ctx, key, iv, plain, cipher, cfg->aes_message_len, tag);

    double user0 = 0.0;
    double sys0 = 0.0;
    double user1 = 0.0;
    double sys1 = 0.0;
    long rss0 = 0;
    long rss1 = 0;
    get_usage(&user0, &sys0, &rss0);
    const double t0 = now_s();
    const double deadline = t0 + cfg->seconds;

    struct sample s;
    memset(&s, 0, sizeof(s));
    do {
        if (decrypt) {
            aes_decrypt_message(api, ctx, key, iv, cipher, out, cfg->aes_message_len, tag);
        } else {
            aes_encrypt_message(api, ctx, key, iv, plain, out, cfg->aes_message_len, tag);
        }
        s.ops++;
        s.bytes += cfg->aes_message_len;
        s.checksum = mix_checksum(s.checksum, out, cfg->aes_message_len);
    } while (now_s() < deadline);

    const double t1 = now_s();
    get_usage(&user1, &sys1, &rss1);
    s.wall_s = t1 - t0;
    s.user_s = user1 - user0;
    s.sys_s = sys1 - sys0;
    s.maxrss_bytes = rss1 > rss0 ? rss1 : rss0;

    api->EVP_CIPHER_CTX_free(ctx);
    free(plain);
    free(cipher);
    free(out);
    return s;
}

static bool has_native_aead(const struct crypto_api *api) {
    return api->EVP_aead_aes_256_gcm != NULL &&
           api->EVP_AEAD_nonce_length != NULL &&
           api->EVP_AEAD_max_overhead != NULL &&
           api->EVP_AEAD_CTX_init != NULL &&
           api->EVP_AEAD_CTX_cleanup != NULL &&
           api->EVP_AEAD_CTX_seal != NULL &&
           api->EVP_AEAD_CTX_open != NULL;
}

static void aead_ctx_init_or_die(struct crypto_api *api, EVP_AEAD_CTX *ctx,
                                 const EVP_AEAD *aead, const unsigned char *key) {
    if (api->EVP_AEAD_CTX_init(ctx, aead, key, AES_GCM_KEY_LEN,
                               AES_GCM_TAG_LEN, NULL) != 1) {
        backend_error(api, "EVP_AEAD_CTX_init(aes-256-gcm)");
    }
}

static struct sample bench_aes_gcm_aead(struct crypto_api *api,
                                        const struct run_config *cfg,
                                        bool open_mode) {
    unsigned char key[AES_GCM_KEY_LEN];
    unsigned char nonce[AES_GCM_IV_LEN];
    fill_pattern(key, sizeof(key), 0x12345678u);
    fill_pattern(nonce, sizeof(nonce), 0x87654321u);

    const EVP_AEAD *aead = api->EVP_aead_aes_256_gcm();
    if (aead == NULL) {
        backend_error(api, "EVP_aead_aes_256_gcm");
    }
    const size_t nonce_len = api->EVP_AEAD_nonce_length(aead);
    const size_t overhead = api->EVP_AEAD_max_overhead(aead);
    if (nonce_len > sizeof(nonce) || overhead < AES_GCM_TAG_LEN) {
        backend_error(api, "EVP_AEAD metadata");
    }

    unsigned char *plain = aligned_alloc_or_die(64, cfg->aes_message_len);
    unsigned char *sealed = aligned_alloc_or_die(64, cfg->aes_message_len + overhead);
    unsigned char *out = aligned_alloc_or_die(64, cfg->aes_message_len + overhead);
    fill_pattern(plain, cfg->aes_message_len, 0xc0ffeeu);

    EVP_AEAD_CTX *ctx = aligned_alloc_or_die(64, 4096);
    aead_ctx_init_or_die(api, ctx, aead, key);

    size_t sealed_len = 0;
    if (api->EVP_AEAD_CTX_seal(ctx, sealed, &sealed_len,
                               cfg->aes_message_len + overhead,
                               nonce, nonce_len, plain, cfg->aes_message_len,
                               NULL, 0) != 1) {
        backend_error(api, "EVP_AEAD_CTX_seal(warmup)");
    }

    double user0 = 0.0;
    double sys0 = 0.0;
    double user1 = 0.0;
    double sys1 = 0.0;
    long rss0 = 0;
    long rss1 = 0;
    get_usage(&user0, &sys0, &rss0);
    const double t0 = now_s();
    const double deadline = t0 + cfg->seconds;

    struct sample s;
    memset(&s, 0, sizeof(s));
    do {
        size_t out_len = 0;
        if (open_mode) {
            if (api->EVP_AEAD_CTX_open(ctx, out, &out_len, cfg->aes_message_len,
                                       nonce, nonce_len, sealed, sealed_len,
                                       NULL, 0) != 1) {
                backend_error(api, "EVP_AEAD_CTX_open");
            }
        } else {
            if (api->EVP_AEAD_CTX_seal(ctx, out, &out_len,
                                       cfg->aes_message_len + overhead,
                                       nonce, nonce_len, plain, cfg->aes_message_len,
                                       NULL, 0) != 1) {
                backend_error(api, "EVP_AEAD_CTX_seal");
            }
        }
        s.ops++;
        s.bytes += cfg->aes_message_len;
        s.checksum = mix_checksum(s.checksum, out, out_len);
    } while (now_s() < deadline);

    const double t1 = now_s();
    get_usage(&user1, &sys1, &rss1);
    s.wall_s = t1 - t0;
    s.user_s = user1 - user0;
    s.sys_s = sys1 - sys0;
    s.maxrss_bytes = rss1 > rss0 ? rss1 : rss0;

    api->EVP_AEAD_CTX_cleanup(ctx);
    free(ctx);
    free(plain);
    free(sealed);
    free(out);
    return s;
}

static void make_x25519_keypair(struct crypto_api *api, EVP_PKEY **out_key) {
    const int nid = api->OBJ_sn2nid("X25519");
    if (nid <= 0) {
        backend_error(api, "OBJ_sn2nid(X25519)");
    }
    EVP_PKEY_CTX *ctx = api->EVP_PKEY_CTX_new_id(nid, NULL);
    if (ctx == NULL) {
        backend_error(api, "EVP_PKEY_CTX_new_id(X25519)");
    }
    if (api->EVP_PKEY_keygen_init(ctx) != 1) {
        backend_error(api, "EVP_PKEY_keygen_init");
    }
    if (api->EVP_PKEY_keygen(ctx, out_key) != 1 || *out_key == NULL) {
        backend_error(api, "EVP_PKEY_keygen");
    }
    api->EVP_PKEY_CTX_free(ctx);
}

static void x25519_sha256_once(struct crypto_api *api, EVP_PKEY *local_key,
                               EVP_PKEY *peer_key, unsigned char hash[SHA256_LEN],
                               bool fresh_ctx, EVP_PKEY_CTX *reused_ctx) {
    unsigned char secret[X25519_SECRET_LEN];
    size_t secret_len = sizeof(secret);
    EVP_PKEY_CTX *ctx = reused_ctx;

    if (fresh_ctx) {
        ctx = api->EVP_PKEY_CTX_new(local_key, NULL);
        if (ctx == NULL) {
            backend_error(api, "EVP_PKEY_CTX_new(local)");
        }
        if (api->EVP_PKEY_derive_init(ctx) != 1) {
            backend_error(api, "EVP_PKEY_derive_init");
        }
        if (api->EVP_PKEY_derive_set_peer(ctx, peer_key) != 1) {
            backend_error(api, "EVP_PKEY_derive_set_peer");
        }
    }

    if (api->EVP_PKEY_derive(ctx, secret, &secret_len) != 1 ||
        secret_len != X25519_SECRET_LEN) {
        backend_error(api, "EVP_PKEY_derive");
    }
    if (api->SHA256(secret, secret_len, hash) == NULL) {
        backend_error(api, "SHA256");
    }

    if (fresh_ctx) {
        api->EVP_PKEY_CTX_free(ctx);
    }
}

static struct sample bench_curve25519_sha256(struct crypto_api *api,
                                             const struct run_config *cfg,
                                             bool fresh_ctx) {
    EVP_PKEY *local_key = NULL;
    EVP_PKEY *peer_key = NULL;
    EVP_PKEY_CTX *reused_ctx = NULL;
    unsigned char hash[SHA256_LEN];

    make_x25519_keypair(api, &local_key);
    make_x25519_keypair(api, &peer_key);

    if (!fresh_ctx) {
        reused_ctx = api->EVP_PKEY_CTX_new(local_key, NULL);
        if (reused_ctx == NULL) {
            backend_error(api, "EVP_PKEY_CTX_new(local)");
        }
        if (api->EVP_PKEY_derive_init(reused_ctx) != 1) {
            backend_error(api, "EVP_PKEY_derive_init");
        }
        if (api->EVP_PKEY_derive_set_peer(reused_ctx, peer_key) != 1) {
            backend_error(api, "EVP_PKEY_derive_set_peer");
        }
    }

    x25519_sha256_once(api, local_key, peer_key, hash, fresh_ctx, reused_ctx);

    double user0 = 0.0;
    double sys0 = 0.0;
    double user1 = 0.0;
    double sys1 = 0.0;
    long rss0 = 0;
    long rss1 = 0;
    get_usage(&user0, &sys0, &rss0);
    const double t0 = now_s();
    const double deadline = t0 + cfg->seconds;

    struct sample s;
    memset(&s, 0, sizeof(s));
    do {
        x25519_sha256_once(api, local_key, peer_key, hash, fresh_ctx, reused_ctx);
        s.ops++;
        s.checksum = mix_checksum(s.checksum, hash, sizeof(hash));
    } while (now_s() < deadline);

    const double t1 = now_s();
    get_usage(&user1, &sys1, &rss1);
    s.wall_s = t1 - t0;
    s.user_s = user1 - user0;
    s.sys_s = sys1 - sys0;
    s.maxrss_bytes = rss1 > rss0 ? rss1 : rss0;

    if (reused_ctx != NULL) {
        api->EVP_PKEY_CTX_free(reused_ctx);
    }
    api->EVP_PKEY_free(local_key);
    api->EVP_PKEY_free(peer_key);
    return s;
}

static int cmp_double(const void *a, const void *b) {
    const double da = *(const double *)a;
    const double db = *(const double *)b;
    return (da > db) - (da < db);
}

static double median(double *values, int n) {
    qsort(values, (size_t)n, sizeof(values[0]), cmp_double);
    if ((n & 1) != 0) {
        return values[n / 2];
    }
    return (values[n / 2 - 1] + values[n / 2]) / 2.0;
}

static void csv_string(const char *s) {
    putchar('"');
    for (; *s != '\0'; s++) {
        if (*s == '"') {
            putchar('"');
        }
        putchar(*s);
    }
    putchar('"');
}

static void print_result(struct crypto_api *api, const struct run_config *cfg,
                         const char *test, size_t message_bytes,
                         struct sample *samples, int n) {
    double *mib_s = xcalloc((size_t)n, sizeof(*mib_s));
    double *ops_s = xcalloc((size_t)n, sizeof(*ops_s));
    double *ns_op = xcalloc((size_t)n, sizeof(*ns_op));
    double *cpu_pct = xcalloc((size_t)n, sizeof(*cpu_pct));
    double *rss_mib = xcalloc((size_t)n, sizeof(*rss_mib));
    uint64_t checksum = 0;

    for (int i = 0; i < n; i++) {
        const double cpu_s = samples[i].user_s + samples[i].sys_s;
        mib_s[i] = samples[i].wall_s > 0.0
                       ? ((double)samples[i].bytes / 1048576.0) / samples[i].wall_s
                       : 0.0;
        ops_s[i] = samples[i].wall_s > 0.0 ? (double)samples[i].ops / samples[i].wall_s : 0.0;
        ns_op[i] = samples[i].ops > 0
                       ? samples[i].wall_s * 1000000000.0 / (double)samples[i].ops
                       : 0.0;
        cpu_pct[i] = samples[i].wall_s > 0.0 ? cpu_s * 100.0 / samples[i].wall_s : 0.0;
        rss_mib[i] = (double)samples[i].maxrss_bytes / 1048576.0;
        checksum ^= samples[i].checksum;
    }

    csv_string(api->name);
    putchar(',');
    csv_string(api->path);
    putchar(',');
    csv_string(version_string(api));
    printf(",%s,%zu,%.3f,%d,%.3f,%.3f,%.1f,%.1f,%.2f,0x%016llx\n",
           test, message_bytes, cfg->seconds, n, median(mib_s, n), median(ops_s, n),
           median(ns_op, n), median(cpu_pct, n), median(rss_mib, n),
           (unsigned long long)checksum);

    free(mib_s);
    free(ops_s);
    free(ns_op);
    free(cpu_pct);
    free(rss_mib);
}

static void run_test(struct crypto_api *api, const struct run_config *cfg,
                     const char *test_name,
                     struct sample (*fn)(struct crypto_api *, const struct run_config *),
                     size_t message_bytes) {
    struct sample *samples = xcalloc((size_t)cfg->reps, sizeof(*samples));
    for (int i = 0; i < cfg->reps; i++) {
        samples[i] = fn(api, cfg);
    }
    print_result(api, cfg, test_name, message_bytes, samples, cfg->reps);
    free(samples);
}

static struct sample bench_aes_encrypt_adapter(struct crypto_api *api,
                                               const struct run_config *cfg) {
    return bench_aes_gcm(api, cfg, false);
}

static struct sample bench_aes_decrypt_adapter(struct crypto_api *api,
                                               const struct run_config *cfg) {
    return bench_aes_gcm(api, cfg, true);
}

static struct sample bench_aead_seal_adapter(struct crypto_api *api,
                                             const struct run_config *cfg) {
    return bench_aes_gcm_aead(api, cfg, false);
}

static struct sample bench_aead_open_adapter(struct crypto_api *api,
                                             const struct run_config *cfg) {
    return bench_aes_gcm_aead(api, cfg, true);
}

static struct sample bench_curve_fresh_adapter(struct crypto_api *api,
                                               const struct run_config *cfg) {
    return bench_curve25519_sha256(api, cfg, true);
}

static struct sample bench_curve_reuse_adapter(struct crypto_api *api,
                                               const struct run_config *cfg) {
    return bench_curve25519_sha256(api, cfg, false);
}

static void usage(const char *argv0) {
    fprintf(stderr,
            "usage: %s [--seconds N] [--reps N] [--aes-message-kib N] [--only NAME]\n"
            "          [--no-aes] [--no-evp-aes] [--no-curve]\n"
            "\n"
            "Outputs CSV comparing Homebrew AWS-LC, Homebrew OpenSSL, and macOS LibreSSL.\n",
            argv0);
}

static size_t parse_size(const char *s, const char *name) {
    char *end = NULL;
    errno = 0;
    unsigned long long v = strtoull(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0' || v == 0) {
        fprintf(stderr, "invalid %s: %s\n", name, s);
        exit(2);
    }
    return (size_t)v;
}

static double parse_double(const char *s, const char *name) {
    char *end = NULL;
    errno = 0;
    double v = strtod(s, &end);
    if (errno != 0 || end == s || *end != '\0' || v <= 0.0) {
        fprintf(stderr, "invalid %s: %s\n", name, s);
        exit(2);
    }
    return v;
}

int main(int argc, char **argv) {
    struct run_config cfg;
    cfg.seconds = 1.0;
    cfg.reps = 5;
    cfg.aes_message_len = 1024 * 1024;
    cfg.only_backend = NULL;
    cfg.no_aes = false;
    cfg.no_evp_aes = false;
    cfg.no_curve = false;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
            cfg.seconds = parse_double(argv[++i], "seconds");
        } else if (strcmp(argv[i], "--reps") == 0 && i + 1 < argc) {
            cfg.reps = (int)parse_size(argv[++i], "reps");
            if (cfg.reps <= 0 || cfg.reps > 1000) {
                fprintf(stderr, "reps must be between 1 and 1000\n");
                return 2;
            }
        } else if (strcmp(argv[i], "--aes-message-kib") == 0 && i + 1 < argc) {
            cfg.aes_message_len = parse_size(argv[++i], "aes-message-kib") * 1024;
            if (cfg.aes_message_len > (size_t)INT32_MAX) {
                fprintf(stderr, "AES message length must fit in int for EVP\n");
                return 2;
            }
        } else if (strcmp(argv[i], "--only") == 0 && i + 1 < argc) {
            cfg.only_backend = argv[++i];
        } else if (strcmp(argv[i], "--no-aes") == 0) {
            cfg.no_aes = true;
        } else if (strcmp(argv[i], "--no-evp-aes") == 0) {
            cfg.no_evp_aes = true;
        } else if (strcmp(argv[i], "--no-curve") == 0) {
            cfg.no_curve = true;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    if (mach_timebase_info(&g_timebase) != KERN_SUCCESS) {
        fprintf(stderr, "mach_timebase_info failed\n");
        return 2;
    }

    puts("backend,library_path,version,test,message_bytes,seconds_per_rep,reps,"
         "median_mib_s,median_ops_s,median_ns_per_op,median_cpu_pct,"
         "median_maxrss_mib,checksum");

    for (size_t i = 0; i < sizeof(default_backends) / sizeof(default_backends[0]); i++) {
        if (cfg.only_backend != NULL &&
            strcmp(cfg.only_backend, default_backends[i].name) != 0) {
            continue;
        }
        struct crypto_api api;
        load_api(&api, &default_backends[i]);
        if (!cfg.no_aes) {
            if (!cfg.no_evp_aes) {
                run_test(&api, &cfg, "aes256-gcm-encrypt-evp", bench_aes_encrypt_adapter,
                         cfg.aes_message_len);
                run_test(&api, &cfg, "aes256-gcm-decrypt-evp", bench_aes_decrypt_adapter,
                         cfg.aes_message_len);
            }
            if (has_native_aead(&api)) {
                run_test(&api, &cfg, "aes256-gcm-seal-native-aead",
                         bench_aead_seal_adapter, cfg.aes_message_len);
                run_test(&api, &cfg, "aes256-gcm-open-native-aead",
                         bench_aead_open_adapter, cfg.aes_message_len);
            }
        }
        if (!cfg.no_curve) {
            run_test(&api, &cfg, "curve25519-sha256-evp-freshctx", bench_curve_fresh_adapter,
                     X25519_SECRET_LEN);
            run_test(&api, &cfg, "curve25519-sha256-evp-reusedctx", bench_curve_reuse_adapter,
                     X25519_SECRET_LEN);
        }
    }

    return 0;
}

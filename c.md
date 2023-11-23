---
theme: solarized_dark.json
---

# C/C++

- Most recent experience was several years ago, creating a custom module for a third-party C application
- Little experience with C++, but experienced with OO programming in general
- Familiar with:
  - manual memory management
  - pointer math
  - `make` &c
  - debugging running applications and core dumps with `gdb`

---

## `mod_callmgr`: `curlworker`

### Header

```c
#ifndef _MOD_CALLMGR_CURLWORKER_H
#define _MOD_CALLMGR_CURLWORKER_H

#define CURLWORKER_DEFAULT_CONN_MAX 20

struct curlworker;
typedef struct curlworker curlworker_t;

/**
 * cURL completion callback.
 * This is called when a transfer completes, successfully or not.
 *
 * @param   curl_stat   cURL transfer status
 * @param   response    response code from server
 * @param   easy        cURL easy handle of completed transfer
 * @param   private     private data pointer given to curlworker_launch()
 */
typedef void (curlworker_complete_cb)(CURLcode curl_stat, long response_code,
                                      CURL *easy, void *private);

// Additional declarations and documentation…

#endif /* _MOD_CALLMGR_CURLWORKER_H */
```

---

## `mod_callmgr`: `curlworker`

### Setup

```c
#include "mod_callmgr.h"
#include "curlworker.h"


struct curlworker {
    CURLM *mhandle;                     ///< cURL multi handle.
    switch_queue_t *request_queue;      ///< Easy handle queue.
    switch_memory_pool_t *pool;         ///< Memory pool.
    switch_thread_t *thread;            ///< Thread pointer.
    curlworker_complete_cb *complete_cb;///< Transfer completion callback.
    void *private;                      ///< Private data provided by caller.
    uint64_t xfer_bytes_up;             ///< Total bytes uploaded.
    uint64_t xfer_bytes_down;           ///< Total bytes downloaded.
    unsigned int xfer_okay;             ///< Count of successful transfers.
    unsigned int xfer_errs;             ///< Count of failed transfers.
    unsigned int pool_is_mine:1;        ///< Is pool mine or caller's?
    unsigned int stop:1;                ///< Stop flag.
};


static unsigned int connmax = CURLWORKER_DEFAULT_CONN_MAX;
```

---

## `mod_callmgr`: `curlworker`

### Module startup (1/2)

```c
curlworker_t *
curlworker_launch(short queue_size, switch_memory_pool_t *pool_in,
                  void *private, curlworker_complete_cb complete_cb)
{
    curlworker_t            *cw;
    switch_threadattr_t     *thattr;
    switch_memory_pool_t    *pool = pool_in;
    switch_bool_t           pool_is_mine = SWITCH_FALSE;

    if (!pool)
    {
        switch_core_new_memory_pool(&pool);
        pool_is_mine = SWITCH_TRUE;
    }

    cw = (curlworker_t*) switch_core_alloc(pool, sizeof *cw);
    cw->pool = pool;
    cw->pool_is_mine = pool_is_mine;
    switch_queue_create(&cw->request_queue, queue_size, cw->pool);
    cw->stop = SWITCH_FALSE;
    cw->xfer_okay = 0;
    cw->xfer_errs = 0;
    cw->xfer_bytes_up = 0;
    cw->xfer_bytes_down = 0;
    cw->mhandle = curl_multi_init();
    cw->complete_cb = complete_cb;
…
```

---

## `mod_callmgr`: `curlworker`

### Module startup (2/2)

```c
…
#if LIBCURL_VERSION_NUM >= 0x071E00 /* 7.30.0 */
    curl_multi_setopt(cw->mhandle, CURLMOPT_PIPELINING, 1);
    curl_multi_setopt(cw->mhandle, CURLMOPT_MAX_HOST_CONNECTIONS, connmax);
    curl_multi_setopt(cw->mhandle, CURLMOPT_MAX_TOTAL_CONNECTIONS, connmax);
#else /* Disable pipelining to enable parallel requests */
    curl_multi_setopt(cw->mhandle, CURLMOPT_PIPELINING, 0);
    curl_multi_setopt(cw->mhandle, CURLMOPT_MAXCONNECTS, connmax);
#endif

    switch_threadattr_create(&thattr, cw->pool);
    switch_threadattr_stacksize_set(thattr, SWITCH_THREAD_STACKSIZE);
    switch_threadattr_detach_set(thattr, 0);
    switch_thread_create(&cw->thread, thattr, curlworker_thread_run, cw,
                         cw->pool);

    return cw;
}
```

---

## `mod_callmgr`: `curlworker`

### Module shutdown

```c
inline switch_status_t
curlworker_stop(curlworker_t *cw)
{
    switch_status_t thread_ret; // Discarded

    cw->stop = SWITCH_TRUE;

    /* Interrupt blocking queue waits */
    switch_queue_interrupt_all(cw->request_queue);

    return switch_thread_join(&thread_ret, cw->thread);
}
```

---

## `mod_callmgr`: `curlworker`

### Thread worker (1/3)

```c
static void *
curlworker_thread_run(switch_thread_t *thread, void *data)
{
    CURL                    *easy;
    CURLMsg                 *message;
    curlworker_t            *cw = (curlworker_t*) data;
    int                     n_active = 0, n_messages = 0;
    switch_status_t         popstat;
    const int               timeout_ms_max = 500;

    while (n_active || !cw->stop || switch_queue_size(cw->request_queue)) {
        /* Block if nothing is active and we're not stopping */
        if (n_active == 0 && !cw->stop) {
            popstat = switch_queue_pop(cw->request_queue, (void**) &easy);
            if (popstat == SWITCH_STATUS_SUCCESS)
                curl_multi_add_handle(cw->mhandle, easy);
            else // Nothing on queue or interrupted: retry
                continue;
        }

        /* Handle anything else that's queued up */
        while (switch_queue_trypop(cw->request_queue, (void**) &easy)
                == SWITCH_STATUS_SUCCESS)
        {
            curl_multi_add_handle(cw->mhandle, easy);
        }
        /* Wait for something to happen for up to timeout_ms_max */
        curl_multi_wait(cw->mhandle, NULL, 0, timeout_ms_max, NULL);

        /* Handle any pending reads/writes */
        curl_multi_perform(cw->mhandle, &n_active);
…
```

---

## `mod_callmgr`: `curlworker`

### Thread worker (2/3)

```c
…
        while ((message = curl_multi_info_read(cw->mhandle, &n_messages))) {
            /* As of this writing CURLMSG_DONE is the only possible value */
            if (message->msg == CURLMSG_DONE) {
                CURL *rmhandle;
                long http_response;

                curl_easy_getinfo(message->easy_handle, CURLINFO_RESPONSE_CODE,
                                  &http_response);

                if (message->data.result == CURLE_OK && http_response == 200) {
                    double bytes;

                    ++cw->xfer_okay;
                    curl_easy_getinfo(
                        message->easy_handle, CURLINFO_SIZE_UPLOAD, &bytes);
                    cw->xfer_bytes_up += bytes;
                    curl_easy_getinfo(
                        message->easy_handle, CURLINFO_SIZE_DOWNLOAD, &bytes);
                    cw->xfer_bytes_down += bytes;
                } else {
                    char *url;
                    curl_easy_getinfo(message->easy_handle,
                                      CURLINFO_EFFECTIVE_URL, &url);

                    ++cw->xfer_errs;
                    mod_callmgr_log(
                        ERROR,
                        "cURL request failed: status=%ld curl=«%s» url=«%s»\n",
                        http_response, curl_easy_strerror(message->data.result),
                        url);
                }
…
```

---

## `mod_callmgr`: `curlworker`

### Thread worker (3/3)

```c
…
                if (cw->complete_cb) {
                    (*cw->complete_cb)(message->data.result, http_response,
                                       message->easy_handle, cw->private);
                }

                rmhandle = message->easy_handle;
                curl_multi_remove_handle(cw->mhandle, rmhandle);
                curl_easy_cleanup(rmhandle);
            }
        }
    }

    /* Cleanup */
    curl_multi_cleanup(cw->mhandle);
    if (cw->pool_is_mine) {
        switch_core_destroy_memory_pool(&cw->pool);
    }

    return NULL;
}
```

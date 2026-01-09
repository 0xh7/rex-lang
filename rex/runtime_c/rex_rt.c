#include "rex_rt.h"

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <direct.h>
#include <windows.h>
#include <process.h>
#define rex_stat _stat
typedef struct _stat rex_stat_t;
#else
#include <netdb.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#define rex_stat stat
typedef struct stat rex_stat_t;
#endif

typedef struct RexStruct {
  const char* name;
  const char** fields;
  RexValue* values;
  int count;
} RexStruct;

typedef struct RexTuple {
  int count;
  RexValue* items;
} RexTuple;

typedef struct RexResult {
  const char* tag;
  RexValue value;
} RexResult;

typedef struct RexPtr {
  RexValue value;
} RexPtr;

typedef struct RexQueue {
  RexValue* items;
  int count;
  int capacity;
} RexQueue;

typedef struct RexChannel {
  RexQueue queue;
} RexChannel;

typedef struct RexSender {
  RexChannel* channel;
} RexSender;

typedef struct RexReceiver {
  RexChannel* channel;
} RexReceiver;

typedef struct RexVec {
  RexValue* items;
  int count;
  int capacity;
} RexVec;

typedef struct RexMapEntry {
  RexValue key;
  RexValue value;
} RexMapEntry;

typedef struct RexMap {
  RexMapEntry* items;
  int count;
  int capacity;
} RexMap;

typedef struct RexSet {
  RexValue* items;
  int count;
  int capacity;
} RexSet;

typedef struct RexSpawnTask {
  RexSpawnFn fn;
  void* ctx;
} RexSpawnTask;

typedef struct RexThreadNode {
#ifdef _WIN32
  HANDLE handle;
#else
  pthread_t handle;
#endif
  struct RexThreadNode* next;
} RexThreadNode;

static RexThreadNode* rex_threads_head = NULL;
static RexThreadNode* rex_threads_tail = NULL;
#ifdef _WIN32
static CRITICAL_SECTION rex_thread_lock;
static int rex_thread_lock_init = 0;
#else
static pthread_mutex_t rex_thread_lock = PTHREAD_MUTEX_INITIALIZER;
#endif

static RexValue rex_resolve(RexValue v);
static RexValue rex_resolve_mut(RexValue v);

static void* rex_xmalloc(size_t size) {
  void* p = malloc(size);
  if (!p) {
    fprintf(stderr, "Rex runtime: out of memory\n");
    exit(1);
  }
  return p;
}

static char* rex_strdup(const char* s) {
  size_t len = strlen(s);
  char* out = (char*)rex_xmalloc(len + 1);
  memcpy(out, s, len + 1);
  return out;
}

static const char* rex_to_cstr(RexValue v) {
  v = rex_resolve(v);
  static char buffers[4][64];
  static int index = 0;
  char* buf = buffers[index];
  index = (index + 1) % 4;

  if (v.tag == REX_STR) {
    return v.as.str ? v.as.str : "";
  }
  if (v.tag == REX_NUM) {
    snprintf(buf, sizeof(buffers[0]), "%.14g", v.as.num);
    return buf;
  }
  if (v.tag == REX_BOOL) {
    return v.as.boolean ? "true" : "false";
  }
  if (v.tag == REX_NIL) {
    return "nil";
  }
  snprintf(buf, sizeof(buffers[0]), "<value>");
  return buf;
}

typedef struct RexStrBuilder {
  char* data;
  int len;
  int cap;
} RexStrBuilder;

static void sb_init(RexStrBuilder* sb) {
  sb->data = NULL;
  sb->len = 0;
  sb->cap = 0;
}

static void sb_reserve(RexStrBuilder* sb, int extra) {
  int need = sb->len + extra + 1;
  if (need <= sb->cap) {
    return;
  }
  int cap = sb->cap > 0 ? sb->cap : 64;
  while (cap < need) {
    cap *= 2;
  }
  if (sb->data) {
    sb->data = (char*)realloc(sb->data, (size_t)cap);
    if (!sb->data) {
      rex_panic("string realloc failed");
      return;
    }
  } else {
    sb->data = (char*)rex_xmalloc((size_t)cap);
  }
  sb->cap = cap;
}

static void sb_append_bytes(RexStrBuilder* sb, const char* data, int len) {
  if (!data || len <= 0) {
    return;
  }
  sb_reserve(sb, len);
  memcpy(sb->data + sb->len, data, (size_t)len);
  sb->len += len;
  sb->data[sb->len] = '\0';
}

static void sb_append_str(RexStrBuilder* sb, const char* s) {
  if (!s) {
    s = "";
  }
  sb_append_bytes(sb, s, (int)strlen(s));
}

static void sb_append_char(RexStrBuilder* sb, char c) {
  sb_reserve(sb, 1);
  sb->data[sb->len++] = c;
  sb->data[sb->len] = '\0';
}

static void sb_free(RexStrBuilder* sb) {
  free(sb->data);
  sb->data = NULL;
  sb->len = 0;
  sb->cap = 0;
}

#ifdef _WIN32
static int rex_console_ready = 0;
static void rex_console_init(void) {
  if (!rex_console_ready) {
    SetConsoleOutputCP(CP_UTF8);
    rex_console_ready = 1;
  }
}
#else
static void rex_console_init(void) { }
#endif

static void rex_thread_lock_init_once(void) {
#ifdef _WIN32
  if (!rex_thread_lock_init) {
    InitializeCriticalSection(&rex_thread_lock);
    rex_thread_lock_init = 1;
  }
#endif
}

static void rex_thread_lock_enter(void) {
  rex_thread_lock_init_once();
#ifdef _WIN32
  EnterCriticalSection(&rex_thread_lock);
#else
  pthread_mutex_lock(&rex_thread_lock);
#endif
}

static void rex_thread_lock_leave(void) {
#ifdef _WIN32
  LeaveCriticalSection(&rex_thread_lock);
#else
  pthread_mutex_unlock(&rex_thread_lock);
#endif
}

static void rex_thread_add(
#ifdef _WIN32
  HANDLE handle
#else
  pthread_t handle
#endif
) {
  RexThreadNode* node = (RexThreadNode*)rex_xmalloc(sizeof(RexThreadNode));
  node->handle = handle;
  node->next = NULL;
  rex_thread_lock_enter();
  if (rex_threads_tail) {
    rex_threads_tail->next = node;
  } else {
    rex_threads_head = node;
  }
  rex_threads_tail = node;
  rex_thread_lock_leave();
}

#ifdef _WIN32
static unsigned __stdcall rex_thread_entry(void* arg) {
  RexSpawnTask* task = (RexSpawnTask*)arg;
  if (task && task->fn) {
    task->fn(task->ctx);
  }
  free(task);
  return 0;
}
#else
static void* rex_thread_entry(void* arg) {
  RexSpawnTask* task = (RexSpawnTask*)arg;
  if (task && task->fn) {
    task->fn(task->ctx);
  }
  free(task);
  return NULL;
}
#endif

static uint64_t rex_rand_state = 0;

static uint64_t rex_seed_from_time(void) {
#ifdef _WIN32
  return (uint64_t)GetTickCount64();
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_nsec ^ (uint64_t)ts.tv_sec;
#endif
}

static uint64_t rex_rand_next(void) {
  if (rex_rand_state == 0) {
    rex_rand_state = rex_seed_from_time();
  }
  rex_rand_state = rex_rand_state * 6364136223846793005ULL + 1ULL;
  return rex_rand_state;
}

static void rex_rand_seed_u64(uint64_t seed) {
  if (seed == 0) {
    seed = 1;
  }
  rex_rand_state = seed;
}


void rex_panic(const char* msg) {
  fprintf(stderr, "Rex panic: %s\n", msg);
  exit(1);
}

RexValue rex_nil(void) {
  RexValue v;
  v.tag = REX_NIL;
  v.as.ptr = NULL;
  return v;
}

RexValue rex_num(double n) {
  RexValue v;
  v.tag = REX_NUM;
  v.as.num = n;
  return v;
}

RexValue rex_bool(int b) {
  RexValue v;
  v.tag = REX_BOOL;
  v.as.boolean = b ? 1 : 0;
  return v;
}

RexValue rex_str(const char* s) {
  RexValue v;
  v.tag = REX_STR;
  v.as.str = rex_strdup(s ? s : "");
  return v;
}

RexValue rex_ptr(void* p) {
  RexValue v;
  v.tag = REX_PTR;
  v.as.ptr = p;
  return v;
}

RexValue rex_ref(RexValue* v) {
  RexValue out;
  out.tag = REX_REF;
  out.as.ptr = v;
  return out;
}

RexValue rex_ref_mut(RexValue* v) {
  RexValue out;
  out.tag = REX_REF_MUT;
  out.as.ptr = v;
  return out;
}

static RexValue rex_resolve(RexValue v) {
  while (v.tag == REX_REF || v.tag == REX_REF_MUT) {
    if (!v.as.ptr) {
      return rex_nil();
    }
    v = *(RexValue*)v.as.ptr;
  }
  return v;
}

static RexValue rex_resolve_mut(RexValue v) {
  int saw_imm = 0;
  while (v.tag == REX_REF || v.tag == REX_REF_MUT) {
    if (v.tag == REX_REF) {
      saw_imm = 1;
    }
    if (!v.as.ptr) {
      return rex_nil();
    }
    v = *(RexValue*)v.as.ptr;
  }
  if (saw_imm) {
    rex_panic("mutable borrow required");
    return rex_nil();
  }
  return v;
}

void rex_drop(RexValue v) {
  if (v.tag == REX_REF || v.tag == REX_REF_MUT) {
    return;
  }
  if (v.tag == REX_STR) {
    free((void*)v.as.str);
    return;
  }
  if (v.tag == REX_PTR) {
    free(v.as.ptr);
    return;
  }
  if (v.tag == REX_STRUCT && v.as.ptr) {
    RexStruct* s = (RexStruct*)v.as.ptr;
    free(s->values);
    free(s);
    return;
  }
  if (v.tag == REX_TUPLE && v.as.ptr) {
    RexTuple* t = (RexTuple*)v.as.ptr;
    free(t->items);
    free(t);
    return;
  }
  if (v.tag == REX_RESULT && v.as.ptr) {
    free(v.as.ptr);
    return;
  }
  if (v.tag == REX_VEC && v.as.ptr) {
    RexVec* vec = (RexVec*)v.as.ptr;
    free(vec->items);
    free(vec);
    return;
  }
  if (v.tag == REX_MAP && v.as.ptr) {
    RexMap* map = (RexMap*)v.as.ptr;
    free(map->items);
    free(map);
    return;
  }
  if (v.tag == REX_SET && v.as.ptr) {
    RexSet* set = (RexSet*)v.as.ptr;
    free(set->items);
    free(set);
    return;
  }
}

int rex_is_truthy(RexValue v) {
  v = rex_resolve(v);
  if (v.tag == REX_NIL) {
    return 0;
  }
  if (v.tag == REX_BOOL) {
    return v.as.boolean != 0;
  }
  if (v.tag == REX_NUM) {
    return v.as.num != 0.0;
  }
  if (v.tag == REX_STR) {
    return v.as.str && v.as.str[0] != '\0';
  }
  return 1;
}

RexValue rex_add(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_num(a.as.num + b.as.num);
  }
  {
    const char* sa = rex_to_cstr(a);
    const char* sb = rex_to_cstr(b);
    size_t len = strlen(sa) + strlen(sb);
    char* out = (char*)rex_xmalloc(len + 1);
    memcpy(out, sa, strlen(sa));
    memcpy(out + strlen(sa), sb, strlen(sb) + 1);
    RexValue v;
    v.tag = REX_STR;
    v.as.str = out;
    return v;
  }
}

RexValue rex_sub(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_num(a.as.num - b.as.num);
  }
  rex_panic("sub expects numbers");
  return rex_nil();
}

RexValue rex_mul(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_num(a.as.num * b.as.num);
  }
  rex_panic("mul expects numbers");
  return rex_nil();
}

RexValue rex_div(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_num(a.as.num / b.as.num);
  }
  rex_panic("div expects numbers");
  return rex_nil();
}

RexValue rex_mod(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_num(fmod(a.as.num, b.as.num));
  }
  rex_panic("mod expects numbers");
  return rex_nil();
}

RexValue rex_eq(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag != b.tag) {
    return rex_bool(0);
  }
  if (a.tag == REX_NUM) {
    return rex_bool(a.as.num == b.as.num);
  }
  if (a.tag == REX_BOOL) {
    return rex_bool(a.as.boolean == b.as.boolean);
  }
  if (a.tag == REX_STR) {
    return rex_bool(strcmp(a.as.str ? a.as.str : "", b.as.str ? b.as.str : "") == 0);
  }
  return rex_bool(a.as.ptr == b.as.ptr);
}

static int rex_value_eq(RexValue a, RexValue b) {
  RexValue eq = rex_eq(a, b);
  return eq.tag == REX_BOOL && eq.as.boolean != 0;
}

RexValue rex_neq(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  RexValue eq = rex_eq(a, b);
  return rex_bool(!eq.as.boolean);
}

RexValue rex_lt(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_bool(a.as.num < b.as.num);
  }
  rex_panic("lt expects numbers");
  return rex_nil();
}

RexValue rex_lte(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_bool(a.as.num <= b.as.num);
  }
  rex_panic("lte expects numbers");
  return rex_nil();
}

RexValue rex_gt(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_bool(a.as.num > b.as.num);
  }
  rex_panic("gt expects numbers");
  return rex_nil();
}

RexValue rex_gte(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    return rex_bool(a.as.num >= b.as.num);
  }
  rex_panic("gte expects numbers");
  return rex_nil();
}

RexValue rex_neg(RexValue v) {
  v = rex_resolve(v);
  if (v.tag == REX_NUM) {
    return rex_num(-v.as.num);
  }
  rex_panic("neg expects number");
  return rex_nil();
}

RexValue rex_not(RexValue v) {
  v = rex_resolve(v);
  return rex_bool(!rex_is_truthy(v));
}

RexValue rex_and(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  return rex_bool(rex_is_truthy(a) && rex_is_truthy(b));
}

RexValue rex_or(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  return rex_bool(rex_is_truthy(a) || rex_is_truthy(b));
}

void rex_println(RexValue v) {
  rex_console_init();
  const char* s = rex_to_cstr(v);
  printf("%s\n", s);
}

void rex_print(RexValue v) {
  rex_console_init();
  const char* s = rex_to_cstr(v);
  printf("%s", s);
}

RexValue rex_tag(const char* tag, RexValue v) {
  v = rex_resolve(v);
  RexResult* r = (RexResult*)rex_xmalloc(sizeof(RexResult));
  r->tag = tag;
  r->value = v;
  RexValue out;
  out.tag = REX_RESULT;
  out.as.ptr = r;
  return out;
}

int rex_tag_is(RexValue v, const char* tag) {
  v = rex_resolve(v);
  if (v.tag != REX_RESULT || !v.as.ptr) {
    return 0;
  }
  RexResult* r = (RexResult*)v.as.ptr;
  return strcmp(r->tag, tag) == 0;
}

RexValue rex_tag_value(RexValue v) {
  v = rex_resolve(v);
  if (v.tag != REX_RESULT || !v.as.ptr) {
    rex_panic("tag_value expects tagged value");
    return rex_nil();
  }
  RexResult* r = (RexResult*)v.as.ptr;
  return r->value;
}

RexValue rex_ok(RexValue v) {
  return rex_tag("Ok", v);
}

RexValue rex_err(RexValue v) {
  return rex_tag("Err", v);
}

int rex_result_is(RexValue v, const char* tag) {
  return rex_tag_is(v, tag);
}

RexValue rex_result_value(RexValue v) {
  return rex_tag_value(v);
}

RexValue rex_try(RexValue v) {
  v = rex_resolve(v);
  if (v.tag != REX_RESULT || !v.as.ptr) {
    return v;
  }
  RexResult* r = (RexResult*)v.as.ptr;
  if (strcmp(r->tag, "Ok") == 0) {
    return r->value;
  }
  if (strcmp(r->tag, "Err") == 0) {
    return v;
  }
  return v;
}

RexValue rex_alloc(void) {
  RexPtr* p = (RexPtr*)rex_xmalloc(sizeof(RexPtr));
  p->value = rex_nil();
  RexValue v;
  v.tag = REX_PTR;
  v.as.ptr = p;
  return v;
}

void rex_free(RexValue p) {
  p = rex_resolve(p);
  if (p.tag == REX_PTR && p.as.ptr) {
    free(p.as.ptr);
  }
}

RexValue rex_box(RexValue v) {
  RexPtr* p = (RexPtr*)rex_xmalloc(sizeof(RexPtr));
  p->value = v;
  RexValue out;
  out.tag = REX_PTR;
  out.as.ptr = p;
  return out;
}

RexValue rex_unbox(RexValue p) {
  p = rex_resolve(p);
  if (p.tag != REX_PTR || !p.as.ptr) {
    rex_panic("unbox expects pointer");
    return rex_nil();
  }
  RexPtr* ptr = (RexPtr*)p.as.ptr;
  return ptr->value;
}

RexValue rex_deref(RexValue p) {
  if (p.tag == REX_REF || p.tag == REX_REF_MUT) {
    return rex_resolve(p);
  }
  return rex_unbox(p);
}

void rex_deref_assign(RexValue p, RexValue v) {
  if (p.tag == REX_REF_MUT && p.as.ptr) {
    *(RexValue*)p.as.ptr = v;
    return;
  }
  if (p.tag == REX_REF) {
    rex_panic("deref assign expects mutable reference");
    return;
  }
  p = rex_resolve(p);
  if (p.tag != REX_PTR || !p.as.ptr) {
    rex_panic("deref assign expects pointer");
    return;
  }
  RexPtr* ptr = (RexPtr*)p.as.ptr;
  ptr->value = v;
}

RexValue rex_struct_new(const char* name, const char** fields, RexValue* values, int count) {
  RexStruct* s = (RexStruct*)rex_xmalloc(sizeof(RexStruct));
  s->name = name;
  s->fields = fields;
  s->count = count;
  s->values = (RexValue*)rex_xmalloc(sizeof(RexValue) * (size_t)count);
  for (int i = 0; i < count; i++) {
    s->values[i] = values[i];
  }
  RexValue v;
  v.tag = REX_STRUCT;
  v.as.ptr = s;
  return v;
}

RexValue rex_struct_get(RexValue obj, const char* field) {
  obj = rex_resolve(obj);
  if (obj.tag != REX_STRUCT || !obj.as.ptr) {
    rex_panic("struct_get expects struct");
    return rex_nil();
  }
  RexStruct* s = (RexStruct*)obj.as.ptr;
  for (int i = 0; i < s->count; i++) {
    if (strcmp(s->fields[i], field) == 0) {
      return s->values[i];
    }
  }
  return rex_nil();
}

void rex_struct_set(RexValue obj, const char* field, RexValue value) {
  obj = rex_resolve_mut(obj);
  if (obj.tag != REX_STRUCT || !obj.as.ptr) {
    rex_panic("struct_set expects struct");
    return;
  }
  RexStruct* s = (RexStruct*)obj.as.ptr;
  for (int i = 0; i < s->count; i++) {
    if (strcmp(s->fields[i], field) == 0) {
      s->values[i] = value;
      return;
    }
  }
}

RexValue rex_tuple_new(int count, RexValue* values) {
  RexTuple* t = (RexTuple*)rex_xmalloc(sizeof(RexTuple));
  t->count = count;
  t->items = (RexValue*)rex_xmalloc(sizeof(RexValue) * (size_t)count);
  for (int i = 0; i < count; i++) {
    t->items[i] = values[i];
  }
  RexValue v;
  v.tag = REX_TUPLE;
  v.as.ptr = t;
  return v;
}

RexValue rex_tuple_get(RexValue tuple, int index) {
  tuple = rex_resolve(tuple);
  if (tuple.tag != REX_TUPLE || !tuple.as.ptr) {
    rex_panic("tuple_get expects tuple");
    return rex_nil();
  }
  RexTuple* t = (RexTuple*)tuple.as.ptr;
  if (index < 0 || index >= t->count) {
    rex_panic("tuple index out of range");
    return rex_nil();
  }
  return t->items[index];
}

static void queue_push(RexQueue* q, RexValue v) {
  if (q->capacity == 0) {
    q->capacity = 4;
    q->items = (RexValue*)rex_xmalloc(sizeof(RexValue) * (size_t)q->capacity);
  } else if (q->count >= q->capacity) {
    q->capacity *= 2;
    q->items = (RexValue*)realloc(q->items, sizeof(RexValue) * (size_t)q->capacity);
    if (!q->items) {
      rex_panic("queue realloc failed");
    }
  }
  q->items[q->count++] = v;
}

static RexValue queue_pop(RexQueue* q) {
  if (q->count == 0) {
    rex_panic("channel is empty");
    return rex_nil();
  }
  RexValue v = q->items[0];
  for (int i = 1; i < q->count; i++) {
    q->items[i - 1] = q->items[i];
  }
  q->count -= 1;
  return v;
}

RexValue rex_channel(void) {
  RexChannel* c = (RexChannel*)rex_xmalloc(sizeof(RexChannel));
  c->queue.items = NULL;
  c->queue.count = 0;
  c->queue.capacity = 0;
  RexSender* s = (RexSender*)rex_xmalloc(sizeof(RexSender));
  RexReceiver* r = (RexReceiver*)rex_xmalloc(sizeof(RexReceiver));
  s->channel = c;
  r->channel = c;
  RexValue sender;
  RexValue receiver;
  sender.tag = REX_SENDER;
  sender.as.ptr = s;
  receiver.tag = REX_RECEIVER;
  receiver.as.ptr = r;
  RexValue values[2];
  values[0] = sender;
  values[1] = receiver;
  return rex_tuple_new(2, values);
}

void rex_sender_send(RexValue sender, RexValue value) {
  sender = rex_resolve(sender);
  if (sender.tag != REX_SENDER || !sender.as.ptr) {
    rex_panic("send expects sender");
    return;
  }
  RexSender* s = (RexSender*)sender.as.ptr;
  queue_push(&s->channel->queue, value);
}

RexValue rex_receiver_recv(RexValue receiver) {
  receiver = rex_resolve(receiver);
  if (receiver.tag != REX_RECEIVER || !receiver.as.ptr) {
    rex_panic("recv expects receiver");
    return rex_nil();
  }
  RexReceiver* r = (RexReceiver*)receiver.as.ptr;
  return queue_pop(&r->channel->queue);
}

RexValue rex_spawn(RexSpawnFn fn, void* ctx) {
  if (!fn) {
    rex_panic("spawn expects function");
    return rex_nil();
  }
  RexSpawnTask* task = (RexSpawnTask*)rex_xmalloc(sizeof(RexSpawnTask));
  task->fn = fn;
  task->ctx = ctx;
#ifdef _WIN32
  uintptr_t handle = _beginthreadex(NULL, 0, rex_thread_entry, task, 0, NULL);
  if (handle == 0) {
    free(task);
    rex_panic("spawn failed");
    return rex_nil();
  }
  rex_thread_add((HANDLE)handle);
#else
  pthread_t thread;
  if (pthread_create(&thread, NULL, rex_thread_entry, task) != 0) {
    free(task);
    rex_panic("spawn failed");
    return rex_nil();
  }
  rex_thread_add(thread);
#endif
  return rex_nil();
}

RexValue rex_wait_all(void) {
  rex_thread_lock_enter();
  RexThreadNode* node = rex_threads_head;
  rex_threads_head = NULL;
  rex_threads_tail = NULL;
  rex_thread_lock_leave();
  while (node) {
    RexThreadNode* next = node->next;
#ifdef _WIN32
    WaitForSingleObject(node->handle, INFINITE);
    CloseHandle(node->handle);
#else
    pthread_join(node->handle, NULL);
#endif
    free(node);
    node = next;
  }
  return rex_nil();
}

RexValue rex_sleep(RexValue ms) {
  ms = rex_resolve(ms);
  if (ms.tag != REX_NUM) {
    rex_panic("sleep expects number");
    return rex_nil();
  }
  int m = (int)ms.as.num;
#ifdef _WIN32
  Sleep((DWORD)m);
#else
  usleep((useconds_t)(m * 1000));
#endif
  return rex_nil();
}

RexValue rex_sleep_s(RexValue seconds) {
  seconds = rex_resolve(seconds);
  if (seconds.tag != REX_NUM) {
    rex_panic("sleep_s expects number");
    return rex_nil();
  }
  double ms = seconds.as.num * 1000.0;
  return rex_sleep(rex_num(ms));
}

RexValue rex_now_ms(void) {
#ifdef _WIN32
  return rex_num((double)GetTickCount64());
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return rex_num((double)(ts.tv_sec * 1000.0 + ts.tv_nsec / 1000000.0));
#endif
}

RexValue rex_now_s(void) {
  RexValue ms = rex_now_ms();
  return rex_num(ms.as.num / 1000.0);
}

RexValue rex_now_ns(void) {
#ifdef _WIN32
  LARGE_INTEGER freq;
  LARGE_INTEGER counter;
  if (!QueryPerformanceFrequency(&freq) || !QueryPerformanceCounter(&counter) || freq.QuadPart == 0) {
    return rex_num(rex_now_ms().as.num * 1000000.0);
  }
  double ns = (double)counter.QuadPart * 1000000000.0 / (double)freq.QuadPart;
  return rex_num(ns);
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return rex_num((double)ts.tv_sec * 1000000000.0 + (double)ts.tv_nsec);
#endif
}

RexValue rex_time_since(RexValue start) {
  start = rex_resolve(start);
  if (start.tag != REX_NUM) {
    rex_panic("time.since expects number");
    return rex_num(0);
  }
  RexValue now = rex_now_ms();
  return rex_num(now.as.num - start.as.num);
}

RexValue rex_format(RexValue v) {
  v = rex_resolve(v);
  return rex_str(rex_to_cstr(v));
}

RexValue rex_sqrt(RexValue v) {
  v = rex_resolve(v);
  if (v.tag != REX_NUM) {
    rex_panic("sqrt expects number");
    return rex_nil();
  }
  return rex_num(sqrt(v.as.num));
}

RexValue rex_abs(RexValue v) {
  v = rex_resolve(v);
  if (v.tag != REX_NUM) {
    rex_panic("abs expects number");
    return rex_nil();
  }
  return rex_num(fabs(v.as.num));
}

RexValue rex_random_seed(RexValue seed) {
  seed = rex_resolve(seed);
  if (seed.tag != REX_NUM) {
    rex_panic("random.seed expects number");
    return rex_nil();
  }
  uint64_t s = (uint64_t)seed.as.num;
  rex_rand_seed_u64(s);
  return rex_nil();
}

RexValue rex_random_int(RexValue min, RexValue max) {
  min = rex_resolve(min);
  max = rex_resolve(max);
  if (min.tag != REX_NUM || max.tag != REX_NUM) {
    rex_panic("random.int expects numbers");
    return rex_num(0);
  }
  int64_t lo = (int64_t)min.as.num;
  int64_t hi = (int64_t)max.as.num;
  if (hi < lo) {
    int64_t tmp = lo;
    lo = hi;
    hi = tmp;
  }
  uint64_t range = (uint64_t)(hi - lo) + 1ULL;
  uint64_t r = rex_rand_next();
  int64_t out = lo;
  if (range > 0) {
    out = lo + (int64_t)(r % range);
  }
  return rex_num((double)out);
}

RexValue rex_random_float(void) {
  uint64_t r = rex_rand_next();
  double out = (double)(r >> 11) * (1.0 / 9007199254740992.0);
  return rex_num(out);
}

RexValue rex_random_bool(RexValue probability) {
  probability = rex_resolve(probability);
  if (probability.tag != REX_NUM) {
    rex_panic("random.bool expects number");
    return rex_bool(0);
  }
  double p = probability.as.num;
  if (p <= 0.0) {
    return rex_bool(0);
  }
  if (p >= 1.0) {
    return rex_bool(1);
  }
  return rex_bool(rex_random_float().as.num < p);
}

RexValue rex_random_choice(RexValue vec) {
  vec = rex_resolve(vec);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("random.choice expects vector");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  if (v->count <= 0) {
    return rex_nil();
  }
  uint64_t r = rex_rand_next();
  int idx = (int)(r % (uint64_t)v->count);
  return v->items[idx];
}

RexValue rex_random_shuffle(RexValue vec) {
  vec = rex_resolve_mut(vec);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("random.shuffle expects vector");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  for (int i = v->count - 1; i > 0; i--) {
    uint64_t r = rex_rand_next();
    int j = (int)(r % (uint64_t)(i + 1));
    RexValue tmp = v->items[i];
    v->items[i] = v->items[j];
    v->items[j] = tmp;
  }
  return vec;
}

RexValue rex_random_range(RexValue min, RexValue max) {
  min = rex_resolve(min);
  max = rex_resolve(max);
  if (min.tag != REX_NUM || max.tag != REX_NUM) {
    rex_panic("random.range expects numbers");
    return rex_num(0);
  }
  double lo = min.as.num;
  double hi = max.as.num;
  if (hi < lo) {
    double tmp = lo;
    lo = hi;
    hi = tmp;
  }
  double r = rex_random_float().as.num;
  return rex_num(lo + (hi - lo) * r);
}

RexValue rex_io_read_file(RexValue path) {
  path = rex_resolve(path);
  if (path.tag != REX_STR) {
    rex_panic("read_file expects string path");
    return rex_err(rex_str("bad path"));
  }
  FILE* f = fopen(path.as.str, "rb");
  if (!f) {
    return rex_err(rex_str(strerror(errno)));
  }
  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    return rex_err(rex_str("fseek failed"));
  }
  long size = ftell(f);
  if (size < 0) {
    fclose(f);
    return rex_err(rex_str("ftell failed"));
  }
  if (fseek(f, 0, SEEK_SET) != 0) {
    fclose(f);
    return rex_err(rex_str("fseek failed"));
  }
  char* buf = (char*)rex_xmalloc((size_t)size + 1);
  size_t read = fread(buf, 1, (size_t)size, f);
  buf[read] = '\0';
  fclose(f);
  RexValue out = rex_ok(rex_str(buf));
  free(buf);
  return out;
}

RexValue rex_io_write_file(RexValue path, RexValue data) {
  path = rex_resolve(path);
  data = rex_resolve(data);
  if (path.tag != REX_STR) {
    rex_panic("write_file expects string path");
    return rex_err(rex_str("bad path"));
  }
  const char* content = rex_to_cstr(data);
  FILE* f = fopen(path.as.str, "wb");
  if (!f) {
    return rex_err(rex_str(strerror(errno)));
  }
  size_t len = strlen(content);
  size_t written = fwrite(content, 1, len, f);
  fclose(f);
  if (written != len) {
    return rex_err(rex_str("write failed"));
  }
  return rex_ok(rex_bool(1));
}

RexValue rex_io_read_line(void) {
  char buf[1024];
  if (!fgets(buf, sizeof(buf), stdin)) {
    return rex_err(rex_str("eof"));
  }
  size_t len = strlen(buf);
  if (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) {
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) {
      buf[len - 1] = '\0';
      len -= 1;
    }
  }
  return rex_ok(rex_str(buf));
}

RexValue rex_io_read_lines(RexValue path) {
  path = rex_resolve(path);
  if (path.tag != REX_STR) {
    rex_panic("read_lines expects string path");
    return rex_err(rex_str("bad path"));
  }
  FILE* f = fopen(path.as.str, "rb");
  if (!f) {
    return rex_err(rex_str(strerror(errno)));
  }
  RexValue lines = rex_collections_vec_new();
  RexStrBuilder sb;
  sb_init(&sb);
  int ch = 0;
  while ((ch = fgetc(f)) != EOF) {
    if (ch == '\r') {
      continue;
    }
    if (ch == '\n') {
      RexValue line = rex_str(sb.data ? sb.data : "");
      rex_collections_vec_push(lines, line);
      sb.len = 0;
      if (sb.data) {
        sb.data[0] = '\0';
      }
      continue;
    }
    sb_append_char(&sb, (char)ch);
  }
  if (sb.len > 0) {
    RexValue line = rex_str(sb.data ? sb.data : "");
    rex_collections_vec_push(lines, line);
  }
  fclose(f);
  sb_free(&sb);
  return rex_ok(lines);
}

RexValue rex_io_write_lines(RexValue path, RexValue lines) {
  path = rex_resolve(path);
  lines = rex_resolve(lines);
  if (path.tag != REX_STR) {
    rex_panic("write_lines expects string path");
    return rex_err(rex_str("bad path"));
  }
  if (lines.tag != REX_VEC || !lines.as.ptr) {
    rex_panic("write_lines expects vector");
    return rex_err(rex_str("bad lines"));
  }
  FILE* f = fopen(path.as.str, "wb");
  if (!f) {
    return rex_err(rex_str(strerror(errno)));
  }
  RexVec* v = (RexVec*)lines.as.ptr;
  for (int i = 0; i < v->count; i++) {
    const char* text = rex_to_cstr(v->items[i]);
    size_t len = strlen(text);
    if (len > 0 && fwrite(text, 1, len, f) != len) {
      fclose(f);
      return rex_err(rex_str("write failed"));
    }
    if (fputc('\n', f) == EOF) {
      fclose(f);
      return rex_err(rex_str("write failed"));
    }
  }
  fclose(f);
  return rex_ok(rex_bool(1));
}

RexValue rex_fs_exists(RexValue path) {
  path = rex_resolve(path);
  if (path.tag != REX_STR) {
    rex_panic("fs_exists expects string path");
    return rex_bool(0);
  }
  rex_stat_t st;
  int rc = rex_stat(path.as.str, &st);
  return rex_bool(rc == 0);
}

RexValue rex_fs_mkdir(RexValue path) {
  path = rex_resolve(path);
  if (path.tag != REX_STR) {
    rex_panic("fs_mkdir expects string path");
    return rex_err(rex_str("bad path"));
  }
#ifdef _WIN32
  int rc = _mkdir(path.as.str);
#else
  int rc = mkdir(path.as.str, 0755);
#endif
  if (rc == 0 || errno == EEXIST) {
    return rex_ok(rex_bool(1));
  }
  return rex_err(rex_str(strerror(errno)));
}

RexValue rex_fs_remove(RexValue path) {
  path = rex_resolve(path);
  if (path.tag != REX_STR) {
    rex_panic("fs_remove expects string path");
    return rex_err(rex_str("bad path"));
  }
  if (remove(path.as.str) == 0) {
    return rex_ok(rex_bool(1));
  }
  return rex_err(rex_str(strerror(errno)));
}

RexValue rex_os_getenv(RexValue key) {
  key = rex_resolve(key);
  if (key.tag != REX_STR) {
    rex_panic("getenv expects string key");
    return rex_nil();
  }
  const char* val = getenv(key.as.str);
  if (!val) {
    return rex_nil();
  }
  return rex_str(val);
}

RexValue rex_os_cwd(void) {
  char buf[1024];
#ifdef _WIN32
  if (!_getcwd(buf, sizeof(buf))) {
    return rex_nil();
  }
#else
  if (!getcwd(buf, sizeof(buf))) {
    return rex_nil();
  }
#endif
  return rex_str(buf);
}

static void vec_grow(RexVec* v) {
  if (v->capacity == 0) {
    v->capacity = 4;
    v->items = (RexValue*)rex_xmalloc(sizeof(RexValue) * (size_t)v->capacity);
  } else if (v->count >= v->capacity) {
    v->capacity *= 2;
    v->items = (RexValue*)realloc(v->items, sizeof(RexValue) * (size_t)v->capacity);
    if (!v->items) {
      rex_panic("vector realloc failed");
    }
  }
}

RexValue rex_collections_vec_new(void) {
  RexVec* v = (RexVec*)rex_xmalloc(sizeof(RexVec));
  v->items = NULL;
  v->count = 0;
  v->capacity = 0;
  RexValue out;
  out.tag = REX_VEC;
  out.as.ptr = v;
  return out;
}

void rex_collections_vec_push(RexValue vec, RexValue value) {
  vec = rex_resolve_mut(vec);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_push expects vector");
    return;
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  vec_grow(v);
  v->items[v->count++] = value;
}

RexValue rex_collections_vec_get(RexValue vec, RexValue index) {
  vec = rex_resolve(vec);
  index = rex_resolve(index);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_get expects vector");
    return rex_nil();
  }
  if (index.tag != REX_NUM) {
    rex_panic("vec_get expects numeric index");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  int idx = (int)index.as.num;
  if (idx < 0 || idx >= v->count) {
    rex_panic("vec index out of range");
    return rex_nil();
  }
  return v->items[idx];
}

void rex_collections_vec_set(RexValue vec, RexValue index, RexValue value) {
  vec = rex_resolve_mut(vec);
  index = rex_resolve(index);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_set expects vector");
    return;
  }
  if (index.tag != REX_NUM) {
    rex_panic("vec_set expects numeric index");
    return;
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  int idx = (int)index.as.num;
  if (idx < 0 || idx >= v->count) {
    rex_panic("vec index out of range");
    return;
  }
  v->items[idx] = value;
}

RexValue rex_collections_vec_len(RexValue vec) {
  vec = rex_resolve(vec);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_len expects vector");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  return rex_num((double)v->count);
}

RexValue rex_collections_vec_insert(RexValue vec, RexValue index, RexValue value) {
  vec = rex_resolve_mut(vec);
  index = rex_resolve(index);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_insert expects vector");
    return rex_nil();
  }
  if (index.tag != REX_NUM) {
    rex_panic("vec_insert expects numeric index");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  int idx = (int)index.as.num;
  if (idx < 0) {
    idx = 0;
  }
  if (idx > v->count) {
    idx = v->count;
  }
  vec_grow(v);
  if (idx < v->count) {
    memmove(&v->items[idx + 1], &v->items[idx], sizeof(RexValue) * (size_t)(v->count - idx));
  }
  v->items[idx] = value;
  v->count += 1;
  return rex_nil();
}

RexValue rex_collections_vec_pop(RexValue vec) {
  vec = rex_resolve_mut(vec);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_pop expects vector");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  if (v->count <= 0) {
    return rex_nil();
  }
  v->count -= 1;
  return v->items[v->count];
}

RexValue rex_collections_vec_clear(RexValue vec) {
  vec = rex_resolve_mut(vec);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_clear expects vector");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  v->count = 0;
  return rex_nil();
}

static int rex_value_cmp(RexValue a, RexValue b) {
  a = rex_resolve(a);
  b = rex_resolve(b);
  if (a.tag == REX_NIL && b.tag == REX_NIL) {
    return 0;
  }
  if (a.tag == REX_NIL) {
    return -1;
  }
  if (b.tag == REX_NIL) {
    return 1;
  }
  if (a.tag == REX_NUM && b.tag == REX_NUM) {
    if (a.as.num < b.as.num) {
      return -1;
    }
    if (a.as.num > b.as.num) {
      return 1;
    }
    return 0;
  }
  if (a.tag == REX_STR && b.tag == REX_STR) {
    const char* sa = a.as.str ? a.as.str : "";
    const char* sb = b.as.str ? b.as.str : "";
    int cmp = strcmp(sa, sb);
    if (cmp < 0) {
      return -1;
    }
    if (cmp > 0) {
      return 1;
    }
    return 0;
  }
  if (a.tag == REX_BOOL && b.tag == REX_BOOL) {
    if (a.as.boolean == b.as.boolean) {
      return 0;
    }
    return a.as.boolean ? 1 : -1;
  }
  if (a.tag != b.tag) {
    return (int)a.tag - (int)b.tag;
  }
  if (a.as.ptr == b.as.ptr) {
    return 0;
  }
  return (a.as.ptr < b.as.ptr) ? -1 : 1;
}

static int rex_value_cmp_qsort(const void* a, const void* b) {
  RexValue va = *(const RexValue*)a;
  RexValue vb = *(const RexValue*)b;
  return rex_value_cmp(va, vb);
}

RexValue rex_collections_vec_sort(RexValue vec) {
  vec = rex_resolve_mut(vec);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_sort expects vector");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  if (v->count > 1) {
    qsort(v->items, (size_t)v->count, sizeof(RexValue), rex_value_cmp_qsort);
  }
  return vec;
}

RexValue rex_collections_vec_slice(RexValue vec, RexValue start, RexValue finish) {
  vec = rex_resolve(vec);
  start = rex_resolve(start);
  finish = rex_resolve(finish);
  if (vec.tag != REX_VEC || !vec.as.ptr) {
    rex_panic("vec_slice expects vector");
    return rex_nil();
  }
  if (start.tag != REX_NUM) {
    rex_panic("vec_slice expects numeric start");
    return rex_nil();
  }
  RexVec* v = (RexVec*)vec.as.ptr;
  int s = (int)start.as.num;
  int e = v->count;
  if (finish.tag != REX_NIL) {
    if (finish.tag != REX_NUM) {
      rex_panic("vec_slice expects numeric end");
      return rex_nil();
    }
    e = (int)finish.as.num;
  }
  if (s < 0) {
    s = 0;
  }
  if (e < s) {
    e = s;
  }
  if (e > v->count) {
    e = v->count;
  }
  RexVec* out = (RexVec*)rex_xmalloc(sizeof(RexVec));
  out->count = e - s;
  out->capacity = out->count;
  if (out->count == 0) {
    out->items = NULL;
  } else {
    out->items = (RexValue*)rex_xmalloc(sizeof(RexValue) * (size_t)out->count);
    for (int i = 0; i < out->count; i++) {
      out->items[i] = v->items[s + i];
    }
  }
  RexValue outv;
  outv.tag = REX_VEC;
  outv.as.ptr = out;
  return outv;
}

RexValue rex_collections_vec_from(int count, RexValue* values) {
  RexVec* v = (RexVec*)rex_xmalloc(sizeof(RexVec));
  v->count = count;
  v->capacity = count;
  if (count == 0) {
    v->items = NULL;
  } else {
    v->items = (RexValue*)rex_xmalloc(sizeof(RexValue) * (size_t)count);
    for (int i = 0; i < count; i++) {
      v->items[i] = values[i];
    }
  }
  RexValue out;
  out.tag = REX_VEC;
  out.as.ptr = v;
  return out;
}

static void map_grow(RexMap* m) {
  if (m->capacity == 0) {
    m->capacity = 4;
    m->items = (RexMapEntry*)rex_xmalloc(sizeof(RexMapEntry) * (size_t)m->capacity);
  } else if (m->count >= m->capacity) {
    m->capacity *= 2;
    m->items = (RexMapEntry*)realloc(m->items, sizeof(RexMapEntry) * (size_t)m->capacity);
    if (!m->items) {
      rex_panic("map realloc failed");
    }
  }
}

RexValue rex_collections_map_new(void) {
  RexMap* m = (RexMap*)rex_xmalloc(sizeof(RexMap));
  m->items = NULL;
  m->count = 0;
  m->capacity = 0;
  RexValue out;
  out.tag = REX_MAP;
  out.as.ptr = m;
  return out;
}

void rex_collections_map_put(RexValue map, RexValue key, RexValue value) {
  map = rex_resolve_mut(map);
  if (map.tag != REX_MAP || !map.as.ptr) {
    rex_panic("map_put expects map");
    return;
  }
  RexMap* m = (RexMap*)map.as.ptr;
  for (int i = 0; i < m->count; i++) {
    if (rex_value_eq(m->items[i].key, key)) {
      m->items[i].value = value;
      return;
    }
  }
  map_grow(m);
  m->items[m->count].key = key;
  m->items[m->count].value = value;
  m->count += 1;
}

RexValue rex_collections_map_get(RexValue map, RexValue key) {
  map = rex_resolve(map);
  if (map.tag != REX_MAP || !map.as.ptr) {
    rex_panic("map_get expects map");
    return rex_nil();
  }
  RexMap* m = (RexMap*)map.as.ptr;
  for (int i = 0; i < m->count; i++) {
    if (rex_value_eq(m->items[i].key, key)) {
      return m->items[i].value;
    }
  }
  return rex_nil();
}

RexValue rex_collections_map_remove(RexValue map, RexValue key) {
  map = rex_resolve_mut(map);
  if (map.tag != REX_MAP || !map.as.ptr) {
    rex_panic("map_remove expects map");
    return rex_bool(0);
  }
  RexMap* m = (RexMap*)map.as.ptr;
  for (int i = 0; i < m->count; i++) {
    if (rex_value_eq(m->items[i].key, key)) {
      for (int j = i + 1; j < m->count; j++) {
        m->items[j - 1] = m->items[j];
      }
      m->count -= 1;
      return rex_bool(1);
    }
  }
  return rex_bool(0);
}

RexValue rex_collections_map_has(RexValue map, RexValue key) {
  map = rex_resolve(map);
  if (map.tag != REX_MAP || !map.as.ptr) {
    rex_panic("map_has expects map");
    return rex_bool(0);
  }
  RexMap* m = (RexMap*)map.as.ptr;
  for (int i = 0; i < m->count; i++) {
    if (rex_value_eq(m->items[i].key, key)) {
      return rex_bool(1);
    }
  }
  return rex_bool(0);
}

RexValue rex_collections_map_keys(RexValue map) {
  map = rex_resolve(map);
  if (map.tag != REX_MAP || !map.as.ptr) {
    rex_panic("map_keys expects map");
    return rex_nil();
  }
  RexMap* m = (RexMap*)map.as.ptr;
  RexValue keys = rex_collections_vec_new();
  for (int i = 0; i < m->count; i++) {
    rex_collections_vec_push(keys, m->items[i].key);
  }
  return keys;
}

static void set_grow(RexSet* s) {
  if (s->capacity == 0) {
    s->capacity = 4;
    s->items = (RexValue*)rex_xmalloc(sizeof(RexValue) * (size_t)s->capacity);
  } else if (s->count >= s->capacity) {
    s->capacity *= 2;
    s->items = (RexValue*)realloc(s->items, sizeof(RexValue) * (size_t)s->capacity);
    if (!s->items) {
      rex_panic("set realloc failed");
    }
  }
}

RexValue rex_collections_set_new(void) {
  RexSet* s = (RexSet*)rex_xmalloc(sizeof(RexSet));
  s->items = NULL;
  s->count = 0;
  s->capacity = 0;
  RexValue out;
  out.tag = REX_SET;
  out.as.ptr = s;
  return out;
}

void rex_collections_set_add(RexValue set, RexValue value) {
  set = rex_resolve_mut(set);
  if (set.tag != REX_SET || !set.as.ptr) {
    rex_panic("set_add expects set");
    return;
  }
  RexSet* s = (RexSet*)set.as.ptr;
  for (int i = 0; i < s->count; i++) {
    if (rex_value_eq(s->items[i], value)) {
      return;
    }
  }
  set_grow(s);
  s->items[s->count++] = value;
}

RexValue rex_collections_set_has(RexValue set, RexValue value) {
  set = rex_resolve(set);
  if (set.tag != REX_SET || !set.as.ptr) {
    rex_panic("set_has expects set");
    return rex_bool(0);
  }
  RexSet* s = (RexSet*)set.as.ptr;
  for (int i = 0; i < s->count; i++) {
    if (rex_value_eq(s->items[i], value)) {
      return rex_bool(1);
    }
  }
  return rex_bool(0);
}

RexValue rex_collections_set_remove(RexValue set, RexValue value) {
  set = rex_resolve_mut(set);
  if (set.tag != REX_SET || !set.as.ptr) {
    rex_panic("set_remove expects set");
    return rex_bool(0);
  }
  RexSet* s = (RexSet*)set.as.ptr;
  for (int i = 0; i < s->count; i++) {
    if (rex_value_eq(s->items[i], value)) {
      s->items[i] = s->items[s->count - 1];
      s->count -= 1;
      return rex_bool(1);
    }
  }
  return rex_bool(0);
}

static void json_append_hex(RexStrBuilder* sb, unsigned char c) {
  char buf[7];
  snprintf(buf, sizeof(buf), "\\u%04x", (unsigned int)c);
  sb_append_str(sb, buf);
}

static void json_append_string(RexStrBuilder* sb, const char* s) {
  sb_append_char(sb, '"');
  if (!s) {
    s = "";
  }
  for (const unsigned char* p = (const unsigned char*)s; *p; p++) {
    unsigned char c = *p;
    switch (c) {
      case '"': sb_append_str(sb, "\\\""); break;
      case '\\': sb_append_str(sb, "\\\\"); break;
      case '\n': sb_append_str(sb, "\\n"); break;
      case '\r': sb_append_str(sb, "\\r"); break;
      case '\t': sb_append_str(sb, "\\t"); break;
      default:
        if (c < 32) {
          json_append_hex(sb, c);
        } else {
          sb_append_char(sb, (char)c);
        }
        break;
    }
  }
  sb_append_char(sb, '"');
}

static void json_append_indent(RexStrBuilder* sb, int indent, int depth) {
  if (indent <= 0) {
    return;
  }
  int total = indent * depth;
  for (int i = 0; i < total; i++) {
    sb_append_char(sb, ' ');
  }
}

static int json_encode_value(RexStrBuilder* sb, RexValue v, int depth, int indent, int pretty) {
  if (depth > 64) {
    return 0;
  }
  v = rex_resolve(v);
  switch (v.tag) {
    case REX_NIL:
      sb_append_str(sb, "null");
      return 1;
    case REX_BOOL:
      sb_append_str(sb, v.as.boolean ? "true" : "false");
      return 1;
    case REX_NUM: {
      char buf[64];
      snprintf(buf, sizeof(buf), "%.14g", v.as.num);
      sb_append_str(sb, buf);
      return 1;
    }
    case REX_STR:
      json_append_string(sb, v.as.str);
      return 1;
    case REX_VEC: {
      RexVec* vec = (RexVec*)v.as.ptr;
      sb_append_char(sb, '[');
      if (vec && vec->count > 0) {
        if (pretty) {
          sb_append_char(sb, '\n');
        }
        for (int i = 0; i < vec->count; i++) {
          if (pretty) {
            json_append_indent(sb, indent, depth + 1);
          }
          if (!json_encode_value(sb, vec->items[i], depth + 1, indent, pretty)) {
            return 0;
          }
          if (i < vec->count - 1) {
            sb_append_char(sb, ',');
          }
          if (pretty) {
            sb_append_char(sb, '\n');
          }
        }
        if (pretty) {
          json_append_indent(sb, indent, depth);
        }
      }
      sb_append_char(sb, ']');
      return 1;
    }
    case REX_MAP: {
      RexMap* map = (RexMap*)v.as.ptr;
      sb_append_char(sb, '{');
      if (map && map->count > 0) {
        if (pretty) {
          sb_append_char(sb, '\n');
        }
        for (int i = 0; i < map->count; i++) {
          if (pretty) {
            json_append_indent(sb, indent, depth + 1);
          }
          const char* key = rex_to_cstr(map->items[i].key);
          json_append_string(sb, key);
          sb_append_char(sb, ':');
          if (pretty) {
            sb_append_char(sb, ' ');
          }
          if (!json_encode_value(sb, map->items[i].value, depth + 1, indent, pretty)) {
            return 0;
          }
          if (i < map->count - 1) {
            sb_append_char(sb, ',');
          }
          if (pretty) {
            sb_append_char(sb, '\n');
          }
        }
        if (pretty) {
          json_append_indent(sb, indent, depth);
        }
      }
      sb_append_char(sb, '}');
      return 1;
    }
    case REX_STRUCT: {
      RexStruct* s = (RexStruct*)v.as.ptr;
      sb_append_char(sb, '{');
      if (s && s->count > 0) {
        if (pretty) {
          sb_append_char(sb, '\n');
        }
        for (int i = 0; i < s->count; i++) {
          if (pretty) {
            json_append_indent(sb, indent, depth + 1);
          }
          json_append_string(sb, s->fields[i]);
          sb_append_char(sb, ':');
          if (pretty) {
            sb_append_char(sb, ' ');
          }
          if (!json_encode_value(sb, s->values[i], depth + 1, indent, pretty)) {
            return 0;
          }
          if (i < s->count - 1) {
            sb_append_char(sb, ',');
          }
          if (pretty) {
            sb_append_char(sb, '\n');
          }
        }
        if (pretty) {
          json_append_indent(sb, indent, depth);
        }
      }
      sb_append_char(sb, '}');
      return 1;
    }
    case REX_TUPLE: {
      RexTuple* t = (RexTuple*)v.as.ptr;
      sb_append_char(sb, '[');
      if (t && t->count > 0) {
        if (pretty) {
          sb_append_char(sb, '\n');
        }
        for (int i = 0; i < t->count; i++) {
          if (pretty) {
            json_append_indent(sb, indent, depth + 1);
          }
          if (!json_encode_value(sb, t->items[i], depth + 1, indent, pretty)) {
            return 0;
          }
          if (i < t->count - 1) {
            sb_append_char(sb, ',');
          }
          if (pretty) {
            sb_append_char(sb, '\n');
          }
        }
        if (pretty) {
          json_append_indent(sb, indent, depth);
        }
      }
      sb_append_char(sb, ']');
      return 1;
    }
    default:
      break;
  }
  return 0;
}

RexValue rex_json_encode(RexValue v) {
  v = rex_resolve(v);
  RexStrBuilder sb;
  sb_init(&sb);
  if (!json_encode_value(&sb, v, 0, 0, 0)) {
    sb_free(&sb);
    return rex_err(rex_str("json encode unsupported"));
  }
  RexValue out = rex_ok(rex_str(sb.data ? sb.data : ""));
  sb_free(&sb);
  return out;
}

RexValue rex_json_encode_pretty(RexValue v, RexValue indent) {
  v = rex_resolve(v);
  indent = rex_resolve(indent);
  if (indent.tag != REX_NUM) {
    rex_panic("json.encode_pretty expects number indent");
    return rex_err(rex_str("bad indent"));
  }
  int spaces = (int)indent.as.num;
  if (spaces < 0) {
    spaces = 0;
  }
  if (spaces > 8) {
    spaces = 8;
  }
  RexStrBuilder sb;
  sb_init(&sb);
  if (!json_encode_value(&sb, v, 0, spaces, spaces > 0)) {
    sb_free(&sb);
    return rex_err(rex_str("json encode unsupported"));
  }
  RexValue out = rex_ok(rex_str(sb.data ? sb.data : ""));
  sb_free(&sb);
  return out;
}

typedef struct JsonParser {
  const char* src;
  size_t len;
  size_t pos;
  const char* err;
} JsonParser;

static void json_skip_ws(JsonParser* p) {
  while (p->pos < p->len && isspace((unsigned char)p->src[p->pos])) {
    p->pos++;
  }
}

static int json_match(JsonParser* p, char c) {
  if (p->pos < p->len && p->src[p->pos] == c) {
    p->pos++;
    return 1;
  }
  return 0;
}

static RexValue json_parse_value(JsonParser* p);

static RexValue json_error(JsonParser* p, const char* msg) {
  if (!p->err) {
    p->err = msg;
  }
  return rex_nil();
}

static int json_hex_value(char c) {
  if (c >= '0' && c <= '9') {
    return c - '0';
  }
  if (c >= 'a' && c <= 'f') {
    return 10 + (c - 'a');
  }
  if (c >= 'A' && c <= 'F') {
    return 10 + (c - 'A');
  }
  return -1;
}

static int json_parse_hex4(JsonParser* p, int* out) {
  if (p->pos + 4 > p->len) {
    return 0;
  }
  int code = 0;
  for (int i = 0; i < 4; i++) {
    int v = json_hex_value(p->src[p->pos++]);
    if (v < 0) {
      return 0;
    }
    code = (code << 4) | v;
  }
  *out = code;
  return 1;
}

static void json_append_utf8(RexStrBuilder* sb, unsigned int code) {
  if (code <= 0x7F) {
    sb_append_char(sb, (char)code);
    return;
  }
  if (code <= 0x7FF) {
    sb_append_char(sb, (char)(0xC0 | ((code >> 6) & 0x1F)));
    sb_append_char(sb, (char)(0x80 | (code & 0x3F)));
    return;
  }
  if (code <= 0xFFFF) {
    sb_append_char(sb, (char)(0xE0 | ((code >> 12) & 0x0F)));
    sb_append_char(sb, (char)(0x80 | ((code >> 6) & 0x3F)));
    sb_append_char(sb, (char)(0x80 | (code & 0x3F)));
    return;
  }
  if (code <= 0x10FFFF) {
    sb_append_char(sb, (char)(0xF0 | ((code >> 18) & 0x07)));
    sb_append_char(sb, (char)(0x80 | ((code >> 12) & 0x3F)));
    sb_append_char(sb, (char)(0x80 | ((code >> 6) & 0x3F)));
    sb_append_char(sb, (char)(0x80 | (code & 0x3F)));
    return;
  }
  sb_append_char(sb, '?');
}

static RexValue json_parse_string(JsonParser* p) {
  if (!json_match(p, '"')) {
    return json_error(p, "expected string");
  }
  RexStrBuilder sb;
  sb_init(&sb);
  while (p->pos < p->len) {
    char c = p->src[p->pos++];
    if (c == '"') {
      RexValue out = rex_str(sb.data ? sb.data : "");
      sb_free(&sb);
      return out;
    }
    if (c == '\\') {
      if (p->pos >= p->len) {
        sb_free(&sb);
        return json_error(p, "bad escape");
      }
      char esc = p->src[p->pos++];
      switch (esc) {
        case '"': sb_append_char(&sb, '"'); break;
        case '\\': sb_append_char(&sb, '\\'); break;
        case '/': sb_append_char(&sb, '/'); break;
        case 'b': sb_append_char(&sb, '\b'); break;
        case 'f': sb_append_char(&sb, '\f'); break;
        case 'n': sb_append_char(&sb, '\n'); break;
        case 'r': sb_append_char(&sb, '\r'); break;
        case 't': sb_append_char(&sb, '\t'); break;
        case 'u': {
          int code = 0;
          if (!json_parse_hex4(p, &code)) {
            sb_free(&sb);
            return json_error(p, "bad unicode escape");
          }
          if (code >= 0xD800 && code <= 0xDBFF) {
            if (p->pos + 2 > p->len || p->src[p->pos] != '\\' || p->src[p->pos + 1] != 'u') {
              sb_free(&sb);
              return json_error(p, "bad unicode escape");
            }
            p->pos += 2;
            int low = 0;
            if (!json_parse_hex4(p, &low)) {
              sb_free(&sb);
              return json_error(p, "bad unicode escape");
            }
            if (low < 0xDC00 || low > 0xDFFF) {
              sb_free(&sb);
              return json_error(p, "bad unicode escape");
            }
            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
          } else if (code >= 0xDC00 && code <= 0xDFFF) {
            sb_free(&sb);
            return json_error(p, "bad unicode escape");
          }
          json_append_utf8(&sb, (unsigned int)code);
          break;
        }
        default:
          sb_free(&sb);
          return json_error(p, "bad escape");
      }
    } else {
      sb_append_char(&sb, c);
    }
  }
  sb_free(&sb);
  return json_error(p, "unterminated string");
}

static RexValue json_parse_number(JsonParser* p) {
  const char* start = p->src + p->pos;
  char* end = NULL;
  double value = strtod(start, &end);
  if (end == start) {
    return json_error(p, "bad number");
  }
  p->pos = (size_t)(end - p->src);
  return rex_num(value);
}

static RexValue json_parse_array(JsonParser* p) {
  if (!json_match(p, '[')) {
    return json_error(p, "expected array");
  }
  RexValue arr = rex_collections_vec_new();
  json_skip_ws(p);
  if (json_match(p, ']')) {
    return arr;
  }
  while (p->pos < p->len) {
    RexValue v = json_parse_value(p);
    if (p->err) {
      return v;
    }
    rex_collections_vec_push(arr, v);
    json_skip_ws(p);
    if (json_match(p, ',')) {
      json_skip_ws(p);
      continue;
    }
    if (json_match(p, ']')) {
      return arr;
    }
    return json_error(p, "expected ',' or ']'");
  }
  return json_error(p, "unterminated array");
}

static RexValue json_parse_object(JsonParser* p) {
  if (!json_match(p, '{')) {
    return json_error(p, "expected object");
  }
  RexValue obj = rex_collections_map_new();
  json_skip_ws(p);
  if (json_match(p, '}')) {
    return obj;
  }
  while (p->pos < p->len) {
    json_skip_ws(p);
    RexValue key = json_parse_string(p);
    if (p->err) {
      return key;
    }
    json_skip_ws(p);
    if (!json_match(p, ':')) {
      return json_error(p, "expected ':'");
    }
    json_skip_ws(p);
    RexValue val = json_parse_value(p);
    if (p->err) {
      return val;
    }
    rex_collections_map_put(obj, key, val);
    json_skip_ws(p);
    if (json_match(p, ',')) {
      json_skip_ws(p);
      continue;
    }
    if (json_match(p, '}')) {
      return obj;
    }
    return json_error(p, "expected ',' or '}'");
  }
  return json_error(p, "unterminated object");
}

static RexValue json_parse_value(JsonParser* p) {
  json_skip_ws(p);
  if (p->pos >= p->len) {
    return json_error(p, "unexpected end");
  }
  char c = p->src[p->pos];
  if (c == '"') {
    return json_parse_string(p);
  }
  if (c == '[') {
    return json_parse_array(p);
  }
  if (c == '{') {
    return json_parse_object(p);
  }
  if (c == 'n' && p->pos + 4 <= p->len && strncmp(p->src + p->pos, "null", 4) == 0) {
    p->pos += 4;
    return rex_nil();
  }
  if (c == 't' && p->pos + 4 <= p->len && strncmp(p->src + p->pos, "true", 4) == 0) {
    p->pos += 4;
    return rex_bool(1);
  }
  if (c == 'f' && p->pos + 5 <= p->len && strncmp(p->src + p->pos, "false", 5) == 0) {
    p->pos += 5;
    return rex_bool(0);
  }
  if (c == '-' || (c >= '0' && c <= '9')) {
    return json_parse_number(p);
  }
  return json_error(p, "unexpected token");
}

RexValue rex_json_decode(RexValue s) {
  s = rex_resolve(s);
  if (s.tag != REX_STR) {
    rex_panic("json.decode expects string");
    return rex_err(rex_str("bad input"));
  }
  const char* src = s.as.str ? s.as.str : "";
  JsonParser p;
  p.src = src;
  p.len = strlen(src);
  p.pos = 0;
  p.err = NULL;
  RexValue v = json_parse_value(&p);
  if (p.err) {
    return rex_err(rex_str(p.err));
  }
  json_skip_ws(&p);
  if (p.pos != p.len) {
    return rex_err(rex_str("trailing data"));
  }
  return rex_ok(v);
}

RexValue rex_net_tcp_connect(RexValue addr) {
  addr = rex_resolve(addr);
  (void)addr;
  return rex_err(rex_str("net not implemented"));
}

RexValue rex_net_udp_socket(void) {
  return rex_err(rex_str("net not implemented"));
}

typedef struct RexUrlParts {
  char* host;
  char* port;
  char* path;
  int use_tls;
} RexUrlParts;

typedef struct RexHttpResponse {
  int status;
  char* body;
} RexHttpResponse;

static void rex_url_free(RexUrlParts* parts) {
  if (!parts) {
    return;
  }
  free(parts->host);
  free(parts->port);
  free(parts->path);
  parts->host = NULL;
  parts->port = NULL;
  parts->path = NULL;
}

static int rex_http_parse_url(const char* url, RexUrlParts* out, const char** err) {
  const char* s = url;
  const char* http = "http://";
  const char* https = "https://";
  size_t http_len = strlen(http);
  size_t https_len = strlen(https);
  if (strncmp(s, https, https_len) == 0) {
    out->use_tls = 1;
    s += https_len;
  } else if (strncmp(s, http, http_len) == 0) {
    out->use_tls = 0;
    s += http_len;
  } else {
    if (err) {
      *err = "only http:// or https:// supported";
    }
    return 0;
  }
  if (*s == '\0') {
    if (err) {
      *err = "missing host";
    }
    return 0;
  }
  const char* path = strchr(s, '/');
  const char* host_end = path ? path : (s + strlen(s));
  const char* colon = NULL;
  for (const char* p = s; p < host_end; p++) {
    if (*p == ':') {
      colon = p;
      break;
    }
  }
  const char* host_end_actual = colon ? colon : host_end;
  size_t host_len = (size_t)(host_end_actual - s);
  if (host_len == 0) {
    if (err) {
      *err = "missing host";
    }
    return 0;
  }
  out->host = (char*)rex_xmalloc(host_len + 1);
  memcpy(out->host, s, host_len);
  out->host[host_len] = '\0';
  if (colon) {
    size_t port_len = (size_t)(host_end - colon - 1);
    if (port_len == 0) {
      if (err) {
        *err = "bad port";
      }
      return 0;
    }
    out->port = (char*)rex_xmalloc(port_len + 1);
    memcpy(out->port, colon + 1, port_len);
    out->port[port_len] = '\0';
  } else {
    out->port = rex_strdup(out->use_tls ? "443" : "80");
  }
  if (path) {
    out->path = rex_strdup(path);
  } else {
    out->path = rex_strdup("/");
  }
  return 1;
}

static int rex_http_status(const char* data, int len) {
  if (len < 12) {
    return 0;
  }
  if (strncmp(data, "HTTP/", 5) != 0) {
    return 0;
  }
  const char* space = strchr(data, ' ');
  if (!space) {
    return 0;
  }
  return atoi(space + 1);
}

static int rex_http_fetch_socket(const RexUrlParts* parts, RexHttpResponse* out, const char** err) {
  struct addrinfo hints;
  struct addrinfo* res = NULL;
  memset(&hints, 0, sizeof(hints));
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = AF_UNSPEC;
  if (getaddrinfo(parts->host, parts->port, &hints, &res) != 0) {
    if (err) {
      *err = "dns failed";
    }
    return 0;
  }
  int connected = 0;
#ifdef _WIN32
  SOCKET sock = INVALID_SOCKET;
#else
  int sock = -1;
#endif
  for (struct addrinfo* it = res; it; it = it->ai_next) {
#ifdef _WIN32
    sock = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
    if (sock == INVALID_SOCKET) {
      continue;
    }
#else
    sock = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
    if (sock < 0) {
      continue;
    }
#endif
    if (connect(sock, it->ai_addr, (int)it->ai_addrlen) == 0) {
      connected = 1;
      break;
    }
#ifdef _WIN32
    closesocket(sock);
#else
    close(sock);
#endif
  }
  freeaddrinfo(res);
  if (!connected) {
    if (err) {
      *err = "connect failed";
    }
    return 0;
  }

  RexStrBuilder req;
  sb_init(&req);
  sb_append_str(&req, "GET ");
  sb_append_str(&req, parts->path);
  sb_append_str(&req, " HTTP/1.0\r\nHost: ");
  sb_append_str(&req, parts->host);
  sb_append_str(&req, "\r\nConnection: close\r\n\r\n");
  send(sock, req.data ? req.data : "", (int)req.len, 0);
  sb_free(&req);

  RexStrBuilder resp;
  sb_init(&resp);
  char buf[4096];
  int n = 0;
  while ((n = (int)recv(sock, buf, sizeof(buf), 0)) > 0) {
    sb_append_bytes(&resp, buf, n);
  }
#ifdef _WIN32
  closesocket(sock);
#else
  close(sock);
#endif

  if (!resp.data || resp.len == 0) {
    sb_free(&resp);
    if (err) {
      *err = "empty response";
    }
    return 0;
  }

  int status = rex_http_status(resp.data, resp.len);
  if (status <= 0) {
    sb_free(&resp);
    if (err) {
      *err = "bad response";
    }
    return 0;
  }

  const char* header_end = strstr(resp.data, "\r\n\r\n");
  if (!header_end) {
    sb_free(&resp);
    if (err) {
      *err = "bad response";
    }
    return 0;
  }
  header_end += 4;
  int body_len = resp.len - (int)(header_end - resp.data);
  if (body_len < 0) {
    sb_free(&resp);
    if (err) {
      *err = "bad response";
    }
    return 0;
  }
  char* body = (char*)rex_xmalloc((size_t)body_len + 1);
  memcpy(body, header_end, (size_t)body_len);
  body[body_len] = '\0';
  sb_free(&resp);
  if (out) {
    out->status = status;
    out->body = body;
  } else {
    free(body);
  }
  return 1;
}

#ifndef _WIN32
static int rex_ssl_ready = 0;

static void rex_ssl_init(void) {
  if (rex_ssl_ready) {
    return;
  }
  SSL_library_init();
  SSL_load_error_strings();
  OpenSSL_add_all_algorithms();
  rex_ssl_ready = 1;
}

static int rex_http_fetch_openssl(const RexUrlParts* parts, RexHttpResponse* out, const char** err) {
  struct addrinfo hints;
  struct addrinfo* res = NULL;
  memset(&hints, 0, sizeof(hints));
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = AF_UNSPEC;
  if (getaddrinfo(parts->host, parts->port, &hints, &res) != 0) {
    if (err) {
      *err = "dns failed";
    }
    return 0;
  }

  int connected = 0;
  int sock = -1;
  for (struct addrinfo* it = res; it; it = it->ai_next) {
    sock = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
    if (sock < 0) {
      continue;
    }
    if (connect(sock, it->ai_addr, (int)it->ai_addrlen) == 0) {
      connected = 1;
      break;
    }
    close(sock);
    sock = -1;
  }
  freeaddrinfo(res);
  if (!connected) {
    if (err) {
      *err = "connect failed";
    }
    return 0;
  }

  rex_ssl_init();
  SSL_CTX* ctx = SSL_CTX_new(TLS_client_method());
  if (!ctx) {
    close(sock);
    if (err) {
      *err = "ssl ctx failed";
    }
    return 0;
  }
  SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
  SSL_CTX_set_default_verify_paths(ctx);

  SSL* ssl = SSL_new(ctx);
  if (!ssl) {
    SSL_CTX_free(ctx);
    close(sock);
    if (err) {
      *err = "ssl init failed";
    }
    return 0;
  }
  SSL_set_fd(ssl, sock);
  SSL_set_tlsext_host_name(ssl, parts->host);

  if (SSL_connect(ssl) != 1) {
    SSL_free(ssl);
    SSL_CTX_free(ctx);
    close(sock);
    if (err) {
      *err = "ssl connect failed";
    }
    return 0;
  }
  if (SSL_get_verify_result(ssl) != X509_V_OK) {
    SSL_shutdown(ssl);
    SSL_free(ssl);
    SSL_CTX_free(ctx);
    close(sock);
    if (err) {
      *err = "ssl verify failed";
    }
    return 0;
  }

  RexStrBuilder req;
  sb_init(&req);
  sb_append_str(&req, "GET ");
  sb_append_str(&req, parts->path);
  sb_append_str(&req, " HTTP/1.0\r\nHost: ");
  sb_append_str(&req, parts->host);
  sb_append_str(&req, "\r\nConnection: close\r\n\r\n");
  int total = 0;
  while (total < req.len) {
    int wrote = SSL_write(ssl, req.data + total, req.len - total);
    if (wrote <= 0) {
      sb_free(&req);
      SSL_shutdown(ssl);
      SSL_free(ssl);
      SSL_CTX_free(ctx);
      close(sock);
      if (err) {
        *err = "ssl write failed";
      }
      return 0;
    }
    total += wrote;
  }
  sb_free(&req);

  RexStrBuilder resp;
  sb_init(&resp);
  char buf[4096];
  while (1) {
    int n = SSL_read(ssl, buf, (int)sizeof(buf));
    if (n > 0) {
      sb_append_bytes(&resp, buf, n);
      continue;
    }
    int ssl_err = SSL_get_error(ssl, n);
    if (ssl_err == SSL_ERROR_WANT_READ || ssl_err == SSL_ERROR_WANT_WRITE) {
      continue;
    }
    break;
  }

  SSL_shutdown(ssl);
  SSL_free(ssl);
  SSL_CTX_free(ctx);
  close(sock);

  if (!resp.data || resp.len == 0) {
    sb_free(&resp);
    if (err) {
      *err = "empty response";
    }
    return 0;
  }

  int status = rex_http_status(resp.data, resp.len);
  if (status <= 0) {
    sb_free(&resp);
    if (err) {
      *err = "bad response";
    }
    return 0;
  }

  const char* header_end = strstr(resp.data, "\r\n\r\n");
  if (!header_end) {
    sb_free(&resp);
    if (err) {
      *err = "bad response";
    }
    return 0;
  }
  header_end += 4;
  int body_len = resp.len - (int)(header_end - resp.data);
  if (body_len < 0) {
    sb_free(&resp);
    if (err) {
      *err = "bad response";
    }
    return 0;
  }
  char* body = (char*)rex_xmalloc((size_t)body_len + 1);
  memcpy(body, header_end, (size_t)body_len);
  body[body_len] = '\0';
  sb_free(&resp);
  if (out) {
    out->status = status;
    out->body = body;
  } else {
    free(body);
  }
  return 1;
}
#endif

#ifdef _WIN32
#include <winhttp.h>

static wchar_t* rex_utf8_to_wide(const char* s) {
  if (!s) {
    s = "";
  }
  int len = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  if (len <= 0) {
    return NULL;
  }
  wchar_t* out = (wchar_t*)rex_xmalloc(sizeof(wchar_t) * (size_t)len);
  if (!out) {
    return NULL;
  }
  MultiByteToWideChar(CP_UTF8, 0, s, -1, out, len);
  return out;
}

static int rex_http_fetch_winhttp(const RexUrlParts* parts, RexHttpResponse* out, const char** err) {
  wchar_t* host_w = rex_utf8_to_wide(parts->host);
  wchar_t* path_w = rex_utf8_to_wide(parts->path);
  if (!host_w || !path_w) {
    free(host_w);
    free(path_w);
    if (err) {
      *err = "winhttp utf8 failed";
    }
    return 0;
  }

  HINTERNET session = WinHttpOpen(L"Rex/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) {
    free(host_w);
    free(path_w);
    if (err) {
      *err = "winhttp init failed";
    }
    return 0;
  }

  INTERNET_PORT port = (INTERNET_PORT)atoi(parts->port ? parts->port : (parts->use_tls ? "443" : "80"));
  HINTERNET connect = WinHttpConnect(session, host_w, port, 0);
  if (!connect) {
    WinHttpCloseHandle(session);
    free(host_w);
    free(path_w);
    if (err) {
      *err = "winhttp connect failed";
    }
    return 0;
  }

  DWORD flags = parts->use_tls ? WINHTTP_FLAG_SECURE : 0;
  HINTERNET request = WinHttpOpenRequest(connect, L"GET", path_w, NULL, WINHTTP_NO_REFERER,
    WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
  if (!request) {
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    free(host_w);
    free(path_w);
    if (err) {
      *err = "winhttp request failed";
    }
    return 0;
  }

  BOOL ok = WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
  if (!ok || !WinHttpReceiveResponse(request, NULL)) {
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    free(host_w);
    free(path_w);
    if (err) {
      *err = "winhttp send failed";
    }
    return 0;
  }

  DWORD status = 0;
  DWORD status_size = sizeof(status);
  if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size, WINHTTP_NO_HEADER_INDEX)) {
    status = 0;
  }

  RexStrBuilder resp;
  sb_init(&resp);
  while (1) {
    DWORD size = 0;
    if (!WinHttpQueryDataAvailable(request, &size)) {
      sb_free(&resp);
      WinHttpCloseHandle(request);
      WinHttpCloseHandle(connect);
      WinHttpCloseHandle(session);
      free(host_w);
      free(path_w);
      if (err) {
        *err = "winhttp read failed";
      }
      return 0;
    }
    if (size == 0) {
      break;
    }
    char* buf = (char*)rex_xmalloc(size);
    if (!buf) {
      sb_free(&resp);
      WinHttpCloseHandle(request);
      WinHttpCloseHandle(connect);
      WinHttpCloseHandle(session);
      free(host_w);
      free(path_w);
      if (err) {
        *err = "winhttp out of memory";
      }
      return 0;
    }
    DWORD read = 0;
    if (!WinHttpReadData(request, buf, size, &read)) {
      free(buf);
      sb_free(&resp);
      WinHttpCloseHandle(request);
      WinHttpCloseHandle(connect);
      WinHttpCloseHandle(session);
      free(host_w);
      free(path_w);
      if (err) {
        *err = "winhttp read failed";
      }
      return 0;
    }
    if (read > 0) {
      sb_append_bytes(&resp, buf, (int)read);
    }
    free(buf);
  }

  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connect);
  WinHttpCloseHandle(session);
  free(host_w);
  free(path_w);

  if (!resp.data) {
    sb_free(&resp);
    if (err) {
      *err = "empty response";
    }
    return 0;
  }
  char* body = (char*)rex_xmalloc(resp.len + 1);
  memcpy(body, resp.data, resp.len);
  body[resp.len] = '\0';
  sb_free(&resp);
  if (out) {
    out->status = (int)status;
    out->body = body;
  } else {
    free(body);
  }
  return 1;
}
#endif

static int rex_http_fetch(const char* url, RexHttpResponse* out, const char** err) {
  const char* parse_err = NULL;
  RexUrlParts parts = { 0 };
  if (!rex_http_parse_url(url ? url : "", &parts, &parse_err)) {
    rex_url_free(&parts);
    if (err) {
      *err = parse_err ? parse_err : "bad url";
    }
    return 0;
  }

#ifdef _WIN32
  if (parts.use_tls) {
    int ok = rex_http_fetch_winhttp(&parts, out, err);
    rex_url_free(&parts);
    return ok;
  }
#else
  if (parts.use_tls) {
    int ok = rex_http_fetch_openssl(&parts, out, err);
    rex_url_free(&parts);
    return ok;
  }
#endif

#ifdef _WIN32
  static int wsa_ready = 0;
  if (!wsa_ready) {
    WSADATA data;
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
      rex_url_free(&parts);
      if (err) {
        *err = "winsock init failed";
      }
      return 0;
    }
    wsa_ready = 1;
  }
#endif

  int ok = rex_http_fetch_socket(&parts, out, err);
  rex_url_free(&parts);
  return ok;
}

RexValue rex_http_get(RexValue url) {
  url = rex_resolve(url);
  if (url.tag != REX_STR) {
    rex_panic("http.get expects string");
    return rex_err(rex_str("bad url"));
  }
  const char* err = NULL;
  const char* url_str = url.as.str ? url.as.str : "";
  RexHttpResponse resp = { 0 };
  if (!rex_http_fetch(url_str, &resp, &err)) {
    return rex_err(rex_str(err ? err : "http error"));
  }
  if (resp.status >= 400) {
    free(resp.body);
    return rex_err(rex_str("http error"));
  }
  RexValue out = rex_ok(rex_str(resp.body ? resp.body : ""));
  free(resp.body);
  return out;
}

RexValue rex_http_get_status(RexValue url) {
  url = rex_resolve(url);
  if (url.tag != REX_STR) {
    rex_panic("http.get_status expects string");
    return rex_err(rex_str("bad url"));
  }
  const char* err = NULL;
  const char* url_str = url.as.str ? url.as.str : "";
  RexHttpResponse resp = { 0 };
  if (!rex_http_fetch(url_str, &resp, &err)) {
    return rex_err(rex_str(err ? err : "http error"));
  }
  RexValue map = rex_collections_map_new();
  rex_collections_map_put(map, rex_str("status"), rex_num((double)resp.status));
  rex_collections_map_put(map, rex_str("body"), rex_str(resp.body ? resp.body : ""));
  free(resp.body);
  return rex_ok(map);
}

RexValue rex_http_get_json(RexValue url) {
  url = rex_resolve(url);
  if (url.tag != REX_STR) {
    rex_panic("http.get_json expects string");
    return rex_err(rex_str("bad url"));
  }
  const char* err = NULL;
  const char* url_str = url.as.str ? url.as.str : "";
  RexHttpResponse resp = { 0 };
  if (!rex_http_fetch(url_str, &resp, &err)) {
    return rex_err(rex_str(err ? err : "http error"));
  }
  if (resp.status >= 400) {
    free(resp.body);
    return rex_err(rex_str("http error"));
  }
  RexValue text = rex_str(resp.body ? resp.body : "");
  free(resp.body);
  return rex_json_decode(text);
}



typedef struct RexOwnershipTrace {
  char* variable;
  char* event;
  uint64_t timestamp;
} RexOwnershipTrace;

static RexOwnershipTrace* rex_ownership_log = NULL;
static int rex_ownership_log_count = 0;
static int rex_ownership_log_capacity = 100;
static int rex_ownership_debug_enabled = 0;

#ifdef _WIN32
  static CRITICAL_SECTION rex_ownership_lock;
  static int rex_ownership_lock_init = 0;
  #define REX_OWNERSHIP_LOCK() \
    if (!rex_ownership_lock_init) { \
      InitializeCriticalSection(&rex_ownership_lock); \
      rex_ownership_lock_init = 1; \
    } \
    EnterCriticalSection(&rex_ownership_lock);
  #define REX_OWNERSHIP_UNLOCK() LeaveCriticalSection(&rex_ownership_lock);
#else
  static pthread_mutex_t rex_ownership_lock = PTHREAD_MUTEX_INITIALIZER;
  #define REX_OWNERSHIP_LOCK() pthread_mutex_lock(&rex_ownership_lock);
  #define REX_OWNERSHIP_UNLOCK() pthread_mutex_unlock(&rex_ownership_lock);
#endif

void rex_ownership_debug_enable(void) {
  REX_OWNERSHIP_LOCK();
  rex_ownership_debug_enabled = 1;
  REX_OWNERSHIP_UNLOCK();
}

void rex_ownership_debug_disable(void) {
  REX_OWNERSHIP_LOCK();
  rex_ownership_debug_enabled = 0;
  REX_OWNERSHIP_UNLOCK();
}

void rex_ownership_cleanup(void) {
  REX_OWNERSHIP_LOCK();
  if (rex_ownership_log) {
    for (int i = 0; i < rex_ownership_log_count; i++) {
      if (rex_ownership_log[i].variable) {
        free(rex_ownership_log[i].variable);
      }
      if (rex_ownership_log[i].event) {
        free(rex_ownership_log[i].event);
      }
    }
    free(rex_ownership_log);
    rex_ownership_log = NULL;
  }
  rex_ownership_log_count = 0;
  rex_ownership_log_capacity = 100;
  rex_ownership_debug_enabled = 0;
  REX_OWNERSHIP_UNLOCK();
}

void rex_ownership_trace(const char* variable, const char* event) {
  if (!variable || !event) {
    return;  
  }
  
  REX_OWNERSHIP_LOCK();
  
  if (!rex_ownership_debug_enabled) {
    REX_OWNERSHIP_UNLOCK();
    return;
  }
  
  if (!rex_ownership_log) {
    rex_ownership_log = (RexOwnershipTrace*)rex_xmalloc(
      rex_ownership_log_capacity * sizeof(RexOwnershipTrace)
    );
  }
  
  if (rex_ownership_log_count >= rex_ownership_log_capacity) {
    rex_ownership_log_capacity *= 2;
    RexOwnershipTrace* new_log = (RexOwnershipTrace*)rex_xmalloc(
      rex_ownership_log_capacity * sizeof(RexOwnershipTrace)
    );
    memcpy(new_log, rex_ownership_log, 
           rex_ownership_log_count * sizeof(RexOwnershipTrace));
    free(rex_ownership_log);
    rex_ownership_log = new_log;
  }
  
  
  rex_ownership_log[rex_ownership_log_count].variable = rex_strdup(variable);
  rex_ownership_log[rex_ownership_log_count].event = rex_strdup(event);
  
#ifdef _WIN32
  rex_ownership_log[rex_ownership_log_count].timestamp = GetTickCount64();
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  rex_ownership_log[rex_ownership_log_count].timestamp = 
    (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
  
  fprintf(stderr, "[ownership] %s %s\n", variable, event);
  rex_ownership_log_count++;
  
  REX_OWNERSHIP_UNLOCK();
}

void rex_ownership_check(const char* variable) {
  if (!variable) {
    return;  
  }
  
  REX_OWNERSHIP_LOCK();
  if (rex_ownership_debug_enabled) {
    fprintf(stderr, "[ownership] checking %s\n", variable);
  }
  REX_OWNERSHIP_UNLOCK();
}

uint64_t rex_temporal_now_ms(void) {
#ifdef _WIN32
  return GetTickCount64();
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

int rex_temporal_is_expired(uint64_t start_time, uint64_t lifetime_ms) {
  uint64_t now = rex_temporal_now_ms();
  return (now - start_time) >= lifetime_ms;
}


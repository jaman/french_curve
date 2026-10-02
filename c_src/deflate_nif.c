#include <erl_nif.h>
#include <libdeflate.h>

#define LOWEST 1
#define HIGHEST 12

static ERL_NIF_TERM compress(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary raw;
  struct libdeflate_compressor *compressor;
  ERL_NIF_TERM room;
  unsigned char *out;
  size_t bound, written;
  int level;

  (void)argc;

  if (!enif_inspect_binary(env, argv[0], &raw)) return enif_make_badarg(env);
  if (!enif_get_int(env, argv[1], &level)) return enif_make_badarg(env);

  if (level < LOWEST) level = LOWEST;
  if (level > HIGHEST) level = HIGHEST;

  compressor = libdeflate_alloc_compressor(level);
  if (compressor == NULL) return enif_make_badarg(env);

  bound = libdeflate_zlib_compress_bound(compressor, raw.size);
  out = enif_make_new_binary(env, bound, &room);
  written = libdeflate_zlib_compress(compressor, raw.data, raw.size, out, bound);
  libdeflate_free_compressor(compressor);

  if (written == 0) return enif_make_badarg(env);

  return enif_make_sub_binary(env, room, 0, written);
}

static ErlNifFunc funcs[] = {{"deflate", 2, compress, ERL_NIF_DIRTY_JOB_CPU_BOUND}};

ERL_NIF_INIT(Elixir.FrenchCurve.Deflate, funcs, NULL, NULL, NULL, NULL)

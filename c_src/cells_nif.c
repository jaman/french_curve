#include <erl_nif.h>
#include <string.h>

#define MAX_SUBPIXELS 8

typedef struct {
  int r, g, b;
} colour;

static int get_pair(ErlNifEnv *env, ERL_NIF_TERM term, int *first, int *second) {
  const ERL_NIF_TERM *field;
  int arity;

  if (!enif_get_tuple(env, term, &arity, &field) || arity != 2) return 0;
  return enif_get_int(env, field[0], first) && enif_get_int(env, field[1], second);
}

static int get_colour(ErlNifEnv *env, ERL_NIF_TERM term, colour *out) {
  const ERL_NIF_TERM *field;
  int arity;

  if (!enif_get_tuple(env, term, &arity, &field) || arity != 3) return 0;

  return enif_get_int(env, field[0], &out->r) && enif_get_int(env, field[1], &out->g) &&
         enif_get_int(env, field[2], &out->b);
}

static inline int luminance(colour c) { return c.r * 299 + c.g * 587 + c.b * 114; }

static inline int distance(colour a, colour b) {
  int dr = a.r - b.r;
  int dg = a.g - b.g;
  int db = a.b - b.b;
  return dr * dr + dg * dg + db * db;
}

static inline int same_colour(colour a, colour b) {
  return a.r == b.r && a.g == b.g && a.b == b.b;
}

static inline colour pixel_at(const unsigned char *rgba, int width, int height, int x, int y,
                              colour background, int threshold) {
  const unsigned char *at;
  colour out;

  if (x >= width || y >= height) return background;

  at = rgba + ((size_t)y * width + x) * 4;

  if (at[3] < threshold) return background;

  out.r = at[0];
  out.g = at[1];
  out.b = at[2];
  return out;
}

static ERL_NIF_TERM quantise(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary rgba;
  colour background;
  ERL_NIF_TERM result;
  unsigned char *out;
  int width, height, sx, sy, threshold, cols, rows, cx, cy;

  if (argc != 5) return enif_make_badarg(env);
  if (!enif_inspect_binary(env, argv[0], &rgba)) return enif_make_badarg(env);
  if (!get_pair(env, argv[1], &width, &height)) return enif_make_badarg(env);
  if (!get_pair(env, argv[2], &sx, &sy)) return enif_make_badarg(env);
  if (!get_colour(env, argv[3], &background)) return enif_make_badarg(env);
  if (!enif_get_int(env, argv[4], &threshold)) return enif_make_badarg(env);

  if (width <= 0 || height <= 0 || sx <= 0 || sy <= 0) return enif_make_badarg(env);
  if (sx * sy > MAX_SUBPIXELS) return enif_make_badarg(env);
  if (rgba.size != (size_t)width * height * 4) return enif_make_badarg(env);

  cols = (width + sx - 1) / sx;
  rows = (height + sy - 1) / sy;

  out = enif_make_new_binary(env, (size_t)cols * rows * 7, &result);
  if (out == NULL) return enif_make_badarg(env);

  for (cy = 0; cy < rows; cy++) {
    for (cx = 0; cx < cols; cx++) {
      colour pixels[MAX_SUBPIXELS];
      colour darkest, brightest, fg, bg;
      unsigned char *cell = out + ((size_t)cy * cols + cx) * 7;
      int count = 0, dx, dy, index, pattern = 0;
      int dark_key, bright_key;
      long lit_r = 0, lit_g = 0, lit_b = 0, lit_n = 0;
      long unlit_r = 0, unlit_g = 0, unlit_b = 0, unlit_n = 0;

      for (dy = 0; dy < sy; dy++) {
        for (dx = 0; dx < sx; dx++) {
          pixels[count++] = pixel_at(rgba.data, width, height, cx * sx + dx, cy * sy + dy,
                                     background, threshold);
        }
      }

      darkest = brightest = pixels[0];
      dark_key = bright_key = luminance(pixels[0]);

      for (index = 1; index < count; index++) {
        int key = luminance(pixels[index]);

        if (key < dark_key) {
          dark_key = key;
          darkest = pixels[index];
        }

        if (key > bright_key) {
          bright_key = key;
          brightest = pixels[index];
        }
      }

      if (same_colour(darkest, brightest)) {
        cell[0] = 0;
        cell[1] = cell[4] = (unsigned char)darkest.r;
        cell[2] = cell[5] = (unsigned char)darkest.g;
        cell[3] = cell[6] = (unsigned char)darkest.b;
        continue;
      }

      for (index = 0; index < count; index++) {
        if (distance(pixels[index], brightest) < distance(pixels[index], darkest)) {
          pattern |= 1 << index;
          lit_r += pixels[index].r;
          lit_g += pixels[index].g;
          lit_b += pixels[index].b;
          lit_n++;
        } else {
          unlit_r += pixels[index].r;
          unlit_g += pixels[index].g;
          unlit_b += pixels[index].b;
          unlit_n++;
        }
      }

      fg.r = lit_n ? (int)(lit_r / lit_n) : 0;
      fg.g = lit_n ? (int)(lit_g / lit_n) : 0;
      fg.b = lit_n ? (int)(lit_b / lit_n) : 0;
      bg.r = unlit_n ? (int)(unlit_r / unlit_n) : 0;
      bg.g = unlit_n ? (int)(unlit_g / unlit_n) : 0;
      bg.b = unlit_n ? (int)(unlit_b / unlit_n) : 0;

      cell[0] = (unsigned char)pattern;
      cell[1] = (unsigned char)fg.r;
      cell[2] = (unsigned char)fg.g;
      cell[3] = (unsigned char)fg.b;
      cell[4] = (unsigned char)bg.r;
      cell[5] = (unsigned char)bg.g;
      cell[6] = (unsigned char)bg.b;
    }
  }

  return result;
}

static ErlNifFunc funcs[] = {{"quantise", 5, quantise, ERL_NIF_DIRTY_JOB_CPU_BOUND}};

ERL_NIF_INIT(Elixir.FrenchCurve.Backend.Cells, funcs, NULL, NULL, NULL, NULL)

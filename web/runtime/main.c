// The native core of the web runtime. It runs the game's Ruby on mruby and gives the Ruby half of the DragonRuby
// API (dragonruby.rb) the module WebHost, whose functions hand drawing, sound and input over to host.js.
//
// host.js drives the frames: it calls web_boot once and web_tick once per tick. Each tick appends draw commands
// to a buffer of floats, which host.js renders when the tick is done (see COMMAND_* below and Renderer in host.js).
#include <emscripten.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/compile.h>
#include <mruby/error.h>
#include <mruby/string.h>

#define GAME_DIR "/game/"
#define PRELUDE_PATH "/runtime/dragonruby.rb"

// Commands in the buffer, each followed by its arguments
enum {
  COMMAND_TARGET = 1,  // id, w, h, r, g, b, a
  COMMAND_SPRITE = 2,  // SPRITE_FLOATS - 1 numbers, see ffi_draw_sprite_6
  COMMAND_SHADER = 3,  // target id, shader id, texture count, texture ids..., uniform count, (is_int, value)...
  COMMAND_SCREEN = 4,  // r, g, b, a
};
#define SPRITE_FLOATS 25

static mrb_state *mrb;
static mrb_value runtime;
static int default_scale_quality = 0;

static float *commands;
static int command_count;
static int command_capacity;

// --- host.js --------------------------------------------------------------------------------------------------

EM_JS(void, js_render, (const float *data, int count), {
  Module.host.render(HEAPF32.subarray(data >> 2, (data >> 2) + count));
});
EM_JS(void, js_register_texture, (int id, const char *name), {
  Module.host.registerTexture(id, UTF8ToString(name));
});
EM_JS(void, js_upload_pixels, (int id, int w, int h, const unsigned char *pixels), {
  Module.host.uploadPixels(id, w, h, HEAPU8.subarray(pixels, pixels + w * h * 4));
});
EM_JS(int, js_shader_id, (const char *path), {
  return Module.host.shaderId(UTF8ToString(path));
});
EM_JS(char *, js_input, (void), {
  return stringToNewUTF8(Module.host.input());
});
EM_JS(char *, js_audio_finished, (void), {
  return stringToNewUTF8(Module.host.audio.finished());
});
EM_JS(void, js_audio_play, (int voice, const char *path, double gain, double pitch, int looping), {
  Module.host.audio.play(voice, UTF8ToString(path), gain, pitch, looping != 0);
});
EM_JS(void, js_audio_update, (int voice, double gain, double pitch, int paused), {
  Module.host.audio.update(voice, gain, pitch, paused != 0);
});
EM_JS(void, js_audio_stop, (int voice), {
  Module.host.audio.stop(voice);
});
EM_JS(double, js_framerate, (void), {
  return Module.host.framerate();
});
EM_JS(void, js_fatal, (const char *message), {
  Module.host.fatal(UTF8ToString(message));
});

// --- Command buffer -------------------------------------------------------------------------------------------

static float *reserve_commands(int count) {
  if (command_count + count > command_capacity) {
    while (command_count + count > command_capacity) command_capacity = command_capacity ? command_capacity * 2 : 65536;
    commands = realloc(commands, sizeof(float) * command_capacity);
  }
  float *slot = commands + command_count;
  command_count += count;
  return slot;
}

// nil (an argument the caller left out) becomes NAN, which host.js replaces with the default
static float number_or_nan(mrb_value value) {
  if (mrb_nil_p(value)) return NAN;
  if (mrb_integer_p(value)) return (float)mrb_integer(value);
  if (mrb_float_p(value)) return (float)mrb_float(value);
  if (mrb_true_p(value)) return 1.0f;
  if (mrb_false_p(value)) return 0.0f;
  return (float)mrb_as_float(mrb, value);
}

// Like DragonRuby: a color channel or alpha is truncated to a whole number from 0 to 255 (100.9 draws as 100)
static float color_channel(mrb_value value) {
  float number = number_or_nan(value);
  if (isnan(number)) return number;
  number = truncf(number);
  return number < 0.0f ? 0.0f : (number > 255.0f ? 255.0f : number);
}

// --- Texture ids ----------------------------------------------------------------------------------------------

// Splat batches pass the same path String for thousands of sprites, so the last few lookups are remembered
#define PATH_CACHE_SIZE 4
#define PATH_CACHE_TEXT 64
static struct {
  struct RString *string;
  mrb_int length;
  char text[PATH_CACHE_TEXT];
  float id;
} path_cache[PATH_CACHE_SIZE];
static int path_cache_next;

static float texture_id(mrb_value path) {
  if (mrb_string_p(path)) {
    struct RString *string = mrb_str_ptr(path);
    mrb_int length = RSTRING_LEN(path);
    for (int i = 0; i < PATH_CACHE_SIZE; i++) {
      // The text is compared too: the garbage collector may have reused a cached String for another one
      if (path_cache[i].string == string && path_cache[i].length == length &&
          memcmp(path_cache[i].text, RSTRING_PTR(path), length) == 0) {
        return path_cache[i].id;
      }
    }
    float id = (float)mrb_integer(mrb_funcall(mrb, runtime, "texture_id", 1, path));
    if (length <= PATH_CACHE_TEXT) {
      int slot = path_cache_next;
      path_cache_next = (path_cache_next + 1) % PATH_CACHE_SIZE;
      path_cache[slot].string = string;
      path_cache[slot].length = length;
      memcpy(path_cache[slot].text, RSTRING_PTR(path), length);
      path_cache[slot].id = id;
    }
    return id;
  }
  return (float)mrb_integer(mrb_funcall(mrb, runtime, "texture_id", 1, path));
}

// --- WebHost::FFI ---------------------------------------------------------------------------------------------

// draw_sprite_6 takes DragonRuby's positional sprite arguments (see the engine's docs/oss/dragon/runtime/draw.rb):
// x, y, w, h, path, angle, a, r, g, b, tile_x, tile_y, tile_w, tile_h, flip_horizontally, flip_vertically,
// angle_anchor_x, angle_anchor_y, source_x, source_y, source_w, source_h, blendmode_enum, anchor_x, anchor_y,
// scale_quality_enum
static mrb_value ffi_draw_sprite_6(mrb_state *mrb, mrb_value self) {
  mrb_int argc = mrb_get_argc(mrb);
  const mrb_value *argv = mrb_get_argv(mrb);
  if (argc != 26) mrb_raisef(mrb, E_ARGUMENT_ERROR, "draw_sprite_6 takes 26 arguments, got %i", argc);

  float *c = reserve_commands(SPRITE_FLOATS);
  c[0] = COMMAND_SPRITE;
  c[1] = texture_id(argv[4]);
  c[2] = mrb_nil_p(argv[22]) ? 1.0f : number_or_nan(argv[22]);                     // blendmode_enum
  c[3] = mrb_nil_p(argv[25]) ? (float)default_scale_quality : number_or_nan(argv[25]);
  c[4] = number_or_nan(argv[0]);   // x
  c[5] = number_or_nan(argv[1]);   // y
  c[6] = number_or_nan(argv[2]);   // w
  c[7] = number_or_nan(argv[3]);   // h
  c[8] = number_or_nan(argv[5]);   // angle
  c[9] = number_or_nan(argv[16]);  // angle_anchor_x
  c[10] = number_or_nan(argv[17]); // angle_anchor_y
  c[11] = number_or_nan(argv[23]); // anchor_x
  c[12] = number_or_nan(argv[24]); // anchor_y
  c[13] = color_channel(argv[7]);  // r
  c[14] = color_channel(argv[8]);  // g
  c[15] = color_channel(argv[9]);  // b
  c[16] = color_channel(argv[6]);  // a
  // The source rectangle counts y from the bottom of the image; the tile rectangle counts it from the top
  int tile = !mrb_nil_p(argv[10]) || !mrb_nil_p(argv[11]) || !mrb_nil_p(argv[12]) || !mrb_nil_p(argv[13]);
  int source = tile ? 10 : 18;
  c[17] = number_or_nan(argv[source]);
  c[18] = number_or_nan(argv[source + 1]);
  c[19] = number_or_nan(argv[source + 2]);
  c[20] = number_or_nan(argv[source + 3]);
  c[21] = tile ? 1.0f : 0.0f;
  c[22] = mrb_test(argv[14]) ? 1.0f : 0.0f;
  c[23] = mrb_test(argv[15]) ? 1.0f : 0.0f;
  c[24] = 0.0f;
  return mrb_nil_value();
}

// --- WebHost --------------------------------------------------------------------------------------------------

static mrb_value host_begin_target(mrb_state *mrb, mrb_value self) {
  mrb_int id, w, h, r, g, b, a;
  mrb_get_args(mrb, "iiiiiii", &id, &w, &h, &r, &g, &b, &a);
  float *c = reserve_commands(8);
  c[0] = COMMAND_TARGET;
  c[1] = (float)id;
  c[2] = (float)w;
  c[3] = (float)h;
  c[4] = (float)r;
  c[5] = (float)g;
  c[6] = (float)b;
  c[7] = (float)a;
  return mrb_nil_value();
}

static mrb_value host_begin_screen(mrb_state *mrb, mrb_value self) {
  mrb_int r, g, b, a;
  mrb_get_args(mrb, "iiii", &r, &g, &b, &a);
  float *c = reserve_commands(5);
  c[0] = COMMAND_SCREEN;
  c[1] = (float)r;
  c[2] = (float)g;
  c[3] = (float)b;
  c[4] = (float)a;
  return mrb_nil_value();
}

// WebHost.set_shader(target_id, shader_id, texture_ids, uniforms), where uniforms alternates is_int and value:
// the shader that draws the target wherever it is drawn as a sprite (see Renderer#flush in host.js)
static mrb_value host_set_shader(mrb_state *mrb, mrb_value self) {
  mrb_int target, shader;
  mrb_value textures, uniforms;
  mrb_get_args(mrb, "iiAA", &target, &shader, &textures, &uniforms);
  mrb_int texture_count = RARRAY_LEN(textures);
  mrb_int uniform_count = RARRAY_LEN(uniforms) / 2;
  float *c = reserve_commands(5 + texture_count + uniform_count * 2);
  c[0] = COMMAND_SHADER;
  c[1] = (float)target;
  c[2] = (float)shader;
  c[3] = (float)texture_count;
  for (mrb_int i = 0; i < texture_count; i++) c[4 + i] = number_or_nan(RARRAY_PTR(textures)[i]);
  float *u = c + 4 + texture_count;
  u[0] = (float)uniform_count;
  for (mrb_int i = 0; i < uniform_count * 2; i++) u[1 + i] = number_or_nan(RARRAY_PTR(uniforms)[i]);
  return mrb_nil_value();
}

static mrb_value host_shader_id(mrb_state *mrb, mrb_value self) {
  const char *path;
  mrb_get_args(mrb, "z", &path);
  int id = js_shader_id(path);
  if (id < 0) mrb_raisef(mrb, E_ARGUMENT_ERROR, "No compiled shader for %s (web/build compiles mygame/shaders/*.hlsl)", path);
  return mrb_int_value(mrb, id);
}

static mrb_value host_register_texture(mrb_state *mrb, mrb_value self) {
  mrb_int id;
  const char *name;
  mrb_get_args(mrb, "iz", &id, &name);
  js_register_texture((int)id, name);
  return mrb_nil_value();
}

// Pixels are DragonRuby's 0xAABBGGRR Integers, so their little-endian bytes are RGBA
static mrb_value host_upload_pixels(mrb_state *mrb, mrb_value self) {
  mrb_int id, w, h;
  mrb_value pixels;
  mrb_get_args(mrb, "iiiA", &id, &w, &h, &pixels);
  mrb_int count = w * h;
  if (count <= 0) return mrb_nil_value();
  mrb_int length = RARRAY_LEN(pixels);
  unsigned int *buffer = calloc(count, sizeof(unsigned int));
  for (mrb_int i = 0; i < count && i < length; i++) {
    mrb_value pixel = RARRAY_PTR(pixels)[i];
    if (mrb_integer_p(pixel)) buffer[i] = (unsigned int)mrb_integer(pixel);
    else if (mrb_float_p(pixel)) buffer[i] = (unsigned int)(long long)mrb_float(pixel);
  }
  js_upload_pixels((int)id, (int)w, (int)h, (const unsigned char *)buffer);
  free(buffer);
  return mrb_nil_value();
}

static mrb_value host_set_default_scale_quality(mrb_state *mrb, mrb_value self) {
  mrb_int value;
  mrb_get_args(mrb, "i", &value);
  default_scale_quality = (int)value;
  return mrb_nil_value();
}

static mrb_value take_js_string(char *text) {
  mrb_value result = mrb_str_new_cstr(mrb, text);
  free(text);
  return result;
}

static mrb_value host_input(mrb_state *mrb, mrb_value self) {
  return take_js_string(js_input());
}

static mrb_value host_audio_finished(mrb_state *mrb, mrb_value self) {
  return take_js_string(js_audio_finished());
}

static mrb_value host_audio_play(mrb_state *mrb, mrb_value self) {
  mrb_int voice;
  const char *path;
  mrb_float gain, pitch;
  mrb_bool looping;
  mrb_get_args(mrb, "izffb", &voice, &path, &gain, &pitch, &looping);
  js_audio_play((int)voice, path, gain, pitch, looping);
  return mrb_nil_value();
}

static mrb_value host_audio_update(mrb_state *mrb, mrb_value self) {
  mrb_int voice;
  mrb_float gain, pitch;
  mrb_bool paused;
  mrb_get_args(mrb, "iffb", &voice, &gain, &pitch, &paused);
  js_audio_update((int)voice, gain, pitch, paused);
  return mrb_nil_value();
}

static mrb_value host_audio_stop(mrb_state *mrb, mrb_value self) {
  mrb_int voice;
  mrb_get_args(mrb, "i", &voice);
  js_audio_stop((int)voice);
  return mrb_nil_value();
}

static mrb_value host_framerate(mrb_state *mrb, mrb_value self) {
  return mrb_float_value(mrb, js_framerate());
}

static mrb_value host_fatal(mrb_state *mrb, mrb_value self) {
  const char *message;
  mrb_get_args(mrb, "z", &message);
  js_fatal(message);
  return mrb_nil_value();
}

static char *read_file(const char *path, size_t *length) {
  FILE *file = fopen(path, "rb");
  if (!file) return NULL;
  fseek(file, 0, SEEK_END);
  long size = ftell(file);
  fseek(file, 0, SEEK_SET);
  char *data = malloc(size + 1);
  *length = fread(data, 1, size, file);
  data[*length] = '\0';
  fclose(file);
  return data;
}

static void game_path(char *buffer, size_t size, const char *path) {
  snprintf(buffer, size, "%s%s", GAME_DIR, path);
}

// Paths are relative to the game's folder (mygame/), like DragonRuby's
static mrb_value host_read_file(mrb_state *mrb, mrb_value self) {
  const char *path;
  mrb_get_args(mrb, "z", &path);
  char full_path[1024];
  game_path(full_path, sizeof(full_path), path);
  size_t length;
  char *data = read_file(full_path, &length);
  if (!data) return mrb_nil_value();
  mrb_value result = mrb_str_new(mrb, data, length);
  free(data);
  return result;
}

static mrb_value host_file_exist(mrb_state *mrb, mrb_value self) {
  const char *path;
  mrb_get_args(mrb, "z", &path);
  char full_path[1024];
  game_path(full_path, sizeof(full_path), path);
  struct stat info;
  return mrb_bool_value(stat(full_path, &info) == 0 && S_ISREG(info.st_mode));
}

// Runs a Ruby file at the top level, with its path in backtraces
static mrb_value load_ruby(mrb_state *mrb, const char *full_path, const char *shown_path) {
  size_t length;
  char *source = read_file(full_path, &length);
  if (!source) mrb_raisef(mrb, E_RUNTIME_ERROR, "cannot load such file -- %s", shown_path);
  mrb_ccontext *context = mrb_ccontext_new(mrb);
  mrb_ccontext_filename(mrb, context, shown_path);
  mrb_value result = mrb_load_nstring_cxt(mrb, source, length, context);
  mrb_ccontext_free(mrb, context);
  free(source);
  if (mrb->exc) {
    mrb_value exception = mrb_obj_value(mrb->exc);
    mrb->exc = NULL;
    mrb_exc_raise(mrb, exception);
  }
  return result;
}

static mrb_value host_load(mrb_state *mrb, mrb_value self) {
  const char *path;
  mrb_get_args(mrb, "z", &path);
  char full_path[1024];
  game_path(full_path, sizeof(full_path), path);
  return load_ruby(mrb, full_path, path);
}

static void define_web_host(void) {
  struct RClass *host = mrb_define_module(mrb, "WebHost");
  mrb_define_module_function(mrb, host, "begin_target", host_begin_target, MRB_ARGS_REQ(7));
  mrb_define_module_function(mrb, host, "begin_screen", host_begin_screen, MRB_ARGS_REQ(4));
  mrb_define_module_function(mrb, host, "set_shader", host_set_shader, MRB_ARGS_REQ(4));
  mrb_define_module_function(mrb, host, "shader_id", host_shader_id, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, host, "register_texture", host_register_texture, MRB_ARGS_REQ(2));
  mrb_define_module_function(mrb, host, "upload_pixels", host_upload_pixels, MRB_ARGS_REQ(4));
  mrb_define_module_function(mrb, host, "default_scale_quality=", host_set_default_scale_quality, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, host, "input", host_input, MRB_ARGS_NONE());
  mrb_define_module_function(mrb, host, "audio_play", host_audio_play, MRB_ARGS_REQ(5));
  mrb_define_module_function(mrb, host, "audio_update", host_audio_update, MRB_ARGS_REQ(4));
  mrb_define_module_function(mrb, host, "audio_stop", host_audio_stop, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, host, "audio_finished", host_audio_finished, MRB_ARGS_NONE());
  mrb_define_module_function(mrb, host, "framerate", host_framerate, MRB_ARGS_NONE());
  mrb_define_module_function(mrb, host, "fatal", host_fatal, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, host, "read_file", host_read_file, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, host, "file_exist?", host_file_exist, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, host, "load", host_load, MRB_ARGS_REQ(1));

  struct RClass *ffi = mrb_define_class_under(mrb, host, "FFI", mrb->object_class);
  mrb_define_method(mrb, ffi, "draw_sprite_6", ffi_draw_sprite_6, MRB_ARGS_ANY());
}

// --- Entry points for host.js ---------------------------------------------------------------------------------

static void report_exception(mrb_value exception) {
  mrb_value message = mrb_funcall(mrb, runtime, "describe_exception", 1, exception);
  js_fatal(mrb_string_cstr(mrb, message));
}

static mrb_value boot_body(mrb_state *mrb, void *data) {
  load_ruby(mrb, PRELUDE_PATH, "web/runtime/dragonruby.rb");
  runtime = mrb_funcall(mrb, mrb_obj_value(mrb_class_get(mrb, "WebRuntime")), "new", 0);
  mrb_gc_register(mrb, runtime);
  return mrb_funcall(mrb, runtime, "boot", 0);
}

static mrb_value tick_body(mrb_state *mrb, void *data) {
  return mrb_funcall(mrb, runtime, "tick", 0);
}

// Returns 0, or 1 after reporting an exception through host.js
static int protected_call(mrb_protect_error_func *body) {
  int arena = mrb_gc_arena_save(mrb);
  mrb_bool failed = FALSE;
  mrb_value result = mrb_protect_error(mrb, body, NULL, &failed);
  if (failed) {
    if (mrb_nil_p(runtime)) {
      mrb_value message = mrb_inspect(mrb, result);
      js_fatal(mrb_string_cstr(mrb, message));
    }
    else {
      report_exception(result);
    }
  }
  mrb_gc_arena_restore(mrb, arena);
  return failed ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE int web_boot(void) {
  mrb = mrb_open();
  runtime = mrb_nil_value();
  define_web_host();
  return protected_call(boot_body);
}

// Runs one tick of the game and renders what it drew
EMSCRIPTEN_KEEPALIVE int web_tick(void) {
  command_count = 0;
  if (protected_call(tick_body)) return 1;
  js_render(commands, command_count);
  return 0;
}

static mrb_value eval_body(mrb_state *mrb, void *data) {
  return mrb_funcall(mrb, runtime, "evaluate", 1, mrb_str_new_cstr(mrb, (const char *)data));
}

static int last_eval_failed;

// Evaluates Ruby (for the browser console and tests) and returns its inspected result, or the exception it raised
// (see web_last_eval_failed). The caller frees the string.
EMSCRIPTEN_KEEPALIVE char *web_eval(const char *code) {
  int arena = mrb_gc_arena_save(mrb);
  mrb_bool failed = FALSE;
  mrb_value result = mrb_protect_error(mrb, eval_body, (void *)code, &failed);
  last_eval_failed = failed;
  mrb_value text = failed ? mrb_funcall(mrb, runtime, "describe_exception", 1, result) : mrb_inspect(mrb, result);
  char *copy = strdup(mrb_string_cstr(mrb, text));
  mrb_gc_arena_restore(mrb, arena);
  return copy;
}

EMSCRIPTEN_KEEPALIVE int web_last_eval_failed(void) {
  return last_eval_failed;
}

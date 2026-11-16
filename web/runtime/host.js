// The browser half of the web runtime: runs the game's ticks at 60 per second, renders the draw commands of each
// tick with WebGL2 the way DragonRuby renders them, plays sounds with Web Audio and collects keyboard, mouse and
// gamepad input. main.c calls the functions of Module.host; window.dr is for the browser console and tests.
//
// Loaded with emcc --pre-js, so Module, FS and HEAP* are in scope.

Module.host = (() => {
  const SCREEN_W = 1280;
  const SCREEN_H = 720;
  const TICK_MS = 1000 / 60;

  const COMMAND_TARGET = 1;
  const COMMAND_SPRITE = 2;
  const COMMAND_SHADER = 3;
  const COMMAND_SCREEN = 4;
  const SPRITE_FLOATS = 25;

  // --- Boot and the tick loop -----------------------------------------------------------------------------------

  let renderer = null;
  let audio = null;
  let input = null;
  let stopped = false;
  let paused = false;
  let framerate = 60;

  async function start() {
    const canvas = Module.canvas;
    renderer = new Renderer(canvas);
    audio = new Audio();
    input = new Input(canvas, renderer);
    renderer.loadShaders(readShaderManifests());
    await Promise.all([audio.load(gameFiles(/\.(wav|ogg|mp3)$/)), renderer.loadImages(gameFiles(/\.(png|jpe?g|gif|webp)$/))]);
    if (Module._web_boot() !== 0) return;
    await waitForClick();
    audio.resume();
    runLoop();
  }

  function runLoop() {
    let last = performance.now();
    let behind = 0;
    let setupPending = new URLSearchParams(location.search).get('setup');
    const frame = (now) => {
      if (stopped) return;
      requestAnimationFrame(frame);
      let elapsed = now - last;
      last = now;
      // A display at 60 Hz ticks once per frame despite jitter; faster ones skip frames, slower ones catch up
      if (Math.abs(elapsed - TICK_MS) < 1.5) elapsed = TICK_MS;
      behind = Math.min(behind + elapsed, TICK_MS * 3);
      while (!paused && behind >= TICK_MS - 0.01) {
        behind -= TICK_MS;
        if (!tick()) return;
        framerate = framerate * 0.95 + (1000 / Math.max(elapsed, 1)) * 0.05;
        if (setupPending) {
          runSetup(setupPending);
          setupPending = null;
        }
      }
    };
    requestAnimationFrame(frame);
  }

  // An exception thrown in here leaves mruby halfway through a call, so nothing may run after it
  function tick() {
    if (stopped) return false;
    try {
      return Module._web_tick() === 0;
    } catch (error) {
      fatal(error.stack || String(error));
      return false;
    }
  }

  // ?setup=autopilot runs GameCli.setup(:autopilot) after the first tick, like scripts/game reset autopilot
  function runSetup(name) {
    if (!/^[a-z_]+$/.test(name)) return console.error(`Invalid setup name: ${name}`);
    try {
      console.log(`GameCli.setup(:${name}) => ${evaluate(`GameCli.setup(:${name})`)}`);
    } catch (error) {
      console.error(`GameCli.setup(:${name}) failed: ${error.message}`);
    }
  }

  function waitForClick() {
    const overlay = document.getElementById('start');
    if (!overlay) return Promise.resolve();
    overlay.classList.add('ready');
    return new Promise((resolve) => {
      overlay.addEventListener('click', () => {
        overlay.remove();
        Module.canvas.focus();
        resolve();
      }, { once: true });
    });
  }

  function fatal(message) {
    stopped = true;
    console.error(message);
    const panel = document.getElementById('error');
    if (panel) {
      panel.textContent = message;
      panel.hidden = false;
    }
  }

  // Returns the inspected result, or throws the exception the Ruby raised
  function evaluate(code) {
    if (stopped) throw new Error('The game stopped after an error');
    const pointer = Module.ccall('web_eval', 'number', ['string'], [code]);
    const result = UTF8ToString(pointer);
    Module._free(pointer);
    if (Module._web_last_eval_failed()) throw new Error(result);
    return result;
  }

  // Every file of the game's folder whose path matches, relative to it
  function gameFiles(pattern) {
    const found = [];
    const walk = (directory) => {
      for (const name of FS.readdir(directory)) {
        if (name === '.' || name === '..') continue;
        const path = `${directory}/${name}`;
        if (FS.isDir(FS.stat(path).mode)) walk(path);
        else if (pattern.test(name)) found.push(path.slice('/game/'.length));
      }
    };
    walk('/game');
    return found;
  }

  // web/build writes one JSON file per shader next to where its .hlsl file was
  function readShaderManifests() {
    return gameFiles(/\.hlsl\.json$/).map((path) => JSON.parse(FS.readFile(`/game/${path}`, { encoding: 'utf8' })));
  }

  // --- Rendering --------------------------------------------------------------------------------------------------

  const SPRITE_VERTEX = `#version 300 es
    in vec2 a_position;
    in vec2 a_uv;
    in vec4 a_color;
    uniform vec2 u_size;
    uniform float u_flip;
    out vec2 v_uv;
    out vec4 v_color;
    void main() {
      vec2 ndc = a_position / u_size * 2.0 - 1.0;
      gl_Position = vec4(ndc.x, ndc.y * u_flip, 0.0, 1.0);
      v_uv = a_uv;
      v_color = a_color;
    }`;

  const SPRITE_FRAGMENT = `#version 300 es
    precision highp float;
    uniform sampler2D u_texture;
    in vec2 v_uv;
    in vec4 v_color;
    out vec4 color;
    void main() {
      color = texture(u_texture, v_uv) * v_color;
    }`;

  // Draws a sprite of a render target that has a shader: the shader gets the sprite's texture coordinate, with (0, 0)
  // at the target's top left corner, as TEXCOORD0 and the sprite's color as COLOR0 (the names come from web/build)
  const SHADED_SPRITE_VERTEX = `#version 300 es
    in vec2 a_position;
    in vec2 a_uv;
    in vec4 a_color;
    uniform vec2 u_size;
    uniform float u_flip;
    out vec2 dr_tex_coord;
    out vec4 dr_tex_color;
    void main() {
      vec2 ndc = a_position / u_size * 2.0 - 1.0;
      gl_Position = vec4(ndc.x, ndc.y * u_flip, 0.0, 1.0);
      dr_tex_coord = a_uv;
      dr_tex_color = a_color;
    }`;

  const MAX_BATCH = 4096;
  const VERTEX_FLOATS = 8;

  // Textures keep their top row first, like DragonRuby's (Direct3D, Metal and Vulkan) textures: render targets are
  // drawn upside down by u_flip, pixel arrays and images are uploaded as they are.
  //
  // A render target's shader does not change the target. Like in DragonRuby, it is the fragment shader of every
  // sprite that shows the target, with the target as t0, sampled with the sprite's scale quality and blended with
  // its blend mode.
  class Renderer {
    constructor(canvas) {
      this.canvas = canvas;
      const gl = canvas.getContext('webgl2', { alpha: false, antialias: false, depth: false, premultipliedAlpha: false });
      if (!gl) throw new Error('This browser does not support WebGL2');
      this.gl = gl;
      this.textures = new Map();
      this.images = new Map();
      this.shaders = [];
      this.shaderIds = new Map();
      this.white = this.createTexture(1, 1, new Uint8Array([255, 255, 255, 255]));
      this.spriteProgram = this.createProgram(SPRITE_VERTEX, SPRITE_FRAGMENT, { a_position: 0, a_uv: 1, a_color: 2 });
      this.spriteSize = gl.getUniformLocation(this.spriteProgram, 'u_size');
      this.spriteFlip = gl.getUniformLocation(this.spriteProgram, 'u_flip');
      this.samplers = [gl.NEAREST, gl.LINEAR].map((filter) => {
        const sampler = gl.createSampler();
        gl.samplerParameteri(sampler, gl.TEXTURE_MIN_FILTER, filter);
        gl.samplerParameteri(sampler, gl.TEXTURE_MAG_FILTER, filter);
        gl.samplerParameteri(sampler, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.samplerParameteri(sampler, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        return sampler;
      });
      this.createSpriteBuffers();
      this.uniformBuffer = gl.createBuffer();
      this.letterbox = { x: 0, y: 0, w: SCREEN_W, h: SCREEN_H, cssX: 0, cssY: 0, cssW: SCREEN_W, cssH: SCREEN_H };
      this.batch = { count: 0, texture: null, blend: -1, filter: -1 };
    }

    createSpriteBuffers() {
      const gl = this.gl;
      this.vertices = new Float32Array(MAX_BATCH * 4 * VERTEX_FLOATS);
      this.spriteVao = gl.createVertexArray();
      gl.bindVertexArray(this.spriteVao);
      this.vertexBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vertexBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, this.vertices.byteLength, gl.DYNAMIC_DRAW);
      const stride = VERTEX_FLOATS * 4;
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0);
      gl.enableVertexAttribArray(1);
      gl.vertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8);
      gl.enableVertexAttribArray(2);
      gl.vertexAttribPointer(2, 4, gl.FLOAT, false, stride, 16);
      const indices = new Uint16Array(MAX_BATCH * 6);
      for (let i = 0; i < MAX_BATCH; i++) {
        indices.set([i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3], i * 6);
      }
      const indexBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
      gl.bindVertexArray(null);
    }

    createProgram(vertexSource, fragmentSource, attributes) {
      const gl = this.gl;
      const compile = (type, source) => {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
        return shader;
      };
      const program = gl.createProgram();
      gl.attachShader(program, compile(gl.VERTEX_SHADER, vertexSource));
      gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragmentSource));
      for (const [name, location] of Object.entries(attributes)) gl.bindAttribLocation(program, location, name);
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
      return program;
    }

    createTexture(w, h, pixels) {
      const gl = this.gl;
      const texture = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
      return { texture, w, h };
    }

    // --- Textures

    async loadImages(paths) {
      await Promise.all(paths.map(async (path) => {
        const blob = new Blob([FS.readFile(`/game/${path}`)]);
        this.images.set(path, await createImageBitmap(blob, { premultiplyAlpha: 'none', colorSpaceConversion: 'none' }));
      }));
    }

    registerTexture(id, name) {
      if (name === 'pixel' || name === 'solid') {
        this.textures.set(id, this.white);
        return;
      }
      const image = this.images.get(name);
      if (!image) return; // a render target or pixel array, created when it is first drawn or uploaded
      const gl = this.gl;
      const entry = this.createTexture(image.width, image.height, null);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, gl.RGBA, gl.UNSIGNED_BYTE, image);
      this.textures.set(id, entry);
    }

    uploadPixels(id, w, h, pixels) {
      const gl = this.gl;
      const existing = this.textures.get(id);
      if (existing && existing.w === w && existing.h === h && !existing.framebuffer) {
        gl.bindTexture(gl.TEXTURE_2D, existing.texture);
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        return;
      }
      this.textures.set(id, this.createTexture(w, h, pixels));
    }

    renderTarget(id, w, h) {
      let target = this.textures.get(id);
      if (!target || !target.framebuffer || target.w !== w || target.h !== h) {
        target = this.createFramebufferTexture(w, h);
        this.textures.set(id, target);
      }
      return target;
    }

    createFramebufferTexture(w, h) {
      const gl = this.gl;
      const entry = this.createTexture(w, h, null);
      entry.framebuffer = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, entry.framebuffer);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, entry.texture, 0);
      return entry;
    }

    // --- Shaders compiled by web/build

    loadShaders(manifests) {
      for (const manifest of manifests) {
        const program = this.createProgram(SHADED_SPRITE_VERTEX, manifest.glsl, { a_position: 0, a_uv: 1, a_color: 2 });
        const gl = this.gl;
        gl.useProgram(program);
        for (const [name, unit] of Object.entries(manifest.samplers)) {
          const location = gl.getUniformLocation(program, name);
          if (location) gl.uniform1i(location, unit);
        }
        let block = null;
        if (manifest.uniform_block) {
          const index = gl.getUniformBlockIndex(program, manifest.uniform_block.name);
          if (index !== gl.INVALID_INDEX) {
            gl.uniformBlockBinding(program, index, 0);
            block = { size: manifest.uniform_block.size };
          }
        }
        this.shaderIds.set(manifest.path, this.shaders.length);
        this.shaders.push({
          program,
          block,
          size: gl.getUniformLocation(program, 'u_size'),
          flip: gl.getUniformLocation(program, 'u_flip'),
        });
      }
    }

    shaderId(path) {
      const id = this.shaderIds.get(path);
      return id === undefined ? -1 : id;
    }

    // --- Commands

    render(commands) {
      const gl = this.gl;
      this.target = null;
      let i = 0;
      while (i < commands.length) {
        switch (commands[i]) {
          case COMMAND_TARGET:
            this.beginTarget(commands, i);
            i += 8;
            break;
          case COMMAND_SPRITE:
            this.sprite(commands, i);
            i += SPRITE_FLOATS;
            break;
          case COMMAND_SHADER:
            i = this.attachShader(commands, i);
            break;
          case COMMAND_SCREEN:
            this.beginScreen(commands, i);
            i += 5;
            break;
          default:
            throw new Error(`Unknown draw command ${commands[i]} at ${i}`);
        }
      }
      this.flush();
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    }

    beginTarget(c, i) {
      this.flush();
      const gl = this.gl;
      const target = this.renderTarget(c[i + 1], c[i + 2], c[i + 3]);
      target.shader = null;
      this.target = { w: target.w, h: target.h, flip: -1 };
      gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
      gl.viewport(0, 0, target.w, target.h);
      gl.disable(gl.SCISSOR_TEST);
      gl.clearColor(c[i + 4] / 255, c[i + 5] / 255, c[i + 6] / 255, c[i + 7] / 255);
      gl.clear(gl.COLOR_BUFFER_BIT);
    }

    // The screen is SCREEN_W x SCREEN_H, scaled to fit the canvas with black bars, like DragonRuby's window
    beginScreen(c, i) {
      this.flush();
      const gl = this.gl;
      this.resizeCanvas();
      const box = this.letterbox;
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.disable(gl.SCISSOR_TEST);
      gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      gl.clearColor(0, 0, 0, 1);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.enable(gl.SCISSOR_TEST);
      gl.scissor(box.x, box.y, box.w, box.h);
      gl.viewport(box.x, box.y, box.w, box.h);
      gl.clearColor(c[i + 1] / 255, c[i + 2] / 255, c[i + 3] / 255, 1);
      gl.clear(gl.COLOR_BUFFER_BIT);
      this.target = { w: SCREEN_W, h: SCREEN_H, flip: 1 };
    }

    resizeCanvas() {
      const canvas = this.canvas;
      const ratio = window.devicePixelRatio || 1;
      const cssW = canvas.clientWidth || SCREEN_W;
      const cssH = canvas.clientHeight || SCREEN_H;
      const w = Math.round(cssW * ratio);
      const h = Math.round(cssH * ratio);
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
      }
      const scale = Math.min(w / SCREEN_W, h / SCREEN_H);
      const boxW = Math.round(SCREEN_W * scale);
      const boxH = Math.round(SCREEN_H * scale);
      const x = Math.floor((w - boxW) / 2);
      const y = Math.floor((h - boxH) / 2);
      this.letterbox = { x, y, w: boxW, h: boxH, cssX: x / ratio, cssY: (h - y - boxH) / ratio, cssW: boxW / ratio, cssH: boxH / ratio };
    }

    sprite(c, i) {
      const entry = this.textures.get(c[i + 1]);
      if (!entry || !this.target) return;
      const blend = c[i + 2];
      const filter = c[i + 3] >= 1 ? 1 : 0;
      const batch = this.batch;
      if (batch.count === MAX_BATCH || batch.texture !== entry || batch.blend !== blend || batch.filter !== filter) {
        this.flush();
        batch.texture = entry;
        batch.blend = blend;
        batch.filter = filter;
      }
      const texW = entry.w;
      const texH = entry.h;
      // Source rectangle in texture pixels, top row first
      let sx = c[i + 17];
      let sy = c[i + 18];
      let sw = c[i + 19];
      let sh = c[i + 20];
      if (Number.isNaN(sx)) sx = 0;
      if (Number.isNaN(sw)) sw = texW - sx;
      if (Number.isNaN(sh)) sh = Number.isNaN(sy) ? texH : texH - sy;
      if (Number.isNaN(sy)) sy = 0;
      const top = c[i + 21] === 1 ? sy : texH - sy - sh;
      let u0 = sx / texW;
      let u1 = (sx + sw) / texW;
      let v0 = top / texH; // top edge of the sprite
      let v1 = (top + sh) / texH;
      if (c[i + 22] === 1) [u0, u1] = [u1, u0];
      if (c[i + 23] === 1) [v0, v1] = [v1, v0];

      let w = c[i + 6];
      let h = c[i + 7];
      if (Number.isNaN(w)) w = sw;
      if (Number.isNaN(h)) h = sh;
      const anchorX = Number.isNaN(c[i + 11]) ? 0 : c[i + 11];
      const anchorY = Number.isNaN(c[i + 12]) ? 0 : c[i + 12];
      const x0 = c[i + 4] - w * anchorX;
      const y0 = c[i + 5] - h * anchorY;
      const x1 = x0 + w;
      const y1 = y0 + h;
      const r = Number.isNaN(c[i + 13]) ? 1 : c[i + 13] / 255;
      const g = Number.isNaN(c[i + 14]) ? 1 : c[i + 14] / 255;
      const b = Number.isNaN(c[i + 15]) ? 1 : c[i + 15] / 255;
      const a = Number.isNaN(c[i + 16]) ? 1 : c[i + 16] / 255;

      // Corners counterclockwise from the bottom left, rotated counterclockwise around the angle anchor
      const corners = [x0, y0, x1, y0, x1, y1, x0, y1];
      const angle = c[i + 8];
      if (!Number.isNaN(angle) && angle !== 0) {
        const pivotX = x0 + w * (Number.isNaN(c[i + 9]) ? 0.5 : c[i + 9]);
        const pivotY = y0 + h * (Number.isNaN(c[i + 10]) ? 0.5 : c[i + 10]);
        const radians = (angle * Math.PI) / 180;
        const cos = Math.cos(radians);
        const sin = Math.sin(radians);
        for (let k = 0; k < 8; k += 2) {
          const dx = corners[k] - pivotX;
          const dy = corners[k + 1] - pivotY;
          corners[k] = pivotX + dx * cos - dy * sin;
          corners[k + 1] = pivotY + dx * sin + dy * cos;
        }
      }
      const uvs = [u0, v1, u1, v1, u1, v0, u0, v0];
      const out = this.vertices;
      let o = batch.count * 4 * VERTEX_FLOATS;
      for (let k = 0; k < 4; k++) {
        out[o] = corners[k * 2];
        out[o + 1] = corners[k * 2 + 1];
        out[o + 2] = uvs[k * 2];
        out[o + 3] = uvs[k * 2 + 1];
        out[o + 4] = r;
        out[o + 5] = g;
        out[o + 6] = b;
        out[o + 7] = a;
        o += VERTEX_FLOATS;
      }
      batch.count++;
    }

    flush() {
      const batch = this.batch;
      if (batch.count === 0) return;
      const gl = this.gl;
      const attached = batch.texture.shader;
      const sampler = this.samplers[batch.filter];
      if (attached) {
        const shader = attached.shader;
        gl.useProgram(shader.program);
        gl.uniform2f(shader.size, this.target.w, this.target.h);
        gl.uniform1f(shader.flip, this.target.flip);
        attached.textureIds.forEach((id, index) => {
          gl.activeTexture(gl.TEXTURE1 + index);
          gl.bindTexture(gl.TEXTURE_2D, (this.textures.get(id) || this.white).texture);
          gl.bindSampler(index + 1, sampler);
        });
        if (attached.uniforms) {
          gl.bindBuffer(gl.UNIFORM_BUFFER, this.uniformBuffer);
          gl.bufferData(gl.UNIFORM_BUFFER, attached.uniforms, gl.DYNAMIC_DRAW);
          gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, this.uniformBuffer);
        }
      } else {
        gl.useProgram(this.spriteProgram);
        gl.uniform2f(this.spriteSize, this.target.w, this.target.h);
        gl.uniform1f(this.spriteFlip, this.target.flip);
      }
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, batch.texture.texture);
      gl.bindSampler(0, sampler);
      this.applyBlend(batch.blend);
      gl.bindVertexArray(this.spriteVao);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vertexBuffer);
      gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.vertices, 0, batch.count * 4 * VERTEX_FLOATS);
      gl.drawElements(gl.TRIANGLES, batch.count * 6, gl.UNSIGNED_SHORT, 0);
      gl.bindVertexArray(null);
      if (attached) {
        for (let unit = 1; unit <= attached.textureIds.length; unit++) gl.bindSampler(unit, null);
      }
      batch.count = 0;
    }

    // DragonRuby's blendmode_enum, which are SDL's blend modes
    applyBlend(mode) {
      const gl = this.gl;
      if (mode === 0) {
        gl.disable(gl.BLEND);
        return;
      }
      gl.enable(gl.BLEND);
      gl.blendEquation(gl.FUNC_ADD);
      switch (mode) {
        case 2: // add: the destination's alpha stays as it is
          gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
          break;
        case 3: // mod
          gl.blendFuncSeparate(gl.ZERO, gl.SRC_COLOR, gl.ZERO, gl.ONE);
          break;
        case 4: // mul
          gl.blendFuncSeparate(gl.DST_COLOR, gl.ONE_MINUS_SRC_ALPHA, gl.ZERO, gl.ONE);
          break;
        default: // blend: stores premultiplied color in a target cleared to transparent
          gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      }
    }

    // The shader, textures (t1, t2, ...) and uniforms that draw a render target until it is rendered again; the
    // uniforms fill the shader's uniform block in order, like DragonRuby's cbuffer
    attachShader(c, i) {
      this.flush();
      const target = this.textures.get(c[i + 1]);
      const shader = this.shaders[c[i + 2]];
      const textureCount = c[i + 3];
      const uniformStart = i + 4 + textureCount;
      const uniformCount = c[uniformStart];
      let uniforms = null;
      if (shader.block) {
        uniforms = new ArrayBuffer(Math.max(shader.block.size, uniformCount * 4));
        const floats = new Float32Array(uniforms);
        const ints = new Int32Array(uniforms);
        for (let u = 0; u < uniformCount; u++) {
          const value = c[uniformStart + 2 + u * 2];
          if (c[uniformStart + 1 + u * 2] === 1) ints[u] = value;
          else floats[u] = value;
        }
      }
      target.shader = { shader, textureIds: Array.from(c.subarray(i + 4, uniformStart)), uniforms };
      return uniformStart + 1 + uniformCount * 2;
    }
  }

  // --- Audio ------------------------------------------------------------------------------------------------------

  class Audio {
    constructor() {
      this.context = new AudioContext();
      this.buffers = new Map();
      this.voices = new Map();
      this.finishedIds = [];
    }

    async load(paths) {
      await Promise.all(paths.map(async (path) => {
        const bytes = FS.readFile(`/game/${path}`);
        try {
          this.buffers.set(path, await this.context.decodeAudioData(bytes.slice().buffer));
        } catch (error) {
          console.warn(`Could not decode ${path}: ${error}`);
        }
      }));
    }

    resume() {
      this.context.resume();
    }

    play(id, path, gain, pitch, looping) {
      const buffer = this.buffers.get(path);
      if (!buffer) {
        console.warn(`No sound ${path}`);
        this.finishedIds.push(id);
        return;
      }
      const source = this.context.createBufferSource();
      source.buffer = buffer;
      source.loop = looping;
      source.playbackRate.value = pitch;
      const volume = this.context.createGain();
      volume.gain.value = gain;
      source.connect(volume).connect(this.context.destination);
      source.onended = () => {
        if (this.voices.get(id)?.source !== source) return;
        this.voices.delete(id);
        this.finishedIds.push(id);
      };
      source.start();
      this.voices.set(id, { source, volume, pitch });
    }

    update(id, gain, pitch, paused) {
      const voice = this.voices.get(id);
      if (!voice) return;
      voice.volume.gain.value = paused ? 0 : gain;
      voice.source.playbackRate.value = paused ? 0 : pitch;
    }

    stop(id) {
      const voice = this.voices.get(id);
      if (!voice) return;
      this.voices.delete(id);
      voice.source.onended = null;
      voice.source.stop();
    }

    finished() {
      const ids = this.finishedIds.join(' ');
      this.finishedIds = [];
      return ids;
    }
  }

  // --- Input ------------------------------------------------------------------------------------------------------

  const KEY_NAMES = {
    Space: 'space', Enter: 'enter', NumpadEnter: 'enter', Escape: 'escape', Backspace: 'backspace', Tab: 'tab',
    Delete: 'delete', ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down',
    ShiftLeft: 'shift', ShiftRight: 'shift', ControlLeft: 'control', ControlRight: 'control', AltLeft: 'alt',
    AltRight: 'alt', MetaLeft: 'meta', MetaRight: 'meta', Minus: 'hyphen', Equal: 'equal_sign', Comma: 'comma',
    Period: 'period', Slash: 'forward_slash', Backslash: 'back_slash', Semicolon: 'semicolon', Quote: 'single_quotation_mark',
    BracketLeft: 'open_square_brace', BracketRight: 'close_square_brace', Backquote: 'backtick',
    PageUp: 'pageup', PageDown: 'pagedown', Home: 'home', End: 'end',
  };
  const DIGITS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];

  // DragonRuby names a letter key by its character and by its position (w_scancode is W on QWERTY, Z on AZERTY)
  function keyNames(event) {
    const code = event.code;
    if (KEY_NAMES[code]) return [KEY_NAMES[code]];
    if (/^Key[A-Z]$/.test(code)) {
      const names = [`${code.slice(3).toLowerCase()}_scancode`];
      const character = event.key.toLowerCase();
      names.push(/^[a-z]$/.test(character) ? character : code.slice(3).toLowerCase());
      return names;
    }
    if (/^(Digit|Numpad)[0-9]$/.test(code)) return [DIGITS[Number(code.slice(-1))]];
    if (/^F[0-9]+$/.test(code)) return [code.toLowerCase()];
    return [];
  }

  // Standard gamepad mapping, named like DragonRuby's controller keys
  const BUTTON_NAMES = ['a', 'b', 'x', 'y', 'l1', 'r1', 'l2', 'r2', 'select', 'start', 'l3', 'r3', 'up', 'down', 'left', 'right', 'home'];
  const STICK_THRESHOLD = 0.5;

  class Input {
    constructor(canvas, renderer) {
      this.canvas = canvas;
      this.renderer = renderer;
      this.held = new Map(); // code -> names
      this.pressed = new Set();
      this.released = new Set();
      this.mouse = { x: 0, y: 0, moved: false, left: false, middle: false, right: false, leftDown: false, leftUp: false };
      this.padHeld = new Set();
      window.addEventListener('keydown', (event) => this.keyDown(event));
      window.addEventListener('keyup', (event) => this.keyUp(event));
      window.addEventListener('blur', () => this.releaseAll());
      canvas.addEventListener('pointermove', (event) => this.pointerMove(event));
      canvas.addEventListener('pointerdown', (event) => this.pointerButton(event, true));
      window.addEventListener('pointerup', (event) => this.pointerButton(event, false));
      canvas.addEventListener('contextmenu', (event) => event.preventDefault());
    }

    keyDown(event) {
      // Browser shortcuts keep working; everything else belongs to the game
      if (event.metaKey || event.ctrlKey || event.code === 'F5' || event.code === 'F12') return;
      event.preventDefault();
      if (event.repeat || this.held.has(event.code)) return;
      const names = keyNames(event);
      this.held.set(event.code, names);
      names.forEach((name) => this.pressed.add(name));
    }

    keyUp(event) {
      const names = this.held.get(event.code);
      if (!names) return;
      this.held.delete(event.code);
      names.forEach((name) => this.released.add(name));
    }

    releaseAll() {
      for (const names of this.held.values()) names.forEach((name) => this.released.add(name));
      this.held.clear();
    }

    pointerMove(event) {
      const rect = this.canvas.getBoundingClientRect();
      const box = this.renderer.letterbox;
      this.mouse.x = Math.floor(((event.clientX - rect.left - box.cssX) / box.cssW) * SCREEN_W);
      this.mouse.y = Math.floor(SCREEN_H - ((event.clientY - rect.top - box.cssY) / box.cssH) * SCREEN_H);
      this.mouse.moved = true;
    }

    pointerButton(event, down) {
      if (down) this.pointerMove(event);
      const button = ['left', 'middle', 'right'][event.button];
      if (!button || this.mouse[button] === down) return;
      this.mouse[button] = down;
      if (button === 'left') {
        if (down) this.mouse.leftDown = true;
        else this.mouse.leftUp = true;
      }
    }

    // What changed since the previous tick, in the lines that Inputs#update in dragonruby.rb reads
    snapshot() {
      const heldNames = new Set();
      for (const names of this.held.values()) names.forEach((name) => heldNames.add(name));
      const keyHeld = [...heldNames].filter((name) => !this.pressed.has(name));
      const m = this.mouse;
      const lines = [
        `kd ${[...this.pressed].join(' ')}`,
        `kh ${keyHeld.join(' ')}`,
        `ku ${[...this.released].join(' ')}`,
        `m ${m.x} ${m.y} ${m.moved ? 1 : 0} ${m.leftDown ? 1 : 0} ${m.left ? 1 : 0} ${m.leftUp ? 1 : 0} ${m.middle ? 1 : 0} ${m.right ? 1 : 0}`,
        ...this.gamepadLines(),
      ];
      this.pressed.clear();
      this.released.clear();
      m.moved = false;
      m.leftDown = false;
      m.leftUp = false;
      return lines.join('\n');
    }

    gamepadLines() {
      const pad = [...(navigator.getGamepads ? navigator.getGamepads() : [])].find((gamepad) => gamepad && gamepad.connected);
      const now = new Set();
      let axes = [];
      if (pad) {
        pad.buttons.forEach((button, index) => {
          if (button.pressed && BUTTON_NAMES[index]) now.add(BUTTON_NAMES[index]);
        });
        ['left', 'right', 'up', 'down'].forEach((direction) => {
          if (now.has(direction)) now.add(`${direction}_dpad`);
        });
        const [lx = 0, ly = 0, rx = 0, ry = 0] = pad.axes;
        if (lx < -STICK_THRESHOLD) now.add('left');
        if (lx > STICK_THRESHOLD) now.add('right');
        if (ly < -STICK_THRESHOLD) now.add('up');
        if (ly > STICK_THRESHOLD) now.add('down');
        axes = [lx, -ly, rx, -ry];
      }
      const down = [...now].filter((name) => !this.padHeld.has(name));
      const held = [...now].filter((name) => this.padHeld.has(name));
      const up = [...this.padHeld].filter((name) => !now.has(name));
      this.padHeld = now;
      return [`cd ${down.join(' ')}`, `ch ${held.join(' ')}`, `cu ${up.join(' ')}`, `ca ${axes.join(' ')}`];
    }
  }

  // --- Browser console and tests ----------------------------------------------------------------------------------

  window.dr = {
    // Evaluates Ruby in the game and returns the inspected result, like scripts/game eval; throws what it raises
    eval: evaluate,
    pause() { paused = true; },
    resume() { paused = false; },
    // Runs ticks right away (while paused, for screenshots of an exact tick)
    step(count = 1) {
      for (let i = 0; i < count; i++) if (!tick()) return false;
      return true;
    },
  };

  Module.onRuntimeInitialized = () => {
    start().catch((error) => fatal(error.stack || String(error)));
  };

  return {
    render: (commands) => renderer.render(commands),
    registerTexture: (id, name) => renderer.registerTexture(id, name),
    uploadPixels: (id, w, h, pixels) => renderer.uploadPixels(id, w, h, pixels),
    shaderId: (path) => renderer.shaderId(path),
    input: () => input.snapshot(),
    audio: {
      play: (...args) => audio.play(...args),
      update: (...args) => audio.update(...args),
      stop: (id) => audio.stop(id),
      finished: () => audio.finished(),
    },
    framerate: () => framerate,
    fatal,
  };
})();

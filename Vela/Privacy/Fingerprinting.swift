import Foundation
import WebKit

/// Fingerprinting protection, the way Brave does it ("farbling").
///
/// **What fingerprinting is:** even with cookies blocked, a site can ask your
/// browser lots of small questions: draw this text on a hidden canvas and
/// read back the pixels, play a silent sound and measure it, how many CPU
/// cores do you have? Each answer alone means little, but together they're
/// nearly unique to your Mac, so trackers can recognize you anywhere.
///
/// **What Vela does:** it changes the answers very slightly. Canvas pixels
/// and audio samples get invisible noise, and hardware details report common
/// values. The noise is the same every time on one website (so sites keep
/// working), but different on every other website and every time Vela
/// starts, so the answers can't be matched up across sites or days.
///
/// WebKit already hides some things for us: it only reports system fonts,
/// rounds timers, and doesn't offer the battery or device-sensor APIs.
enum Fingerprinting {
    /// Changes every launch, so your fingerprint changes every launch too.
    private static let sessionSeed = UInt32.random(in: 1...UInt32.max)

    static func script(shieldsDownSites: Set<String>) -> WKUserScript {
        let sites = (try? JSONEncoder().encode(shieldsDownSites.sorted()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let source = """
        (() => {
          if (window.__velaFarble) return;
          window.__velaFarble = true;
          const host = location.hostname;
          const shieldsDown = \(sites);
          if (shieldsDown.some((s) => host === s || host.endsWith('.' + s))) return;

          // A number made from this launch's seed and the website's name.
          let seed = \(sessionSeed) >>> 0;
          const site = host.split('.').slice(-2).join('.');
          for (let i = 0; i < site.length; i++) seed = (Math.imul(seed ^ site.charCodeAt(i), 2654435761) >>> 0) || 1;
          // A small random-number generator that always starts from that seed,
          // so the same drawing gets the same noise on this site.
          const generator = () => {
            let s = seed;
            return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
          };

          // Keep our replacements looking like built-in functions.
          const nativeText = new WeakMap();
          const originalToString = Function.prototype.toString;
          const toString = function () {
            return nativeText.has(this) ? nativeText.get(this) : originalToString.call(this);
          };
          nativeText.set(toString, originalToString.call(originalToString));
          Function.prototype.toString = toString;
          const replace = (target, name, make) => {
            const original = target && target[name];
            if (typeof original !== 'function') return;
            const replacement = make(original);
            nativeText.set(replacement, originalToString.call(original));
            try { target[name] = replacement; } catch (e) {}
          };
          const getter = (target, name, value) => {
            try {
              const descriptor = Object.getOwnPropertyDescriptor(target, name);
              if (!descriptor || !descriptor.get) return;
              const get = function () { return value; };
              nativeText.set(get, originalToString.call(descriptor.get));
              Object.defineProperty(target, name, { ...descriptor, get });
            } catch (e) {}
          };

          // 1. Hardware: report what most Macs report.
          getter(Navigator.prototype, 'hardwareConcurrency', 8);
          getter(Navigator.prototype, 'deviceMemory', 8);

          // 2. Canvas: flip the lowest bit of a few pixels. Invisible to you,
          //    but it changes the "fingerprint" a tracker computes.
          const addNoise = (data) => {
            const random = generator();
            for (let i = 0; i < data.length; i += 4 * (1 + Math.floor(random() * 97))) {
              data[i + Math.floor(random() * 3)] ^= 1;
            }
          };
          const proto2D = window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype;
          const originalGetImageData = proto2D && proto2D.getImageData;
          replace(proto2D, 'getImageData', (original) => function (...args) {
            const image = original.apply(this, args);
            try { addNoise(image.data); } catch (e) {}
            return image;
          });
          const noisyCopy = (canvas) => {
            try {
              const w = canvas.width, h = canvas.height;
              if (!w || !h || w * h > 4000000 || !originalGetImageData) return canvas;
              const copy = document.createElement('canvas');
              copy.width = w; copy.height = h;
              const context = copy.getContext('2d');
              context.drawImage(canvas, 0, 0);
              const image = originalGetImageData.call(context, 0, 0, w, h);
              addNoise(image.data);
              context.putImageData(image, 0, 0);
              return copy;
            } catch (e) { return canvas; }
          };
          const protoCanvas = window.HTMLCanvasElement && HTMLCanvasElement.prototype;
          replace(protoCanvas, 'toDataURL', (original) => function (...args) {
            return original.apply(noisyCopy(this), args);
          });
          replace(protoCanvas, 'toBlob', (original) => function (...args) {
            return original.apply(noisyCopy(this), args);
          });

          // 3. WebGL: read-back pixels get the same noise.
          for (const name of ['WebGLRenderingContext', 'WebGL2RenderingContext']) {
            const proto = window[name] && window[name].prototype;
            replace(proto, 'readPixels', (original) => function (...args) {
              const result = original.apply(this, args);
              const pixels = args[6];
              if (pixels && pixels.length) { try { addNoise(pixels); } catch (e) {} }
              return result;
            });
          }

          // 4. Audio: a tiny, inaudible change to measured sound.
          const touched = new WeakSet();
          const protoBuffer = window.AudioBuffer && AudioBuffer.prototype;
          replace(protoBuffer, 'getChannelData', (original) => function (...args) {
            const samples = original.apply(this, args);
            if (!touched.has(samples)) {
              touched.add(samples);
              const random = generator();
              for (let i = 0; i < samples.length; i += 100) samples[i] += (random() - 0.5) * 1e-7;
            }
            return samples;
          });
          const protoAnalyser = window.AnalyserNode && AnalyserNode.prototype;
          replace(protoAnalyser, 'getFloatFrequencyData', (original) => function (array) {
            original.call(this, array);
            const random = generator();
            for (let i = 0; i < array.length; i += 10) array[i] += (random() - 0.5) * 0.1;
          });
        })();
        """
        // Runs in the page's own world (that's where the page's code reads
        // these values), in every frame, before the page's scripts.
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}

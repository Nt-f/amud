// Plays HLS where the browser can't (Firefox, older desktop Chrome):
// setting a video's src to an .m3u8 playlist plays it through hls.js
// (hls.light.min.js, Apache-2.0, see LICENSE) instead. video_player_web
// just sets src, so this needs nothing from it. Loaded with hls.js by
// lib/features/gemara/daf_video_codec_web.dart the first time a video opens.
(function () {
  if (!window.Hls || !Hls.isSupported() || document.createElement('video').canPlayType('application/vnd.apple.mpegurl')) return;
  var src = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');

  function detach(media) {
    if (media._hls) media._hls.destroy();
    media._hls = null;
  }

  Object.defineProperty(HTMLMediaElement.prototype, 'src', {
    configurable: true,
    enumerable: src.enumerable,
    get: src.get,
    set: function (value) {
      // hls.js itself sets src to its MediaSource's blob: URL.
      if (!/\.m3u8(\?|#|$)/.test(String(value))) return src.set.call(this, value);
      detach(this);
      var media = this, hls = new Hls(), recovered = false;
      media._hls = hls;
      hls.on(Hls.Events.ERROR, function (_, data) {
        if (!data.fatal) return;
        if (data.type === Hls.ErrorTypes.MEDIA_ERROR && !recovered) {
          recovered = true;
          hls.recoverMediaError();
          return;
        }
        console.warn('hls.js:', data.details);
        detach(media);
        // The browser can't play the playlist itself, so the video reports
        // an error, and video_player with it.
        src.set.call(media, value);
      });
      if (!this._hlsEmptied) {
        this._hlsEmptied = true;
        // video_player_web disposes of a video by removing its src.
        this.addEventListener('emptied', function () {
          if (this._hls && !/^blob:/.test(src.get.call(this))) detach(this);
        });
      }
      hls.loadSource(value);
      hls.attachMedia(this);
    },
  });
})();

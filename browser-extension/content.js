(() => {
  let last = "";
  // Content-script files share the page's isolated global object, but Firefox
  // does not expose a property created by an earlier file as a bare identifier.
  const defaultHosts = globalThis.FURRPC_DEFAULT_HOSTS || [];
  let allowedHosts = [...defaultHosts];
  let showBrowsing = false;
  const musicHosts = new Set(["music.youtube.com", "soundcloud.com", "open.spotify.com", "music.apple.com", "music.amazon.com", "tidal.com", "deezer.com", "pandora.com", "bandcamp.com", "mixcloud.com"]);

  chrome.storage.local.get(["enabledHosts", "showBrowsing"], settings => {
    if (Array.isArray(settings.enabledHosts)) allowedHosts = settings.enabledHosts;
    showBrowsing = settings.showBrowsing === true;
    report();
  });
  chrome.storage.onChanged.addListener(changes => {
    if (changes.enabledHosts) {
      allowedHosts = Array.isArray(changes.enabledHosts.newValue) ? changes.enabledHosts.newValue : [...defaultHosts];
      last = "";
      report();
    }
    if (changes.showBrowsing) {
      showBrowsing = changes.showBrowsing.newValue === true;
      last = "";
      report();
    }
  });

  const serviceName = () => {
    const host = location.hostname.replace(/^www\./, "");
    const known = {
      "youtube.com": "YouTube", "music.youtube.com": "YouTube Music",
      "netflix.com": "Netflix", "soundcloud.com": "SoundCloud",
      "open.spotify.com": "Spotify", "twitch.tv": "Twitch",
      "disneyplus.com": "Disney+", "primevideo.com": "Prime Video",
      "amazon.com": "Amazon Music", "music.apple.com": "Apple Music",
      "max.com": "Max", "hulu.com": "Hulu", "paramountplus.com": "Paramount+",
      "peacocktv.com": "Peacock", "crunchyroll.com": "Crunchyroll",
      "bandcamp.com": "Bandcamp", "mixcloud.com": "Mixcloud", "vimeo.com": "Vimeo"
    };
    return known[host] || host.split(".").slice(0, -1).join(" ").replace(/\b\w/g, c => c.toUpperCase()) || "Browser Media";
  };

  const cleanTitle = (service) => {
    let title = document.title || service;
    for (const suffix of [" - YouTube", " | Netflix", " | SoundCloud", " - Twitch", " | Spotify"]) {
      if (title.endsWith(suffix)) title = title.slice(0, -suffix.length);
    }
    return title.trim().slice(0, 128) || service;
  };

  const text = selectors => {
    for (const selector of selectors) {
      const value = document.querySelector(selector)?.textContent?.trim();
      if (value) return value.replace(/\s+/g, " ").slice(0, 128);
    }
    return "";
  };

  const mediaMetadata = () => {
    try { return navigator.mediaSession?.metadata || null; }
    catch (_) { return null; }
  };

  const mediaTitle = (host, service) => {
    if (musicHosts.has(host)) {
      const metadataTitle = mediaMetadata()?.title?.trim();
      if (metadataTitle && metadataTitle !== service) return metadataTitle.slice(0, 128);
      const playerTitle = text([
        "ytmusic-player-bar .title.ytmusic-player-bar",
        "[data-testid='context-item-info-title']",
        ".playbackSoundBadge__titleLink",
        ".lcd__track-name", ".track-title", ".now-playing__title"
      ]);
      if (playerTitle) return playerTitle;
    }
    return cleanTitle(service);
  };

  const creator = host => {
    if (musicHosts.has(host)) {
      const metadataArtist = mediaMetadata()?.artist?.trim();
      if (metadataArtist) return metadataArtist.slice(0, 128);
      const playerArtist = text([
        "ytmusic-player-bar .byline a:first-of-type",
        "[data-testid='context-item-info-artist']",
        ".playbackSoundBadge__lightLink",
        ".lcd__sub-copy a:first-of-type", ".track-artist", ".now-playing__artist"
      ]);
      if (playerArtist) return playerArtist;
    }
    if (host === "youtube.com") {
      return text(["ytd-watch-metadata #owner #channel-name a", "#upload-info #channel-name a", "yt-formatted-string.ytd-channel-name a"]);
    }
    return text(["[itemprop='author'] [itemprop='name']", "[itemprop='author']", ".artist-name", ".creator-name", ".author-name", "[rel='author']"]);
  };

  const absoluteImage = value => {
    if (!value) return "";
    try {
      const url = new URL(value, location.href);
      return url.protocol === "https:" || url.protocol === "http:" ? url.href.slice(0, 2048) : "";
    } catch (_) { return ""; }
  };

  const artwork = active => {
    const host = location.hostname.replace(/^www\./, "");
    if (musicHosts.has(host)) {
      const covers = mediaMetadata()?.artwork || [];
      for (const cover of [...covers].reverse()) {
        const found = absoluteImage(cover?.src);
        if (found) return found;
      }
      for (const selector of [
        "ytmusic-player-bar #song-image img", "ytmusic-player-bar img.image",
        "[data-testid='cover-art-image']", ".playbackSoundBadge__avatar img",
        ".lcd__artwork img", ".now-playing img", ".player-artwork img"
      ]) {
        const image = document.querySelector(selector);
        const found = absoluteImage(image?.currentSrc || image?.src);
        if (found) return found;
      }
    }
    // YouTube's SPA metadata can be missing or stale after navigating between
    // videos. Its video ID gives us a stable, publicly fetchable thumbnail.
    if (host === "youtube.com" || host === "music.youtube.com") {
      const videoID = new URLSearchParams(location.search).get("v") || location.pathname.match(/^\/shorts\/([^/?]+)/)?.[1];
      if (/^[A-Za-z0-9_-]{11}$/.test(videoID || "")) return `https://i.ytimg.com/vi/${videoID}/hqdefault.jpg`;
    }
    for (const selector of ["meta[property='og:image:secure_url']", "meta[property='og:image']", "meta[name='twitter:image']", "meta[itemprop='thumbnailUrl']", "link[itemprop='thumbnailUrl']"]) {
      const element = document.querySelector(selector);
      const found = absoluteImage(element?.content || element?.href);
      if (found) return found;
    }
    const poster = absoluteImage(active?.poster);
    if (poster) return poster;
    let best = null;
    for (const image of document.images) {
      const rect = image.getBoundingClientRect();
      if (rect.width < 160 || rect.height < 120 || rect.bottom < 0 || rect.top > innerHeight) continue;
      if (!best || rect.width * rect.height > best.area) best = { url: image.currentSrc || image.src, area: rect.width * rect.height };
    }
    return absoluteImage(best?.url);
  };

  const report = () => {
    const host = location.hostname.replace(/^www\./, "").toLowerCase();
    const allowed = allowedHosts.some(item => host === item || host.endsWith("." + item));
    const media = [...document.querySelectorAll("video, audio")];
    const active = allowed ? media.find(m => !m.paused && !m.ended && m.readyState >= 2) : null;
    const service = serviceName();
    const browsing = allowed && showBrowsing && !active && document.visibilityState === "visible";
    const data = {
      playing: !!active,
      browsing,
      service,
      title: mediaTitle(host, service),
      subtitle: creator(host),
      image: artwork(active),
      kind: musicHosts.has(host) || active?.tagName?.toLowerCase() === "audio" ? "audio" : "video",
      position: active && Number.isFinite(active.currentTime) ? active.currentTime : 0,
      duration: active && Number.isFinite(active.duration) ? active.duration : 0
    };
    const signature = JSON.stringify(data);
    if (signature !== last) {
      last = signature;
      try {
        const pending = chrome.runtime.sendMessage({ type: "furrpc-media", data });
        if (pending && pending.catch) pending.catch(() => {});
      } catch (_) {}
    }
  };

  addEventListener("play", report, true);
  addEventListener("pause", report, true);
  addEventListener("ended", report, true);
  addEventListener("popstate", report, true);
  addEventListener("visibilitychange", report, true);
  setInterval(report, 4000);
  report();
})();

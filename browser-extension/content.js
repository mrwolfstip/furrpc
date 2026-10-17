(() => {
  let last = "";
  let lastSent = 0;
  const inFrame = window !== window.top;
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
    const match = Object.keys(known).filter(key => host === key || host.endsWith("." + key)).sort((a, b) => b.length - a.length)[0];
    if (match) return known[match];
    return host.split(".").slice(0, -1).join(" ").replace(/\b\w/g, c => c.toUpperCase()) || "Browser Media";
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

  const cssImage = selectors => {
    for (const selector of selectors) {
      const element = document.querySelector(selector);
      if (!element) continue;
      const match = getComputedStyle(element).backgroundImage.match(/^url\(["']?(.*?)["']?\)$/);
      const found = absoluteImage(match?.[1]);
      if (found) return found;
    }
    return "";
  };

  // "3:21", "1:02:03" and remaining-time labels such as "-3:21"
  const clockTokens = value => (String(value || "").match(/[-−]?\d{1,3}(?::\d{2}){1,2}(?!\d)/g) || []).map(token => {
    const remaining = /^[-−]/.test(token);
    const parts = token.replace(/^[-−]/, "").split(":").map(Number);
    return { seconds: parts.reduce((total, part) => total * 60 + part, 0), remaining };
  });

  const clock = value => clockTokens(value)[0]?.seconds || 0;

  // first is the elapsed time. a negative second token is time remaining, so
  // duration = position + remaining.
  const pairFromTokens = (first, other) => {
    if (!first || !other || first.remaining) return null;
    const duration = other.remaining ? first.seconds + other.seconds : other.seconds;
    return duration > 0 && first.seconds <= duration + 1 ? { position: first.seconds, duration } : null;
  };

  const spoken = value => {
    let total = 0;
    let found = false;
    for (const [, amount, unit] of String(value || "").matchAll(/(\d+(?:\.\d+)?)\s*(hour|minute|second)s?/gi)) {
      found = true;
      total += Number(amount) * { hour: 3600, minute: 60, second: 1 }[unit.toLowerCase()];
    }
    return found ? total : null;
  };

  const number = value => {
    const parsed = parseFloat(value);
    return Number.isFinite(parsed) ? parsed : null;
  };

  const rawText = selectors => {
    for (const selector of selectors) {
      for (const node of document.querySelectorAll(selector)) {
        const value = node.textContent?.trim();
        if (value) return value.replace(/\s+/g, " ").slice(0, 64);
      }
    }
    return "";
  };

  const hostIs = (host, key) => host === key || host.endsWith("." + key);

  // exact selectors for known players. combined holds "1:23 / 4:56" in one node.
  // selectors marked best-effort could not be checked against the live site.
  const siteClocks = [
    ["music.youtube.com", { combined: ["ytmusic-player-bar .time-info"] }],
    ["youtube.com", { elapsed: [".ytp-time-current"], total: [".ytp-time-duration"] }],
    ["open.spotify.com", { elapsed: ["[data-testid='playback-position']"], total: ["[data-testid='playback-duration']"] }],
    ["music.apple.com", { elapsed: ["[class*='time-elapsed' i]", "[class*='elapsed' i]"], total: ["[class*='time-remaining' i]", "[class*='remaining' i]", "[class*='duration' i]"] }],
    ["music.amazon.com", { elapsed: ["[class*='currentTime' i]", "[class*='elapsed' i]"], total: ["[class*='duration' i]", "[class*='remaining' i]"] }],
    ["tidal.com", { elapsed: ["[data-test='current-time']"], total: ["[data-test='duration']"] }],
    ["deezer.com", { elapsed: [".slider-counter-current"], total: [".slider-counter-max"] }],
    ["pandora.com", { elapsed: ["[data-qa='elapsed_time']"], total: ["[data-qa='remaining_time']"] }],
    ["bandcamp.com", { elapsed: [".time_elapsed"], total: [".time_total"] }],
    ["mixcloud.com", { elapsed: ["[class*='elapsed' i]", "[class*='current-time' i]"], total: ["[class*='duration' i]", "[class*='remaining' i]"] }],
    ["twitch.tv", { elapsed: ["[data-a-target='player-seekbar-current-time']"], total: ["[data-a-target='player-seekbar-duration']"] }],
    ["primevideo.com", { combined: [".atvwebplayersdk-timeindicator-text"] }]
  ];

  const playerBox = "[class*='player' i], [class*='control' i], [class*='playback' i], [class*='transport' i], [id*='player' i], [data-testid*='player' i], [data-testid*='playback' i], [data-uia*='control' i], ytmusic-player-bar";
  const notTime = /volume|\bvol\b|mute|sound|speed|rate|zoom|brightness|quality|caption|subtitle|font|opacity|gain|balance|equali[sz]er|bass|treble/i;
  const notTimeBox = "[class*='volume' i], [data-testid*='volume' i], [aria-label*='volume' i], [class*='speed' i], [class*='quality' i]";

  const readSiteClocks = host => {
    for (const [key, config] of siteClocks) {
      if (!hostIs(host, key)) continue;
      let pair = null;
      if (config.combined) {
        const tokens = clockTokens(rawText(config.combined));
        pair = pairFromTokens(tokens[0], tokens[1]);
      } else {
        pair = pairFromTokens(clockTokens(rawText(config.elapsed))[0], clockTokens(rawText(config.total))[0]);
      }
      if (pair) return pair;
    }
    // any other site: a lone clock label inside a player or controls container
    const find = pattern => [...document.querySelectorAll("[class], [data-testid], [data-test], [data-qa]")]
      .filter(node => !node.children.length && /^[-−]?\d{1,3}(:\d{2}){1,2}$/.test(node.textContent.trim()) &&
        pattern.test(`${node.className?.baseVal ?? node.className} ${node.getAttribute("data-testid") || ""} ${node.getAttribute("data-test") || ""} ${node.getAttribute("data-qa") || ""}`) &&
        node.closest(playerBox) && node.getClientRects().length)[0];
    const elapsed = find(/elapsed|current[-_ ]?time|time[-_ ]?passed|position/i);
    const total = find(/remaining|duration|total|time[-_ ]?left/i);
    return elapsed && total ? pairFromTokens(clockTokens(elapsed.textContent)[0], clockTokens(total.textContent)[0]) : null;
  };

  // role=slider, input[type=range] and progress elements inside a player
  const readScrubber = () => {
    for (const node of document.querySelectorAll("[role='slider'], input[type='range'], progress, #progress-bar")) {
      if (!node.getClientRects().length || !node.closest(playerBox) || node.closest(notTimeBox)) continue;
      const label = [node.getAttribute("aria-label"), node.getAttribute("title"), node.getAttribute("name"), node.id, node.className?.baseVal ?? node.className].join(" ");
      if (notTime.test(label)) continue;
      const parts = (node.getAttribute("aria-valuetext") || "").split(/\s+(?:of|\/)\s+/i);
      if (parts.length === 2) {
        const [a, b] = parts.map(part => clockTokens(part)[0] || (spoken(part) != null ? { seconds: spoken(part), remaining: false } : null));
        const pair = pairFromTokens(a, b);
        if (pair) return pair;
      }
      const now = number(node.getAttribute("aria-valuenow")) ?? number(node.value);
      const max = number(node.getAttribute("aria-valuemax")) ?? number(node.max);
      // 1, 100, 1000 and 10000 are almost always percentages or milliseconds, not seconds
      if (now == null || max == null || max <= 0 || now < 0 || now > max + 1) continue;
      if ([1, 100, 1000, 10000].includes(max) || max > 43200) continue;
      return { position: now, duration: max };
    }
    return null;
  };

  const previewBox = "ytd-video-preview, ytd-moving-thumbnail-renderer, [class*='hover-preview' i], [class*='preview-player' i], [class*='previewModal' i], [data-uia='billboard-row'], .billboard, .billboard-row";

  // among playing media prefer a visible one, then one that is not a muted loop,
  // then one with a finite duration, then the longest.
  const pickMedia = (host, media) => {
    const music = musicHosts.has(host);
    const candidates = media.filter(m => !m.paused && !m.ended && m.readyState >= 2 && !m.closest(previewBox)).map(m => {
      let visible = true;
      if (m.tagName === "VIDEO" && !music) {
        const rect = m.getBoundingClientRect();
        const style = getComputedStyle(m);
        visible = rect.width >= 160 && rect.height >= 90 && style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) !== 0;
      }
      return { m, visible, ambient: m.muted && m.loop, finite: Number.isFinite(m.duration) && m.duration > 0 };
    }).filter(c => c.visible);
    candidates.sort((a, b) => (a.ambient - b.ambient) || (b.finite - a.finite) || ((b.finite ? b.m.duration : 0) - (a.finite ? a.m.duration : 0)));
    return candidates[0]?.m || null;
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
      if (host === "soundcloud.com") {
        const found = cssImage([".playbackSoundBadge__avatar .sc-artwork", ".playbackSoundBadge__avatar span", ".playbackSoundBadge__avatar"]);
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
    const active = allowed ? pickMedia(host, media) : null;
    const soundCloudButton = host === "soundcloud.com" ? document.querySelector(".playControls__play, .playControl") : null;
    const soundCloudPlaying = allowed && !!soundCloudButton && (
      soundCloudButton.classList.contains("playing") ||
      /pause/i.test(soundCloudButton.getAttribute("aria-label") || soundCloudButton.getAttribute("title") || "")
    );
    const playing = !!active || soundCloudPlaying;
    const service = serviceName();
    // embedded frames never report "browsing"; only the top page does
    const browsing = allowed && showBrowsing && !playing && !inFrame && document.visibilityState === "visible";
    let position = active && Number.isFinite(active.currentTime) ? active.currentTime : 0;
    let duration = active && Number.isFinite(active.duration) && active.duration > 0 ? active.duration : 0;
    let live = false;
    if (playing && !duration) {
      // no usable media duration: soundcloud as before, then scrubbers, then clock text
      const soundCloudPair = soundCloudPlaying ? pairFromTokens(
        clockTokens(text([".playbackTimeline__timePassed span:last-child", ".playbackTimeline__timePassed"]))[0],
        clockTokens(text([".playbackTimeline__duration span:last-child", ".playbackTimeline__duration"]))[0]) : null;
      let found = soundCloudPair;
      if (!found) {
        const scrub = readScrubber();
        const clocks = readSiteClocks(host);
        // clock text wins when it disagrees with a scrubber (units can differ)
        found = scrub && (!clocks || Math.abs(scrub.duration - clocks.duration) <= 2) ? scrub : clocks;
      }
      if (found) {
        position = found.position;
        duration = found.duration;
      } else if (active && active.duration === Infinity) {
        live = true;
      }
    }
    const rate = active && Number.isFinite(active.playbackRate) && active.playbackRate > 0 ? active.playbackRate : 1;
    const data = {
      playing,
      browsing,
      service,
      title: mediaTitle(host, service),
      subtitle: creator(host),
      image: artwork(active),
      kind: musicHosts.has(host) || active?.tagName?.toLowerCase() === "audio" ? "audio" : "video",
      position: Math.round(position * 10) / 10,
      duration: Math.round(duration * 10) / 10,
      rate
    };
    if (live) data.live = true;
    const signature = JSON.stringify(data);
    const now = Date.now();
    // resend an unchanged state every 8 s so the app and background page keep it fresh
    if (signature !== last || ((playing || browsing) && now - lastSent > 8000)) {
      last = signature;
      lastSent = now;
      try {
        const pending = chrome.runtime.sendMessage({ type: "furrpc-media", data });
        if (pending && pending.catch) pending.catch(() => {});
      } catch (_) {}
    }
  };

  // seeks, track changes and speed changes should reach discord right away
  let scheduled = 0;
  const soon = () => {
    clearTimeout(scheduled);
    scheduled = setTimeout(report, 120);
  };

  addEventListener("play", report, true);
  addEventListener("pause", report, true);
  addEventListener("ended", report, true);
  addEventListener("popstate", report, true);
  addEventListener("visibilitychange", report, true);
  for (const name of ["seeked", "durationchange", "loadedmetadata", "playing", "ratechange"]) addEventListener(name, soon, true);
  setInterval(report, 4000);
  report();
})();

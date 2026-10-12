globalThis.FURRPC_DEFAULT_SOURCES = [
  ["YouTube", "youtube.com", "video"],
  ["Netflix", "netflix.com", "video"],
  ["Disney+", "disneyplus.com", "video"],
  ["Prime Video", "primevideo.com", "video"],
  ["Max", "max.com", "video"],
  ["Hulu", "hulu.com", "video"],
  ["Paramount+", "paramountplus.com", "video"],
  ["Peacock", "peacocktv.com", "video"],
  ["Crunchyroll", "crunchyroll.com", "video"],
  ["Twitch", "twitch.tv", "video"],
  ["Vimeo", "vimeo.com", "video"],
  ["YouTube Music", "music.youtube.com", "music"],
  ["SoundCloud", "soundcloud.com", "music"],
  ["Spotify", "open.spotify.com", "music"],
  ["Apple Music", "music.apple.com", "music"],
  ["Amazon Music", "music.amazon.com", "music"],
  ["TIDAL", "tidal.com", "music"],
  ["Deezer", "deezer.com", "music"],
  ["Pandora", "pandora.com", "music"],
  ["Bandcamp", "bandcamp.com", "music"],
  ["Mixcloud", "mixcloud.com", "music"]
];

globalThis.FURRPC_DEFAULT_HOSTS = globalThis.FURRPC_DEFAULT_SOURCES.map(source => source[1]);

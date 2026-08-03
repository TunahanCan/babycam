(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const supportedLanguages = new Set(["tr", "en", "de", "fr", "es", "zh", "hi", "ar"]);
  const defaultLanguage = "tr";
  const storageKey = "miucam.website.language";
  const queryLanguage = new URLSearchParams(window.location.search).get("lang");
  const pageLanguage = document.documentElement.dataset.locale;
  let storedLanguage = null;

  try {
    storedLanguage = window.localStorage.getItem(storageKey);
  } catch (_) {
    // Storage can be unavailable in private or hardened browser contexts.
  }

  const language = supportedLanguages.has(queryLanguage)
    ? queryLanguage
    : supportedLanguages.has(pageLanguage)
      ? pageLanguage
      : supportedLanguages.has(storedLanguage)
        ? storedLanguage
        : defaultLanguage;

  document.documentElement.lang = language;
  document.documentElement.dir = language === "ar" ? "rtl" : "ltr";
  document.documentElement.dataset.language = language;
})();

(() => {
  "use strict";

  const defaultLanguage = "tr";
  const supportedLanguages = Object.freeze([
    "tr",
    "en",
    "de",
    "fr",
    "es",
    "zh",
    "hi",
    "ar",
  ]);
  const rightToLeftLanguages = new Set(["ar"]);
  const openGraphLocales = Object.freeze({
    tr: "tr_TR",
    en: "en_US",
    de: "de_DE",
    fr: "fr_FR",
    es: "es_ES",
    zh: "zh_CN",
    hi: "hi_IN",
    ar: "ar_SA",
  });
  const storageKey = "miucam.website.language";
  const scriptUrl = document.currentScript?.src || new URL("i18n.js", window.location.href).href;
  const localeBaseUrl = new URL("locales/", scriptUrl);
  const catalogs = new Map();
  const bindings = [];
  let currentLanguage = defaultLanguage;
  let currentCatalog = {};
  let languageRequestId = 0;

  const normalize = (value) => value.replace(/\s+/g, " ").trim();
  const format = (value) => value.split("{year}").join(String(new Date().getFullYear()));

  const readStoredLanguage = () => {
    try {
      return window.localStorage.getItem(storageKey);
    } catch (_) {
      return null;
    }
  };

  const storeLanguage = (language) => {
    try {
      window.localStorage.setItem(storageKey, language);
    } catch (_) {
      // Storage can be unavailable in private or hardened browser contexts.
    }
  };

  const resolveInitialLanguage = () => {
    const queryLanguage = new URLSearchParams(window.location.search).get("lang");
    if (supportedLanguages.includes(queryLanguage)) return queryLanguage;

    const storedLanguage = readStoredLanguage();
    if (supportedLanguages.includes(storedLanguage)) return storedLanguage;
    return defaultLanguage;
  };

  const loadCatalog = async (language) => {
    if (catalogs.has(language)) return catalogs.get(language);

    const response = await window.fetch(new URL(`${language}.json`, localeBaseUrl));
    if (!response.ok) throw new Error(`Locale could not be loaded: ${language} (${response.status})`);

    const catalog = await response.json();
    catalogs.set(language, catalog);
    return catalog;
  };

  const addExplicitBindings = () => {
    document.querySelectorAll("[data-i18n]").forEach((element) => {
      const key = element.dataset.i18n;
      const target = element.dataset.i18nTarget || "text";
      bindings.push({ element, key, target, explicit: true });
    });
  };

  const addAutomaticBindings = (sourceCatalog) => {
    const keysBySource = new Map();
    Object.entries(sourceCatalog).forEach(([key, value]) => {
      const normalizedValue = normalize(value);
      if (!keysBySource.has(normalizedValue)) keysBySource.set(normalizedValue, key);
    });

    const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || parent.closest("script, style, [data-i18n]")) {
          return NodeFilter.FILTER_REJECT;
        }
        return keysBySource.has(normalize(node.nodeValue || ""))
          ? NodeFilter.FILTER_ACCEPT
          : NodeFilter.FILTER_REJECT;
      },
    });

    let textNode = walker.nextNode();
    while (textNode) {
      const rawValue = textNode.nodeValue || "";
      const normalizedValue = normalize(rawValue);
      const leadingWhitespace = rawValue.match(/^\s*/)?.[0] || "";
      const trailingWhitespace = rawValue.match(/\s*$/)?.[0] || "";
      bindings.push({
        node: textNode,
        key: keysBySource.get(normalizedValue),
        leadingWhitespace,
        trailingWhitespace,
        target: "textNode",
      });
      textNode = walker.nextNode();
    }

    const translatedAttributes = ["alt", "aria-label", "title", "content"];
    document.querySelectorAll("*").forEach((element) => {
      translatedAttributes.forEach((attribute) => {
        if (!element.hasAttribute(attribute)) return;
        if (element.dataset.i18n && (element.dataset.i18nTarget || "text") === attribute) return;

        const key = keysBySource.get(normalize(element.getAttribute(attribute) || ""));
        if (key) bindings.push({ element, key, target: attribute });
      });
    });
  };

  const applyBinding = (binding, catalog) => {
    if (!(binding.key in catalog)) return;
    const value = format(catalog[binding.key]);

    if (binding.target === "textNode") {
      binding.node.nodeValue = `${binding.leadingWhitespace}${value}${binding.trailingWhitespace}`;
    } else if (binding.target === "label") {
      const separatorIndex = value.search(/[:：]/);
      if (separatorIndex < 0) {
        binding.element.textContent = value;
        return;
      }

      const label = document.createElement("strong");
      label.textContent = value.slice(0, separatorIndex + 1);
      binding.element.replaceChildren(
        label,
        document.createTextNode(` ${value.slice(separatorIndex + 1).trim()}`),
      );
    } else if (binding.target === "html") {
      binding.element.innerHTML = value;
    } else if (binding.target === "text") {
      binding.element.textContent = value;
    } else {
      binding.element.setAttribute(binding.target, value);
    }
  };

  const updateLanguageUrl = (language) => {
    const url = new URL(window.location.href);
    if (language === defaultLanguage) url.searchParams.delete("lang");
    else url.searchParams.set("lang", language);
    window.history.replaceState(
      window.history.state,
      "",
      `${url.pathname}${url.search}${url.hash}`,
    );
  };

  const syncInternalLinks = (language) => {
    document.querySelectorAll("a[href]").forEach((link) => {
      const sourceHref = link.dataset.languageHref || link.getAttribute("href");
      if (!sourceHref) return;
      link.dataset.languageHref = sourceHref;

      const url = new URL(sourceHref, window.location.href);
      const linksToPage = sourceHref.startsWith("#") || /(?:\/|\.html)$/.test(url.pathname);
      if (url.origin !== window.location.origin || !linksToPage) return;

      if (language === defaultLanguage) url.searchParams.delete("lang");
      else url.searchParams.set("lang", language);
      link.setAttribute("href", `${url.pathname}${url.search}${url.hash}`);
    });
  };

  const updateLocalizedMetadata = (language, catalog) => {
    document
      .querySelector('meta[property="og:locale"]')
      ?.setAttribute("content", openGraphLocales[language]);

    const structuredData = document.querySelector('script[type="application/ld+json"]');
    if (!structuredData || !catalog["meta.homeDescription"]) return;

    try {
      const value = JSON.parse(structuredData.textContent);
      value.description = catalog["meta.homeDescription"];
      structuredData.textContent = JSON.stringify(value);
    } catch (error) {
      console.error("MiuCam structured data could not be localized", error);
    }
  };

  const applyLanguage = (language, catalog, { updateUrl = true } = {}) => {
    bindings.forEach((binding) => applyBinding(binding, catalog));
    currentLanguage = language;
    currentCatalog = catalog;

    document.documentElement.lang = language;
    document.documentElement.dir = rightToLeftLanguages.has(language) ? "rtl" : "ltr";
    document.documentElement.dataset.language = language;
    document.querySelectorAll("[data-language-selector]").forEach((selector) => {
      selector.value = language;
    });

    storeLanguage(language);
    if (updateUrl) updateLanguageUrl(language);
    syncInternalLinks(language);
    updateLocalizedMetadata(language, catalog);

    window.dispatchEvent(
      new CustomEvent("miucam:languagechange", { detail: { language, catalog } }),
    );
  };

  const changeLanguage = async (language, options) => {
    if (!supportedLanguages.includes(language)) return false;
    const requestId = ++languageRequestId;

    try {
      const catalog = await loadCatalog(language);
      if (requestId !== languageRequestId) return false;
      applyLanguage(language, catalog, options);
      return true;
    } catch (error) {
      console.error(error);
      if (requestId === languageRequestId && language !== defaultLanguage) {
        const fallbackCatalog = await loadCatalog(defaultLanguage);
        if (requestId !== languageRequestId) return false;
        applyLanguage(defaultLanguage, fallbackCatalog, { ...options, updateUrl: true });
      }
      return false;
    }
  };

  const initialize = async () => {
    const initialLanguage = resolveInitialLanguage();
    const sourceCatalogRequest = loadCatalog(defaultLanguage);
    const initialCatalogRequest =
      initialLanguage === defaultLanguage
        ? sourceCatalogRequest
        : loadCatalog(initialLanguage).catch((error) => {
            console.error(error);
            return sourceCatalogRequest;
          });
    const [sourceCatalog, initialCatalog] = await Promise.all([
      sourceCatalogRequest,
      initialCatalogRequest,
    ]);

    addExplicitBindings();
    addAutomaticBindings(sourceCatalog);

    document.querySelectorAll("[data-language-selector]").forEach((selector) => {
      selector.addEventListener("change", (event) => changeLanguage(event.target.value));
    });

    const appliedLanguage =
      initialLanguage !== defaultLanguage && initialCatalog !== sourceCatalog
        ? initialLanguage
        : defaultLanguage;
    applyLanguage(appliedLanguage, initialCatalog);

    window.MiuCamI18n.ready = true;
    window.dispatchEvent(new CustomEvent("miucam:i18nready"));
  };

  window.MiuCamI18n = {
    ready: false,
    supportedLanguages,
    get language() {
      return currentLanguage;
    },
    t(key) {
      return format(currentCatalog[key] || catalogs.get(defaultLanguage)?.[key] || key);
    },
    changeLanguage,
  };

  initialize().catch((error) => console.error("MiuCam i18n initialization failed", error));
})();

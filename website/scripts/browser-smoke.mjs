import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const baseUrl = new URL(process.argv[2] || "http://127.0.0.1:8080/");
const chromeBinary = process.env.CHROME_BIN || "google-chrome";
const outputDirectory = resolve(process.env.SCREENSHOT_DIR || "/tmp/miucam-browser-smoke");

rmSync(outputDirectory, { recursive: true, force: true });
mkdirSync(outputDirectory, { recursive: true });

const chrome = spawn(
  chromeBinary,
  [
    "--headless=new",
    "--no-sandbox",
    "--disable-gpu",
    "--hide-scrollbars",
    "--remote-debugging-address=127.0.0.1",
    "--remote-debugging-port=0",
    `--user-data-dir=${resolve(outputDirectory, "chrome-profile")}`,
    "about:blank",
  ],
  { stdio: ["ignore", "ignore", "pipe"] },
);

const delay = (milliseconds) => new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

const browserPort = await new Promise((resolvePromise, reject) => {
  const timeout = setTimeout(() => reject(new Error("Chrome debug port zaman aşımı")), 10_000);
  let stderr = "";

  chrome.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
    const match = stderr.match(/DevTools listening on ws:\/\/127\.0\.0\.1:(\d+)\//);
    if (!match) return;
    clearTimeout(timeout);
    resolvePromise(Number(match[1]));
  });

  chrome.once("error", (error) => {
    clearTimeout(timeout);
    reject(error);
  });
});

class CdpClient {
  #nextId = 1;
  #pending = new Map();
  #listeners = new Map();

  constructor(webSocketUrl) {
    this.socket = new WebSocket(webSocketUrl);
  }

  async connect() {
    if (this.socket.readyState === WebSocket.OPEN) return;
    await new Promise((resolvePromise, reject) => {
      this.socket.addEventListener("open", resolvePromise, { once: true });
      this.socket.addEventListener("error", reject, { once: true });
    });
    this.socket.addEventListener("message", (event) => this.#handleMessage(event));
  }

  #handleMessage(event) {
    const message = JSON.parse(event.data);
    if (message.id) {
      const pending = this.#pending.get(message.id);
      if (!pending) return;
      this.#pending.delete(message.id);
      if (message.error) pending.reject(new Error(message.error.message));
      else pending.resolve(message.result);
      return;
    }

    for (const listener of this.#listeners.get(message.method) || []) listener(message.params);
  }

  command(method, params = {}) {
    const id = this.#nextId++;
    this.socket.send(JSON.stringify({ id, method, params }));
    return new Promise((resolvePromise, reject) => {
      this.#pending.set(id, { resolve: resolvePromise, reject });
    });
  }

  on(method, listener) {
    const listeners = this.#listeners.get(method) || [];
    listeners.push(listener);
    this.#listeners.set(method, listeners);
  }

  close() {
    this.socket.close();
  }
}

const targetResponse = await fetch(
  `http://127.0.0.1:${browserPort}/json/new?${encodeURIComponent(baseUrl.href)}`,
  { method: "PUT" },
);
if (!targetResponse.ok) throw new Error(`Chrome target açılamadı: ${targetResponse.status}`);

const target = await targetResponse.json();
const client = new CdpClient(target.webSocketDebuggerUrl);
await client.connect();

const failures = [];
client.on("Runtime.exceptionThrown", ({ exceptionDetails }) => {
  failures.push(`JavaScript exception: ${exceptionDetails.text}`);
});
client.on("Network.loadingFailed", ({ errorText, type, canceled }) => {
  if (!canceled) failures.push(`Resource failed (${type}): ${errorText}`);
});
client.on("Network.responseReceived", ({ response }) => {
  if (response.status >= 400) failures.push(`HTTP ${response.status}: ${response.url}`);
});

await Promise.all([
  client.command("Page.enable"),
  client.command("Runtime.enable"),
  client.command("Network.enable"),
]);

const evaluate = async (expression, awaitPromise = false) => {
  const result = await client.command("Runtime.evaluate", {
    expression,
    awaitPromise,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
  }
  return result.result.value;
};

const waitUntilReady = async ({ reveal = true } = {}) => {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (await evaluate("document.readyState === 'complete'")) break;
    await delay(50);
  }

  let i18nReady = false;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    i18nReady = await evaluate("window.MiuCamI18n?.ready === true");
    if (i18nReady) break;
    await delay(50);
  }
  if (!i18nReady) throw new Error("Çeviri kataloğu yüklenemedi");
  if (!reveal) return;

  await evaluate(
    `(async () => {
      await document.fonts.ready;
      const previousScrollBehavior = document.documentElement.style.scrollBehavior;
      document.documentElement.style.scrollBehavior = 'auto';
      const revealItems = [...document.querySelectorAll('[data-reveal]')];
      for (const item of revealItems) {
        item.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
        await new Promise((resolve) => setTimeout(resolve, 110));
      }
      window.scrollTo({ top: 0, behavior: 'instant' });
      document.documentElement.style.scrollBehavior = previousScrollBehavior;
      await new Promise((resolve) => setTimeout(resolve, 800));
      return true;
    })()`,
    true,
  );
};

const runScenario = async ({
  name,
  path,
  width,
  height,
  mobile,
  expectedLanguage,
  expectedDirection,
  expectedHeading,
  testAllLanguages = false,
  testCompactLayout = false,
  testMenu = false,
  testPricingLinks = false,
  switchToLanguage,
}) => {
  await client.command("Emulation.setDeviceMetricsOverride", {
    width,
    height,
    deviceScaleFactor: 1,
    mobile,
    screenWidth: width,
    screenHeight: height,
  });

  const url = new URL(path, baseUrl).href;
  await client.command("Page.navigate", { url });
  await waitUntilReady();

  const diagnostics = await evaluate(`(() => ({
    title: document.title,
    language: document.documentElement.lang,
    direction: document.documentElement.dir,
    queryLanguage: new URL(location.href).searchParams.get('lang'),
    pathname: location.pathname,
    selectedLanguage: document.querySelector('[data-language-selector]')?.value,
    firstHeading: document.querySelector('h1')?.textContent.replace(/\\s+/g, ' ').trim(),
    mismatchedInternalPageLinks: [...document.querySelectorAll('a[href]')]
      .filter((link) => {
        const url = new URL(link.href);
        const linksToPage = /(?:\\/|\\.html)$/.test(url.pathname);
        if (url.origin !== location.origin || !linksToPage) return false;
        const supported = ['en', 'de', 'fr', 'es', 'zh', 'hi', 'ar'];
        const linkLanguage = url.pathname.split('/').filter(Boolean)
          .find((part) => supported.includes(part)) || 'tr';
        return linkLanguage !== document.documentElement.lang;
      })
      .map((link) => link.getAttribute('href')),
    width: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
    headings: document.querySelectorAll('h1, h2, h3').length,
    languageBootstrapped:
      document.documentElement.classList.contains('js')
      && document.documentElement.dataset.language === document.documentElement.lang,
    homeConversionReady: (() => {
      const hero = document.querySelector('.hero');
      if (!hero) return true;
      const secondaryCta = hero.querySelector('.hero-actions .button-secondary');
      const screens = document.querySelector('#ekranlar');
      const features = document.querySelector('#ozellikler');
      const trustItems = [...document.querySelectorAll('.trust-bar .trust-item')];
      const primaryHeroImage = document.querySelector('.phone-hero img');
      const secondaryHeroImage = document.querySelector('.phone-hero-secondary img');
      return secondaryCta?.hash === '#ekranlar'
        && hero.querySelector('.hero-pricing a')?.hash === '#fiyatlandirma'
        && document.querySelector('.final-cta .button-white')?.hash === '#fiyatlandirma'
        && Boolean(document.querySelector('#fiyatlandirma .pricing-summary'))
        && primaryHeroImage?.fetchPriority === 'high'
        && secondaryHeroImage?.fetchPriority === 'low'
        && Boolean(
          screens?.compareDocumentPosition(features) & Node.DOCUMENT_POSITION_FOLLOWING,
        )
        && trustItems.length === 4
        && trustItems.every((item) => item.textContent.trim() && !item.querySelector('strong'));
    })(),
    brokenImages: [...document.images]
      .filter((image) => image.complete && image.naturalWidth === 0)
      .map((image) => image.currentSrc || image.src),
    invisibleRevealItems: [...document.querySelectorAll('[data-reveal]')]
      .filter((item) => getComputedStyle(item).opacity === '0')
      .map((item) => item.id || item.className || item.tagName)
  }))()`);

  const untranslatedSourceValues = await evaluate(
    `(async () => {
      if (document.documentElement.lang === 'tr') return [];
      const i18nScript = document.querySelector('script[src$="i18n.js"]');
      const localeBase = new URL('locales/', i18nScript.src);
      const [source, target] = await Promise.all([
        fetch(new URL('tr.json', localeBase)).then((response) => response.json()),
        fetch(new URL(document.documentElement.lang + '.json', localeBase))
          .then((response) => response.json()),
      ]);
      const normalize = (value) => value.replace(/\\s+/g, ' ').trim();
      const sourceValues = new Set(
        Object.keys(source)
          .filter((key) => source[key] !== target[key])
          .map((key) => normalize(source[key])),
      );
      const matches = new Set();
      const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT, {
        acceptNode(node) {
          if (node.parentElement?.closest('script, style')) return NodeFilter.FILTER_REJECT;
          return sourceValues.has(normalize(node.nodeValue || ''))
            ? NodeFilter.FILTER_ACCEPT
            : NodeFilter.FILTER_REJECT;
        },
      });
      let node = walker.nextNode();
      while (node) {
        matches.add(normalize(node.nodeValue || ''));
        node = walker.nextNode();
      }
      for (const element of document.querySelectorAll('*')) {
        for (const attribute of ['alt', 'aria-label', 'title', 'content']) {
          const value = normalize(element.getAttribute(attribute) || '');
          if (sourceValues.has(value)) matches.add(value);
        }
      }
      return [...matches];
    })()`,
    true,
  );

  if (
    diagnostics.language !== expectedLanguage ||
    diagnostics.direction !== expectedDirection ||
    diagnostics.selectedLanguage !== expectedLanguage ||
    diagnostics.queryLanguage !== null
  ) {
    failures.push(
      `${name}: dil durumu hatalı (${diagnostics.language}/${diagnostics.direction}/${diagnostics.selectedLanguage})`,
    );
  }
  if (!diagnostics.firstHeading?.includes(expectedHeading)) {
    failures.push(`${name}: beklenen çeviri başlıkta yok: ${expectedHeading}`);
  }
  if (!diagnostics.languageBootstrapped) {
    failures.push(`${name}: erken dil/RTL başlangıç durumu kurulmadı`);
  }
  if (!diagnostics.homeConversionReady) {
    failures.push(`${name}: hero CTA, fayda şeridi veya ürün kanıtı sırası bozuk`);
  }
  if (diagnostics.mismatchedInternalPageLinks.length > 0) {
    failures.push(
      `${name}: dili taşımayan sayfa bağlantısı: ${diagnostics.mismatchedInternalPageLinks.join(", ")}`,
    );
  }
  if (untranslatedSourceValues.length > 0) {
    failures.push(`${name}: çevrilmeden kalan kaynak metin: ${untranslatedSourceValues.join(" | ")}`);
  }

  if (diagnostics.scrollWidth > diagnostics.width + 1) {
    failures.push(`${name}: yatay taşma (${diagnostics.scrollWidth}px > ${diagnostics.width}px)`);
  }
  if (diagnostics.brokenImages.length > 0) {
    failures.push(`${name}: kırık görseller: ${diagnostics.brokenImages.join(", ")}`);
  }
  if (diagnostics.invisibleRevealItems.length > 0) {
    failures.push(
      `${name}: görünmeyen reveal öğesi: ${diagnostics.invisibleRevealItems.join(", ")}`,
    );
  }

  const tourErrors = await evaluate(`(async () => {
    const tour = document.querySelector('[data-screen-showcase]');
    if (!tour) return [];
    const errors = [];
    const tabs = [...tour.querySelectorAll('[data-screen-tab]')];
    const panels = [...tour.querySelectorAll('[data-screen-panel]')];
    const tablist = tour.querySelector('[data-screen-tabs]');
    if (tabs.length !== 4 || panels.length !== 4 || tablist.hidden
      || tablist.getAttribute('role') !== 'tablist') return ['tablist structure'];
    const selected = (index) => tabs.every((tab, position) =>
      tab.getAttribute('aria-selected') === String(position === index)
      && tab.tabIndex === (position === index ? 0 : -1)
      && panels[position].hidden === (position !== index)
      && tab.getAttribute('aria-controls') === panels[position].id
      && panels[position].getAttribute('aria-labelledby') === tab.id
      && panels[position].getAttribute('role') === 'tabpanel');
    if (!selected(0)) errors.push('initial selection');
    const previousScroll = document.documentElement.style.scrollBehavior;
    document.documentElement.style.scrollBehavior = 'auto';
    try {
      for (let index = 0; index < tabs.length; index++) {
        tabs[index].click();
        panels[index].scrollIntoView({ behavior: 'instant', block: 'center' });
        const img = panels[index].querySelector('img');
        try { await img.decode(); } catch (_) { errors.push('image decode ' + index); }
        if (!selected(index)) errors.push('selection ' + index);
        const rect = panels[index].getBoundingClientRect();
        if (rect.width < 1 || rect.left < -1 || rect.right > innerWidth + 1) errors.push('panel overflow ' + index);
        if (img.naturalWidth !== 390 || img.naturalHeight !== 844) errors.push('outdated capture ' + index);
        if (!img.alt || !panels[index].querySelector('h3')?.textContent.trim()) errors.push('missing description ' + index);
      }
      tabs[0].click();
      tabs[0].focus({ preventScroll: true });
      const rtl = document.documentElement.dir === 'rtl';
      const press = (key) => document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }));
      const expectSelection = (index, label) => {
        if (!selected(index) || document.activeElement !== tabs[index]) errors.push(label);
      };
      press(rtl ? 'ArrowLeft' : 'ArrowRight'); expectSelection(1, 'forward arrow');
      press(rtl ? 'ArrowRight' : 'ArrowLeft'); expectSelection(0, 'backward arrow');
      press(rtl ? 'ArrowRight' : 'ArrowLeft'); expectSelection(3, 'wrap arrow');
      press('Home'); expectSelection(0, 'home key');
      press('End'); expectSelection(3, 'end key');
      tabs[0].click();
      document.activeElement.blur();
      window.scrollTo({ top: 0, behavior: 'instant' });
    } finally {
      document.documentElement.style.scrollBehavior = previousScroll;
    }
    return errors;
  })()`, true);
  for (const error of tourErrors) failures.push(`${name}: ekran turu (${error})`);

  if (name === "desktop-home" || name === "mobile-home") {
    for (const story of ["watch", "room", "comfort", "alerts"]) {
      const clip = await evaluate(`(() => {
        document.getElementById('screen-tab-${story}').click();
        const section = document.getElementById('ekranlar');
        const rect = section.getBoundingClientRect();
        return { x: 0, y: rect.top + scrollY, width: innerWidth, height: rect.height, scale: 1 };
      })()`);
      const capture = await client.command("Page.captureScreenshot", {
        format: "png", captureBeyondViewport: true, fromSurface: true, clip,
      });
      writeFileSync(resolve(outputDirectory, `${name}-${story}.png`), Buffer.from(capture.data, "base64"));
    }
    await evaluate("document.getElementById('screen-tab-watch').click()");
  }

  if (testMenu) {
    const menuResult = await evaluate(`(() => {
      const toggle = document.querySelector('[data-menu-toggle]');
      const nav = document.querySelector('[data-nav]');
      const hiddenBeforeOpen = getComputedStyle(nav).visibility === 'hidden';
      toggle.click();
      const opened = toggle.getAttribute('aria-expanded') === 'true' && nav.classList.contains('is-open');
      const links = [...nav.querySelectorAll('a')];
      links[links.length - 1].focus();
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
      const focusTrapped = document.activeElement === toggle;
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      const closed = toggle.getAttribute('aria-expanded') === 'false'
        && !nav.classList.contains('is-open')
        && getComputedStyle(nav).visibility === 'hidden';
      return { hiddenBeforeOpen, opened, focusTrapped, closed };
    })()`);
    if (
      !menuResult.hiddenBeforeOpen ||
      !menuResult.opened ||
      !menuResult.focusTrapped ||
      !menuResult.closed
    ) {
      failures.push(`${name}: mobil menü veya klavye odağı davranışı bozuk`);
    }
  }

  if (testCompactLayout) {
    const compactLayoutResult = await evaluate(`(() => {
      const releaseNote = document.querySelector('.release-note')?.getBoundingClientRect();
      const ctaMascot = document.querySelector('.cta-card > img')?.getBoundingClientRect();
      const ctaOverlaps = releaseNote && ctaMascot
        ? !(
            releaseNote.right <= ctaMascot.left
            || ctaMascot.right <= releaseNote.left
            || releaseNote.bottom <= ctaMascot.top
            || ctaMascot.bottom <= releaseNote.top
          )
        : true;

      const previousRootFontSize = document.documentElement.style.fontSize;
      document.documentElement.style.fontSize = '200%';
      const viewportWidth = document.documentElement.clientWidth;
      const resizedScrollWidth = document.documentElement.scrollWidth;
      const visible = (element) => {
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== 'none'
          && style.visibility !== 'hidden'
          && rect.width > 0
          && rect.height > 0;
      };
      const clippedControls = [
        ...document.querySelectorAll('a[href], button, select, summary, [tabindex]'),
      ]
        .filter(visible)
        .filter((element) => {
          if (element.closest('.screen-showcase, .legal-nav')) return false;
          const rect = element.getBoundingClientRect();
          return rect.left < -1 || rect.right > viewportWidth + 1;
        })
        .map((element) => element.id || element.className || element.tagName);
      document.documentElement.style.fontSize = previousRootFontSize;

      return { ctaOverlaps, viewportWidth, resizedScrollWidth, clippedControls };
    })()`);

    if (compactLayoutResult.ctaOverlaps) {
      failures.push(`${name}: CTA maskotu yayın notunun üstünü kapatıyor`);
    }
    if (
      compactLayoutResult.resizedScrollWidth > compactLayoutResult.viewportWidth + 1
      || compactLayoutResult.clippedControls.length > 0
    ) {
      failures.push(
        `${name}: %200 metin boyutunda yeniden akış bozuk `
        + `(${compactLayoutResult.resizedScrollWidth}px > `
        + `${compactLayoutResult.viewportWidth}px; `
        + `${compactLayoutResult.clippedControls.join(", ")})`,
      );
    }
  }

  const screenshot = await client.command("Page.captureScreenshot", {
    format: "png",
    captureBeyondViewport: true,
    fromSurface: true,
  });
  writeFileSync(resolve(outputDirectory, `${name}.png`), Buffer.from(screenshot.data, "base64"));

  if (testPricingLinks) {
    const pricingLinks = await evaluate(`(async () => {
      const previousScrollBehavior = document.documentElement.style.scrollBehavior;
      document.documentElement.style.scrollBehavior = 'auto';
      const settle = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      try {
        document.querySelector('.hero-pricing a').click();
        await settle();
        const card = document.querySelector('.pricing-summary');
        const rect = card.getBoundingClientRect();
        const heroOpensPricing = location.hash === '#fiyatlandirma'
          && rect.top < innerHeight && rect.bottom > 0
          && getComputedStyle(card).opacity !== '0';
        const details = document.querySelector('#ucret-detaylari');
        const explanationLink = card.querySelector('.text-link');
        explanationLink.click();
        await settle();
        const explanationOpens = explanationLink.hash === '#ucret-detaylari'
          && location.hash === '#ucret-detaylari' && details.open;
        details.open = false;
        explanationLink.click();
        await settle();
        const sameFragmentReopens = details.open;
        document.querySelector('.final-cta .button-white').click();
        await settle();
        return {
          heroOpensPricing,
          explanationOpens,
          sameFragmentReopens,
          finalCtaOpensPricing: location.hash === '#fiyatlandirma',
        };
      } finally {
        document.documentElement.style.scrollBehavior = previousScrollBehavior;
      }
    })()`, true);
    for (const [check, passed] of Object.entries(pricingLinks)) {
      if (!passed) failures.push(`${name}: fiyat bağlantısı davranışı bozuk (${check})`);
    }
    await checkLocalizedDocument(expectedLanguage, '', '#fiyatlandirma', `${name} pricing navigation`);
  }

  if (testAllLanguages) {
    await client.command("Emulation.setDeviceMetricsOverride", {
      width: 320,
      height: 568,
      deviceScaleFactor: 1,
      mobile: true,
      screenWidth: 320,
      screenHeight: 568,
    });
    const languageCycle = await evaluate(
      `(async () => {
        const localeBase = new URL('locales/', ${JSON.stringify(baseUrl.href)});
        const originalFetch = window.fetch.bind(window);
        window.fetch = (input, options) => {
          if (new URL(input).pathname.endsWith('/fr.json')) {
            return new Promise((resolve) => {
              setTimeout(() => resolve(originalFetch(input, options)), 150);
            });
          }
          return originalFetch(input, options);
        };
        const slowSelection = window.MiuCamI18n.changeLanguage('fr');
        const latestSelection = window.MiuCamI18n.changeLanguage('es');
        await Promise.all([slowSelection, latestSelection]);
        const raceWinner = document.documentElement.lang;
        window.fetch = originalFetch;

        const results = [];
        for (const language of window.MiuCamI18n.supportedLanguages) {
          const catalog = await fetch(new URL(language + '.json', localeBase))
            .then((response) => response.json());
          await window.MiuCamI18n.changeLanguage(language);
          await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
          results.push({
            language,
            documentLanguage: document.documentElement.lang,
            direction: document.documentElement.dir,
            selected: document.querySelector('[data-language-selector]')?.value,
            titleMatches: document.title === catalog['meta.homeTitle'],
            headingMatches: document.querySelector('h1')?.textContent
              .replace(/\\s+/g, ' ')
              .includes(catalog['hero.titleLead']),
            menuLabelMatches: document.querySelector('[data-menu-toggle]')
              ?.getAttribute('aria-label') === catalog['menu.open'],
            openGraphLocaleChanged:
              language === 'tr'
              || document.querySelector('meta[property="og:locale"]')?.content !== 'tr_TR',
            structuredDataMatches: (() => {
              const script = document.querySelector('script[type="application/ld+json"]');
              return !script || JSON.parse(script.textContent).description === catalog['meta.homeDescription'];
            })(),
            pathMatches: (() => {
              const routeLanguage = location.pathname.split('/').filter(Boolean)
                .find((part) => ['en', 'de', 'fr', 'es', 'zh', 'hi', 'ar'].includes(part))
                || 'tr';
              return routeLanguage === language;
            })(),
            pricingLocalized: ['trialLabel', 'title', 'details', 'region', 'amount', 'payment', 'availability', 'faqLink']
              .every((key) => document.querySelector('[data-i18n="pricing.' + key + '"]')?.textContent
                === catalog['pricing.' + key]),
            screenTourLocalized: [...document.querySelectorAll('[data-screen-showcase] [data-i18n], .family-license [data-i18n]')]
              .every((element) => {
                const target = element.dataset.i18nTarget;
                const value = target ? element.getAttribute(target) : element.textContent;
                return value === catalog[element.dataset.i18n];
              }),
            pricingOverflow: (() => {
              const card = document.querySelector('.pricing-summary');
              const cardRect = card.getBoundingClientRect();
              if (cardRect.left < -1 || cardRect.right > document.documentElement.clientWidth + 1) return true;
              const walker = document.createTreeWalker(card, NodeFilter.SHOW_TEXT);
              let node;
              while ((node = walker.nextNode())) {
                if (!node.textContent.trim()) continue;
                const range = document.createRange();
                range.selectNodeContents(node);
                if ([...range.getClientRects()].some((rect) => rect.left < cardRect.left - 1 || rect.right > cardRect.right + 1)) {
                  return true;
                }
              }
              return false;
            })(),
            hasHorizontalOverflow:
              document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
          });
        }
        await window.MiuCamI18n.changeLanguage(${JSON.stringify(expectedLanguage)});
        return { raceWinner, results };
      })()`,
      true,
    );
    if (languageCycle.raceWinner !== "es") {
      failures.push(`${name}: hızlı dil seçiminde son seçim korunmadı`);
    }
    for (const result of languageCycle.results) {
      const expectedLanguageDirection = result.language === "ar" ? "rtl" : "ltr";
      if (
        result.documentLanguage !== result.language ||
        result.direction !== expectedLanguageDirection ||
        result.selected !== result.language ||
        !result.titleMatches ||
        !result.headingMatches ||
        !result.menuLabelMatches ||
        !result.openGraphLocaleChanged ||
        !result.structuredDataMatches ||
        !result.pathMatches ||
        !result.pricingLocalized ||
        !result.screenTourLocalized ||
        result.pricingOverflow ||
        result.hasHorizontalOverflow
      ) {
        failures.push(`${name}: ${result.language} dil geçişi veya yerleşimi hatalı`);
      }
    }
    await client.command("Emulation.setDeviceMetricsOverride", {
      width,
      height,
      deviceScaleFactor: 1,
      mobile,
      screenWidth: width,
      screenHeight: height,
    });
  }

  if (switchToLanguage) {
    const switchResult = await evaluate(
      `(async () => {
        const selector = document.querySelector('[data-language-selector]');
        const languageChanged = Promise.race([
          new Promise((resolve) => {
            window.addEventListener('miucam:languagechange', resolve, { once: true });
          }),
          new Promise((_, reject) => {
            setTimeout(() => reject(new Error('language selector timeout')), 3000);
          }),
        ]);
        selector.value = ${JSON.stringify(switchToLanguage)};
        selector.dispatchEvent(new Event('change', { bubbles: true }));
        await languageChanged;
        return {
          language: document.documentElement.lang,
          query: new URL(window.location.href).searchParams.get('lang'),
          pathname: window.location.pathname,
          stored: window.localStorage.getItem('miucam.website.language'),
          selected: document.querySelector('[data-language-selector]')?.value,
        };
      })()`,
      true,
    );
    if (
      switchResult.language !== switchToLanguage ||
      switchResult.query !== null ||
      !switchResult.pathname.split('/').includes(switchToLanguage) ||
      switchResult.stored !== switchToLanguage ||
      switchResult.selected !== switchToLanguage
    ) {
      failures.push(`${name}: dil seçimi URL veya kalıcı depolamaya yansımadı`);
    }
  }

  console.log(
    `${name}: ${diagnostics.language}/${diagnostics.direction} · ${diagnostics.title} · ${diagnostics.width}px · ${diagnostics.headings} başlık · başarılı`,
  );
};

const checkLocalizedDocument = async (language, page, hash, context) => {
  const mismatches = await evaluate(`(async () => {
    const language = ${JSON.stringify(language)};
    const page = ${JSON.stringify(page)};
    const expectedHash = ${JSON.stringify(hash)};
    const root = new URL(${JSON.stringify(baseUrl.href)});
    const catalog = await fetch(new URL('locales/' + language + '.json', root))
      .then((response) => response.json());
    const normalize = (value) => (value || '').replace(/\\s+/g, ' ').trim();
    const errors = [];
    const expectText = (actual, key, label) => {
      if (normalize(actual) !== normalize(catalog[key])) errors.push(label);
    };
    expectText(document.title, page ? 'meta.privacyTitle' : 'meta.homeTitle', 'title');
    expectText(document.querySelector('.skip-link')?.textContent, 'skip.content', 'skip-link');
    expectText(document.querySelector('.primary-nav a[href*="#nasil-calisir"]')?.textContent,
      'nav.how', 'navigation text');
    expectText(document.querySelector('[data-nav]')?.getAttribute('aria-label'),
      'nav.mainLabel', 'navigation aria-label');
    expectText(document.querySelector('[data-language-selector]')?.getAttribute('aria-label'),
      'language.label', 'language aria-label');
    expectText(document.querySelector('meta[name="description"]')?.content,
      page ? 'meta.privacyDescription' : 'meta.homeDescription', 'description');
    if (!page) {
      expectText(document.querySelector('meta[property="og:title"]')?.content,
        'meta.socialTitle', 'OG title');
      expectText(document.querySelector('meta[property="og:description"]')?.content,
        'meta.socialDescription', 'OG description');
    }
    const expectedUrl = new URL((language === 'tr' ? '' : language + '/') + page, root);
    const canonical = document.querySelector('link[rel="canonical"]')?.href;
    if (canonical !== expectedUrl.href) errors.push('canonical URL');
    const ogUrl = document.querySelector('meta[property="og:url"]')?.content;
    if (ogUrl && ogUrl !== expectedUrl.href) errors.push('OG URL');
    const structuredData = document.querySelector('script[type="application/ld+json"]');
    if (structuredData && JSON.parse(structuredData.textContent).url !== expectedUrl.href) {
      errors.push('JSON-LD URL');
    }
    if (location.hash !== expectedHash) errors.push('navigation fragment lost');
    if (expectedHash === '#ucret-detaylari' && !document.querySelector(expectedHash)?.open) {
      errors.push('linked pricing explanation closed');
    }
    if (location.pathname !== expectedUrl.pathname) errors.push('localized path');
    if (document.documentElement.lang !== language
        || document.documentElement.dir !== (language === 'ar' ? 'rtl' : 'ltr')
        || document.querySelector('[data-language-selector]')?.value !== language
        || localStorage.getItem('miucam.website.language') !== language) {
      errors.push('language/RTL/selection/storage');
    }
    return errors;
  })()`, true);
  if (mismatches.length) failures.push(`${context}: ${mismatches.join(', ')}`);
};

const runLocalizedEntryRegressions = async () => {
  const languages = ['tr', 'en', 'de', 'fr', 'es', 'zh', 'hi', 'ar'];
  await client.command('Page.navigate', { url: baseUrl.href });
  await waitUntilReady({ reveal: false });
  for (const page of ['', 'privacy.html']) {
    for (const source of languages) {
      // A stored preference must not override an explicitly localized URL.
      await evaluate(`localStorage.setItem('miucam.website.language', ${JSON.stringify(source === 'ar' ? 'en' : 'ar')})`);
      const hash = page ? '#izinler' : '#ucret-detaylari';
      const path = (source === 'tr' ? '' : source + '/') + page + hash;
      // Hash-only navigation reuses the old document; each entry must be a
      // fresh prerendered page to exercise its original binding language.
      await client.command('Page.navigate', { url: 'about:blank' });
      await client.command('Page.navigate', { url: new URL(path, baseUrl).href });
      await waitUntilReady({ reveal: false });
      await checkLocalizedDocument(source, page, hash, `${path} initial`);
      for (const target of [source === 'de' ? 'ar' : 'de', 'tr']) {
        await evaluate(`(async () => {
          const changed = new Promise((resolve) => {
            window.addEventListener('miucam:languagechange', resolve, { once: true });
          });
          const selector = document.querySelector('[data-language-selector]');
          selector.value = ${JSON.stringify(target)};
          selector.dispatchEvent(new Event('change', { bubbles: true }));
          await Promise.race([
            changed,
            new Promise((_, reject) => setTimeout(() => reject(new Error('language selection timeout')), 3000)),
          ]);
        })()`, true);
        await checkLocalizedDocument(target, page, hash, `${path} → ${target}`);
      }
    }
  }
};

const runStandardScenarios = async () => {
  await runScenario({
    name: "desktop-home",
    path: "?lang=nope",
    width: 1440,
    height: 1000,
    mobile: false,
    expectedLanguage: "tr",
    expectedDirection: "ltr",
    expectedHeading: "Eski telefonun",
    testAllLanguages: true,
    testPricingLinks: true,
  });
  await runScenario({
    name: "tablet-home",
    path: "en/",
    width: 768,
    height: 1024,
    mobile: true,
    expectedLanguage: "en",
    expectedDirection: "ltr",
    expectedHeading: "Turn your old phone",
  });
  await runScenario({
    name: "mobile-home",
    path: "ar/",
    width: 375,
    height: 812,
    mobile: true,
    expectedLanguage: "ar",
    expectedDirection: "rtl",
    expectedHeading: "هاتفك القديم",
    testMenu: true,
    switchToLanguage: "es",
  });
  await runScenario({
    name: "compact-home",
    path: "de/",
    width: 320,
    height: 568,
    mobile: true,
    expectedLanguage: "de",
    expectedDirection: "ltr",
    expectedHeading: "Mach dein altes Smartphone",
    testCompactLayout: true,
  });
  await runScenario({
    name: "desktop-privacy",
    path: "de/privacy.html",
    width: 1280,
    height: 900,
    mobile: false,
    expectedLanguage: "de",
    expectedDirection: "ltr",
    expectedHeading: "Entwurf der Datenschutzerklärung",
  });
  await runScenario({
    name: "mobile-privacy-rtl",
    path: "ar/privacy.html",
    width: 390,
    height: 844,
    mobile: true,
    expectedLanguage: "ar",
    expectedDirection: "rtl",
    expectedHeading: "مسودة إشعار الخصوصية",
    testMenu: true,
  });

  await client.command("Emulation.setScriptExecutionDisabled", { value: true });
  await client.command("Emulation.setDeviceMetricsOverride", {
    width: 375,
    height: 812,
    deviceScaleFactor: 1,
    mobile: true,
    screenWidth: 375,
    screenHeight: 812,
  });
  await client.command("Page.navigate", { url: new URL("en/", baseUrl).href });
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (await evaluate("document.readyState === 'complete'")) break;
    await delay(50);
  }
  const noScriptResult = await evaluate(`(() => {
    const header = document.querySelector('.site-header');
    const main = document.querySelector('main');
    return {
      language: document.documentElement.lang,
      direction: document.documentElement.dir,
      hasJsClass: document.documentElement.classList.contains('js'),
      headerPosition: getComputedStyle(header).position,
      navPosition: getComputedStyle(document.querySelector('[data-nav]')).position,
      menuDisplay: getComputedStyle(document.querySelector('[data-menu-toggle]')).display,
      heading: document.querySelector('h1')?.textContent.replace(/\\s+/g, ' ').trim(),
      headerOverlapsMain: header.getBoundingClientRect().bottom > main.getBoundingClientRect().top + 1,
      hasHorizontalOverflow:
        document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
      allScreenStoriesVisible: [...document.querySelectorAll('[data-screen-panel]')]
        .filter((panel) => getComputedStyle(panel).display !== 'none').length === 4,
      inactiveTabsHidden: getComputedStyle(document.querySelector('[data-screen-tabs]')).display === 'none',
    };
  })()`);
  if (
    noScriptResult.language !== "en"
    || noScriptResult.direction !== "ltr"
    || noScriptResult.hasJsClass
    || noScriptResult.headerPosition !== "relative"
    || noScriptResult.navPosition !== "static"
    || noScriptResult.menuDisplay !== "none"
    || !noScriptResult.heading?.includes("Turn your old phone")
    || noScriptResult.headerOverlapsMain
    || noScriptResult.hasHorizontalOverflow
    || !noScriptResult.allScreenStoriesVisible
    || !noScriptResult.inactiveTabsHidden
  ) {
    failures.push("mobile-no-script: yerelleştirilmiş JS kapalı mobil yedek düzeni bozuk");
  } else {
    console.log("mobile-no-script: en/ltr · statik yerelleştirme ve menü düzeni · başarılı");
  }
  const noScriptScreenshot = await client.command("Page.captureScreenshot", {
    format: "png",
    captureBeyondViewport: true,
    fromSurface: true,
  });
  writeFileSync(
    resolve(outputDirectory, "mobile-no-script.png"),
    Buffer.from(noScriptScreenshot.data, "base64"),
  );
  await client.command("Emulation.setScriptExecutionDisabled", { value: false });
};

try {
  await runLocalizedEntryRegressions();
  if (process.env.LANGUAGE_ONLY !== '1') await runStandardScenarios();
  if (failures.length > 0) {
    console.error(`Tarayıcı smoke testi başarısız (${failures.length} hata):`);
    failures.forEach((failure) => console.error(`- ${failure}`));
    process.exitCode = 1;
  } else {
    console.log(`Tarayıcı smoke testi başarılı. Görseller: ${outputDirectory}`);
  }
} finally {
  client.close();
  chrome.kill("SIGTERM");
}

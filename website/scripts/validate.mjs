import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const defaultSiteRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const siteRoot = resolve(process.env.SITE_ROOT || defaultSiteRoot);
const supportedLanguages = ["tr", "en", "de", "fr", "es", "zh", "hi", "ar"];
const defaultLanguage = "tr";
const rootIndexSource = readFileSync(resolve(siteRoot, "index.html"), "utf8");
const isLocalizedBuild = /\bdata-localized-site="true"/i.test(rootIndexSource);
const htmlFiles = ["index.html", "privacy.html"];
if (isLocalizedBuild) {
  for (const language of supportedLanguages) {
    if (language === defaultLanguage) continue;
    htmlFiles.push(`${language}/index.html`, `${language}/privacy.html`);
  }
}
const errors = [];

const fail = (file, message) => errors.push(`${file}: ${message}`);
const read = (file) => readFileSync(resolve(siteRoot, file), "utf8");

const isLocalReference = (value) =>
  !/^(?:[a-z]+:|#|\/\/)/i.test(value) && !value.startsWith("data:");

const normalize = (value) => value.replace(/\s+/g, " ").trim();
const format = (value) => value.split("{year}").join(String(new Date().getFullYear()));
const escapeHtml = (value) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
const decodeHtml = (value) =>
  value
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const yearTokenCount = (value) =>
  typeof value === "string" ? (value.match(/\{year\}/g) || []).length : 0;
const pageLanguage = (file) => {
  const language = file.split("/")[0];
  return supportedLanguages.includes(language) ? language : defaultLanguage;
};

const rootCanonicalMatch = rootIndexSource.match(
  /<link\s+[^>]*rel="canonical"[^>]*href="([^"]+)"/i,
);
const publicBaseUrl = rootCanonicalMatch
  ? new URL("./", rootCanonicalMatch[1])
  : null;
const publicPageUrl = (file) =>
  publicBaseUrl
    ? new URL(file === "index.html" ? "./" : file.replace(/index\.html$/, ""), publicBaseUrl).href
    : null;

for (const file of htmlFiles) {
  if (!existsSync(resolve(siteRoot, file))) {
    fail(file, "yerelleştirilmiş HTML sayfası bulunamadı");
    continue;
  }

  const html = read(file);
  const language = pageLanguage(file);
  const expectedDirection = language === "ar" ? "rtl" : "ltr";

  if (!new RegExp(`<html\\s+lang="${language}"`, "i").test(html)) {
    fail(file, `html lang=${language} eksik`);
  }
  if (isLocalizedBuild && !new RegExp(`\\bdir="${expectedDirection}"`, "i").test(html)) {
    fail(file, `dir=${expectedDirection} eksik`);
  }
  if (!/<meta\s+name="description"/i.test(html)) fail(file, "meta description eksik");
  if (!/<main\b/i.test(html) || !/<header\b/i.test(html) || !/<footer\b/i.test(html)) {
    fail(file, "header/main/footer landmark yapısı eksik");
  }
  if (!/class="skip-link"/i.test(html)) fail(file, "skip link eksik");
  if (!/<select\b[^>]*\bdata-language-selector\b[^>]*>/i.test(html)) {
    fail(file, "dil seçici eksik");
  }
  if (!/<script\b[^>]*\bsrc="(?:\.\.?\/)?i18n\.js(?:[?#][^"]*)?"[^>]*>/i.test(html)) {
    fail(file, "i18n.js script bağlantısı eksik");
  }
  for (const language of supportedLanguages) {
    const optionPattern = new RegExp(
      `<option\\b[^>]*\\bvalue="${escapeRegExp(language)}"[^>]*>`,
      "i",
    );
    if (!optionPattern.test(html)) {
      fail(file, `dil seçicide ${language} seçeneği eksik`);
    }
  }

  const ids = [...html.matchAll(/\bid="([^"]+)"/gi)].map((match) => match[1]);
  const duplicateIds = ids.filter((id, index) => ids.indexOf(id) !== index);
  if (duplicateIds.length > 0) {
    fail(file, `yinelenen id bulundu: ${[...new Set(duplicateIds)].join(", ")}`);
  }

  for (const match of html.matchAll(/(?:src|href)="([^"]+)"/gi)) {
    const reference = match[1];
    if (!isLocalReference(reference)) continue;

    const cleanReference = reference.split(/[?#]/, 1)[0];
    let target = cleanReference
      ? resolve(siteRoot, dirname(file), cleanReference)
      : resolve(siteRoot, file);
    if (cleanReference && !existsSync(target)) {
      fail(file, `yerel hedef bulunamadı: ${reference}`);
    }
    if (existsSync(target) && statSync(target).isDirectory()) {
      target = resolve(target, "index.html");
    }

    const fragment = reference.includes("#") ? reference.split("#").at(-1) : "";
    if (fragment && existsSync(target) && ["", ".html"].includes(extname(target))) {
      const targetHtml = readFileSync(target, "utf8");
      const escapedFragment = fragment.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      if (!new RegExp(`\\bid="${escapedFragment}"`, "i").test(targetHtml)) {
        fail(file, `fragment hedefi bulunamadı: ${reference}`);
      }
    }
  }

  for (const match of html.matchAll(/<img\b[^>]*>/gi)) {
    const tag = match[0];
    if (!/\balt="[^"]*"/i.test(tag)) fail(file, `alt niteliği eksik: ${tag}`);
    if (!/\bwidth="\d+"/i.test(tag)) fail(file, `width niteliği eksik: ${tag}`);
    if (!/\bheight="\d+"/i.test(tag)) fail(file, `height niteliği eksik: ${tag}`);
  }

  for (const match of html.matchAll(/<a\b[^>]*target="_blank"[^>]*>/gi)) {
    if (!/\brel="[^"]*noreferrer[^"]*"/i.test(match[0])) {
      fail(file, `target=_blank bağlantısında rel=noreferrer eksik: ${match[0]}`);
    }
  }

  if (
    /href="#"/i.test(html)
    || /\bTODO\b/.test(html)
    || /lorem ipsum|example\.com/i.test(html)
  ) {
    fail(file, "placeholder bağlantı veya metin bulundu");
  }

  if (isLocalizedBuild) {
    const selectedOptions = [...html.matchAll(/<option\b[^>]*\bselected(?:="selected")?[^>]*>/gi)];
    const selectedLanguage = selectedOptions[0]?.[0].match(/\bvalue="([^"]+)"/i)?.[1];
    if (selectedOptions.length !== 1 || selectedLanguage !== language) {
      fail(file, `dil seçicide yalnız ${language} seçili olmalı`);
    }

    const canonical = html.match(/<link\s+[^>]*rel="canonical"[^>]*href="([^"]+)"/i)?.[1];
    const expectedCanonical = publicPageUrl(file);
    if (!canonical || canonical !== expectedCanonical) {
      fail(file, `self-canonical hatalı: ${canonical || "eksik"}`);
    }

    const hreflangs = new Map(
      [...html.matchAll(/<link\s+[^>]*rel="alternate"[^>]*hreflang="([^"]+)"[^>]*href="([^"]+)"/gi)]
        .map((match) => [match[1], match[2]]),
    );
    const privacyPage = file.endsWith("privacy.html");
    const alternateRoutes = new Map([
      ["tr", "tr"],
      ["en", "en"],
      ["de", "de"],
      ["fr", "fr"],
      ["es", "es"],
      ["zh-Hans", "zh"],
      ["hi", "hi"],
      ["ar", "ar"],
      ["x-default", "tr"],
    ]);
    for (const [hreflang, routeLanguage] of alternateRoutes) {
      const routePrefix = routeLanguage === defaultLanguage ? "" : `${routeLanguage}/`;
      const expectedHref = new URL(
        `${routePrefix}${privacyPage ? "privacy.html" : ""}`,
        publicBaseUrl,
      ).href;
      if (hreflangs.get(hreflang) !== expectedHref) {
        fail(file, `hreflang=${hreflang} hedefi hatalı veya eksik`);
      }
    }

    if (language !== defaultLanguage) {
      const contentWithoutCode = html
        .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
        .replace(/<style\b[\s\S]*?<\/style>/gi, " ");
      const visibleText = contentWithoutCode.replace(/<[^>]+>/g, " ");
      const translatedAttributes = [
        ...contentWithoutCode.matchAll(/\b(?:alt|aria-label|title|content)="([^"]*)"/gi),
      ].map((match) => match[1]);
      const suspiciousTurkish = normalize(`${visibleText} ${translatedAttributes.join(" ")}`)
        .split(/(?<=[.!?])\s+|\s{2,}/)
        .filter((value) => /[ğĞıİşŞ]/.test(value));
      if (suspiciousTurkish.length > 0) {
        fail(
          file,
          `çevrilmeden kalmış olası Türkçe metin: ${suspiciousTurkish.slice(0, 3).join(" | ")}`,
        );
      }
    }
  }
}

const indexHtml = read("index.html");
for (const id of ["nasil-calisir", "ozellikler", "ekranlar", "gizlilik", "sss"]) {
  if (!indexHtml.includes(`id="${id}"`)) fail("index.html", `#${id} bölümü eksik`);
}

if (!/property="og:title"/i.test(indexHtml) || !/name="twitter:card"/i.test(indexHtml)) {
  fail("index.html", "Open Graph veya Twitter kart metadatası eksik");
}
if (!/<link\s+rel="canonical"\s+href="https:\/\//i.test(indexHtml)) {
  fail("index.html", "mutlak canonical URL eksik");
}
if (!/property="og:image"\s+content="https:\/\//i.test(indexHtml)) {
  fail("index.html", "mutlak Open Graph görsel URL'si eksik");
}

const jsonLdMatch = indexHtml.match(
  /<script\s+type="application\/ld\+json">([\s\S]*?)<\/script>/i,
);
if (!jsonLdMatch) {
  fail("index.html", "JSON-LD eksik");
} else {
  try {
    JSON.parse(jsonLdMatch[1]);
  } catch (error) {
    fail("index.html", `JSON-LD geçersiz: ${error.message}`);
  }
}

const css = read("styles.css");
if (!css.includes("prefers-reduced-motion")) fail("styles.css", "reduced-motion desteği eksik");
if (!css.includes(":focus-visible")) fail("styles.css", "görünür klavye odağı eksik");
if (!/@media\s*\(max-width:/i.test(css)) fail("styles.css", "responsive breakpoint eksik");

const localeDirectory = resolve(siteRoot, "locales");
const expectedLocaleFiles = supportedLanguages.map((language) => `${language}.json`).sort();
let actualLocaleFiles = [];

if (!existsSync(localeDirectory)) {
  fail("locales", "locale klasörü bulunamadı");
} else {
  actualLocaleFiles = readdirSync(localeDirectory)
    .filter((file) => file.endsWith(".json"))
    .sort();

  const unexpectedFiles = actualLocaleFiles.filter(
    (file) => !expectedLocaleFiles.includes(file),
  );
  if (unexpectedFiles.length > 0) {
    fail("locales", `desteklenmeyen locale dosyası: ${unexpectedFiles.join(", ")}`);
  }
}

const catalogs = new Map();
for (const language of supportedLanguages) {
  const file = `locales/${language}.json`;
  if (!existsSync(resolve(siteRoot, file))) {
    fail(file, "locale dosyası bulunamadı");
    continue;
  }

  try {
    const catalog = JSON.parse(read(file));
    if (!catalog || Array.isArray(catalog) || typeof catalog !== "object") {
      fail(file, "locale kök değeri JSON nesnesi olmalı");
      continue;
    }

    for (const [key, value] of Object.entries(catalog)) {
      if (typeof value !== "string") {
        fail(file, `${key} değeri string olmalı`);
      } else if (value.trim().length === 0) {
        fail(file, `${key} değeri boş olamaz`);
      }
    }
    catalogs.set(language, catalog);
  } catch (error) {
    fail(file, `geçersiz JSON: ${error.message}`);
  }
}

const sourceCatalog = catalogs.get(defaultLanguage);
if (sourceCatalog) {
  const sourceKeys = Object.keys(sourceCatalog).sort();

  for (const language of supportedLanguages) {
    if (language === defaultLanguage) continue;
    const catalog = catalogs.get(language);
    if (!catalog) continue;

    const keys = Object.keys(catalog).sort();
    const missingKeys = sourceKeys.filter((key) => !Object.hasOwn(catalog, key));
    const extraKeys = keys.filter((key) => !Object.hasOwn(sourceCatalog, key));

    if (missingKeys.length > 0) {
      fail(`locales/${language}.json`, `eksik anahtarlar: ${missingKeys.join(", ")}`);
    }
    if (extraKeys.length > 0) {
      fail(`locales/${language}.json`, `fazla anahtarlar: ${extraKeys.join(", ")}`);
    }

    for (const key of sourceKeys) {
      if (!Object.hasOwn(catalog, key)) continue;
      const expectedTokens = yearTokenCount(sourceCatalog[key]);
      const actualTokens = yearTokenCount(catalog[key]);
      if (actualTokens !== expectedTokens) {
        fail(
          `locales/${language}.json`,
          `${key} için {year} sayısı ${expectedTokens} olmalı, ${actualTokens} bulundu`,
        );
      }
    }
  }

  for (const file of ["index.html", "privacy.html"]) {
    const html = read(file);
    for (const match of html.matchAll(
      /<([a-z][\w:-]*)\b((?=[^>]*\bdata-i18n="([^"]+)")[^>]*)>([\s\S]*?)<\/\1>/gi,
    )) {
      const [, , attributes, key, content] = match;
      if (!Object.hasOwn(sourceCatalog, key)) {
        fail(file, `bilinmeyen data-i18n anahtarı: ${key}`);
        continue;
      }
      const target = attributes.match(/\bdata-i18n-target="([^"]+)"/i)?.[1] || "text";
      if (!(["text", "html", "label"].includes(target))) continue;
      const fallbackText = normalize(decodeHtml(content.replace(/<[^>]+>/g, " ")));
      const expectedText = normalize(format(sourceCatalog[key]));
      if (fallbackText !== expectedText) {
        fail(file, `${key} HTML fallback metni Türkçe katalogla eşleşmiyor`);
      }
    }

    for (const match of html.matchAll(/<[a-z][\w:-]*\b[^>]*\bdata-i18n="([^"]+)"[^>]*>/gi)) {
      const tag = match[0];
      const key = match[1];
      const target = tag.match(/\bdata-i18n-target="([^"]+)"/i)?.[1];
      if (!target || ["text", "html", "label"].includes(target)) continue;
      if (!Object.hasOwn(sourceCatalog, key)) {
        fail(file, `bilinmeyen data-i18n anahtarı: ${key}`);
        continue;
      }
      const fallbackValue = decodeHtml(
        tag.match(new RegExp(`\\b${escapeRegExp(target)}="([^"]*)"`, "i"))?.[1] || "",
      );
      if (fallbackValue !== format(sourceCatalog[key])) {
        fail(file, `${key} HTML ${target} fallback değeri Türkçe katalogla eşleşmiyor`);
      }
    }
  }
}

if (isLocalizedBuild) {
  const metaContent = (html, attribute, value) => {
    const tag = [...html.matchAll(/<meta\b[^>]*>/gi)]
      .map((match) => match[0])
      .find((candidate) =>
        new RegExp(`\\b${attribute}="${escapeRegExp(value)}"`, "i").test(candidate),
      );
    return tag?.match(/\bcontent="([^"]*)"/i)?.[1] || null;
  };

  for (const file of htmlFiles) {
    if (!existsSync(resolve(siteRoot, file))) continue;
    const html = read(file);
    const language = pageLanguage(file);
    const catalog = catalogs.get(language);
    if (!catalog) continue;

    const privacyPage = file.endsWith("privacy.html");
    const titleKey = privacyPage ? "meta.privacyTitle" : "meta.homeTitle";
    const descriptionKey = privacyPage
      ? "meta.privacyDescription"
      : "meta.homeDescription";
    const title = normalize(html.match(/<title>([\s\S]*?)<\/title>/i)?.[1] || "");
    if (title !== escapeHtml(format(catalog[titleKey]))) {
      fail(file, `statik title ${language} kataloğuyla eşleşmiyor`);
    }
    if (metaContent(html, "name", "description") !== escapeHtml(format(catalog[descriptionKey]))) {
      fail(file, `statik meta description ${language} kataloğuyla eşleşmiyor`);
    }

    if (privacyPage) {
      const heading = normalize(html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || "");
      if (heading !== escapeHtml(format(catalog["privacyPage.title"]))) {
        fail(file, `statik gizlilik başlığı ${language} kataloğuyla eşleşmiyor`);
      }
      continue;
    }

    for (const [attribute, name, key] of [
      ["property", "og:title", "meta.socialTitle"],
      ["property", "og:description", "meta.socialDescription"],
      ["name", "twitter:title", "meta.socialTitle"],
      ["name", "twitter:description", "meta.socialDescription"],
    ]) {
      if (metaContent(html, attribute, name) !== escapeHtml(format(catalog[key]))) {
        fail(file, `${name} ${language} kataloğuyla eşleşmiyor`);
      }
    }

    const expectedSocialImage = new URL("assets/og-cover.png", publicBaseUrl).href;
    if (
      metaContent(html, "property", "og:image") !== expectedSocialImage
      || metaContent(html, "name", "twitter:image") !== expectedSocialImage
    ) {
      fail(file, "sosyal paylaşım görsel URL'si site tabanıyla eşleşmiyor");
    }

    for (const key of ["hero.titleLead", "hero.titleAccent", "hero.lead"]) {
      const binding = html.match(
        new RegExp(`<[^>]+\\bdata-i18n="${escapeRegExp(key)}"[^>]*>([\\s\\S]*?)<\\/[^>]+>`, "i"),
      )?.[1];
      if (normalize(binding || "") !== escapeHtml(format(catalog[key]))) {
        fail(file, `${key} statik gövde metni ${language} kataloğuyla eşleşmiyor`);
      }
    }

    const localizedJsonLd = html.match(
      /<script\s+type="application\/ld\+json">([\s\S]*?)<\/script>/i,
    );
    try {
      const value = JSON.parse(localizedJsonLd?.[1] || "");
      if (
        value.inLanguage !== language
        || value.description !== catalog["meta.homeDescription"]
        || value.url !== publicPageUrl(file)
        || value.image !== new URL("assets/brand/icon-512.png", publicBaseUrl).href
      ) {
        fail(file, `yerelleştirilmiş JSON-LD ${language} kataloğuyla eşleşmiyor`);
      }
    } catch (error) {
      fail(file, `yerelleştirilmiş JSON-LD geçersiz: ${error.message}`);
    }
  }
}

if (isLocalizedBuild && publicBaseUrl) {
  const sitemap = read("sitemap.xml");
  const sitemapUrls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
  const expectedSitemapUrls = supportedLanguages.map((language) => {
    const prefix = language === defaultLanguage ? "" : `${language}/`;
    return new URL(prefix, publicBaseUrl).href;
  });
  if (
    sitemapUrls.length !== expectedSitemapUrls.length
    || expectedSitemapUrls.some((url) => !sitemapUrls.includes(url))
  ) {
    fail("sitemap.xml", "yerelleştirilmiş sayfa URL'leri eksik veya hatalı");
  }
  const expectedSitemap = new URL("sitemap.xml", publicBaseUrl).href;
  if (!read("robots.txt").includes(`Sitemap: ${expectedSitemap}`)) {
    fail("robots.txt", "sitemap URL'si site tabanıyla eşleşmiyor");
  }
}

const manifestFiles = ["site.webmanifest"];
if (isLocalizedBuild) {
  manifestFiles.push(
    ...supportedLanguages
      .filter((language) => language !== defaultLanguage)
      .map((language) => `${language}/site.webmanifest`),
  );
}

for (const file of manifestFiles) {
  let manifest;
  try {
    manifest = JSON.parse(read(file));
  } catch (error) {
    fail(file, `geçersiz JSON: ${error.message}`);
    continue;
  }

  const language = pageLanguage(file);
  if (isLocalizedBuild && manifest.lang !== language) {
    fail(file, `manifest lang=${language} olmalı`);
  }
  for (const icon of manifest.icons || []) {
    if (!existsSync(resolve(siteRoot, dirname(file), icon.src))) {
      fail(file, `ikon bulunamadı: ${icon.src}`);
    }
  }
}

for (const file of [
  "styles.css",
  "app.js",
  "language-init.js",
  "i18n.js",
  "site.webmanifest",
  "robots.txt",
  "sitemap.xml",
  "_headers",
]) {
  if (!existsSync(resolve(siteRoot, file))) fail(file, "dosya bulunamadı");
}

if (errors.length > 0) {
  console.error(`MiuCam site doğrulaması başarısız (${errors.length} hata):`);
  errors.forEach((error) => console.error(`- ${error}`));
  process.exit(1);
}

const assetCount = [...indexHtml.matchAll(/(?:src|href)="([^"]+)"/gi)].filter(
  ([, reference]) => isLocalReference(reference) && extname(reference.split(/[?#]/, 1)[0]),
).length;

const localeKeyCount = sourceCatalog ? Object.keys(sourceCatalog).length : 0;
console.log(
  `MiuCam site doğrulaması başarılı: ${htmlFiles.length} sayfa, ${assetCount} yerel referans, ${catalogs.size} dil, ${localeKeyCount} çeviri anahtarı.`,
);

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const defaultSiteRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const siteRoot = resolve(process.env.SITE_ROOT || defaultSiteRoot);
const htmlFiles = ["index.html", "privacy.html"];
const supportedLanguages = ["tr", "en", "de", "fr", "es", "zh", "hi", "ar"];
const defaultLanguage = "tr";
const errors = [];

const fail = (file, message) => errors.push(`${file}: ${message}`);
const read = (file) => readFileSync(resolve(siteRoot, file), "utf8");

const isLocalReference = (value) =>
  !/^(?:[a-z]+:|#|\/\/)/i.test(value) && !value.startsWith("data:");

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const yearTokenCount = (value) =>
  typeof value === "string" ? (value.match(/\{year\}/g) || []).length : 0;

for (const file of htmlFiles) {
  const html = read(file);

  if (!/<html\s+lang="tr"/i.test(html)) fail(file, "html lang=tr eksik");
  if (!/<meta\s+name="description"/i.test(html)) fail(file, "meta description eksik");
  if (!/<main\b/i.test(html) || !/<header\b/i.test(html) || !/<footer\b/i.test(html)) {
    fail(file, "header/main/footer landmark yapısı eksik");
  }
  if (!/class="skip-link"/i.test(html)) fail(file, "skip link eksik");
  if (!/<select\b[^>]*\bdata-language-selector\b[^>]*>/i.test(html)) {
    fail(file, "dil seçici eksik");
  }
  if (!/<script\b[^>]*\bsrc="(?:\.\/)?i18n\.js(?:[?#][^"]*)?"[^>]*>/i.test(html)) {
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
    const target = cleanReference
      ? resolve(siteRoot, dirname(file), cleanReference)
      : resolve(siteRoot, file);
    if (cleanReference && !existsSync(target)) {
      fail(file, `yerel hedef bulunamadı: ${reference}`);
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

  if (/href="#"|TODO|lorem ipsum|example\.com/i.test(html)) {
    fail(file, "placeholder bağlantı veya metin bulundu");
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
}

let manifest;
try {
  manifest = JSON.parse(read("site.webmanifest"));
} catch (error) {
  fail("site.webmanifest", `geçersiz JSON: ${error.message}`);
}

for (const icon of manifest?.icons || []) {
  if (!existsSync(resolve(siteRoot, icon.src))) {
    fail("site.webmanifest", `ikon bulunamadı: ${icon.src}`);
  }
}

for (const file of [
  "styles.css",
  "app.js",
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

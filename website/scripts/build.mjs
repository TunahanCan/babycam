import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputRoot = resolve(process.argv[2] || resolve(sourceRoot, "..", "_site"));
const buildMarkerName = ".miucam-site-build";
const defaultLanguage = "tr";
const languages = ["tr", "en", "de", "fr", "es", "zh", "hi", "ar"];
const pageFiles = ["index.html", "privacy.html"];
const ogLocales = {
  tr: "tr_TR",
  en: "en_US",
  de: "de_DE",
  fr: "fr_FR",
  es: "es_ES",
  zh: "zh_CN",
  hi: "hi_IN",
  ar: "ar_SA",
};
const hreflangRoutes = {
  tr: "tr",
  en: "en",
  de: "de",
  fr: "fr",
  es: "es",
  "zh-Hans": "zh",
  hi: "hi",
  ar: "ar",
  "x-default": "tr",
};
const pathContains = (parent, child) => {
  const childPath = relative(parent, child);
  return childPath === "" || (!childPath.startsWith("..") && !isAbsolute(childPath));
};
if (pathContains(sourceRoot, outputRoot) || pathContains(outputRoot, sourceRoot)) {
  throw new Error(`Refusing unsafe website output directory: ${outputRoot}`);
}

const read = (path) => readFileSync(resolve(sourceRoot, path), "utf8");
const format = (value) => value.split("{year}").join(String(new Date().getFullYear()));
const normalize = (value) => value.replace(/\s+/g, " ").trim();
const escapeHtml = (value) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

const sourceCanonical = read("index.html").match(
  /<link\s+[^>]*rel="canonical"[^>]*href="([^"]+)"/i,
)?.[1];
const configuredSiteUrl = process.env.SITE_URL?.trim() || sourceCanonical;
if (!configuredSiteUrl) throw new Error("A canonical URL or SITE_URL is required");

const publicBaseUrl = new URL(`${configuredSiteUrl.replace(/\/+$/, "")}/`);
if (!["http:", "https:"].includes(publicBaseUrl.protocol)) {
  throw new Error(`Unsupported website URL protocol: ${publicBaseUrl.protocol}`);
}
if (publicBaseUrl.search || publicBaseUrl.hash) {
  throw new Error("SITE_URL must not include a query string or fragment");
}

const catalogs = new Map(
  languages.map((language) => [
    language,
    JSON.parse(read(`locales/${language}.json`)),
  ]),
);
const sourceCatalog = catalogs.get(defaultLanguage);
const sourceKeysByValue = new Map();
for (const [key, value] of Object.entries(sourceCatalog)) {
  const normalized = normalize(value);
  if (!sourceKeysByValue.has(normalized)) sourceKeysByValue.set(normalized, key);
}

const replaceAttribute = (attributes, name, value) => {
  const escaped = escapeHtml(value);
  const pattern = new RegExp(`(\\b${name}=")[^"]*(")`, "i");
  return pattern.test(attributes)
    ? attributes.replace(pattern, `$1${escaped}$2`)
    : `${attributes} ${name}="${escaped}"`;
};

const applyExplicitBindings = (html, catalog) => {
  const attributePattern = /<([a-z][\w:-]*)([^<>]*\bdata-i18n="([^"]+)"[^<>]*\bdata-i18n-target="([^"]+)"[^<>]*)>/gi;
  let output = html.replace(
    attributePattern,
    (match, tag, attributes, key, target) => {
      if (["text", "html", "label"].includes(target) || !(key in catalog)) return match;
      return `<${tag}${replaceAttribute(attributes, target, format(catalog[key]))}>`;
    },
  );

  const labelPattern = /<([a-z][\w:-]*)\b((?=[^>]*\bdata-i18n="([^"]+)")(?=[^>]*\bdata-i18n-target="label")[^>]*)>[\s\S]*?<\/\1>/gi;
  output = output.replace(labelPattern, (match, tag, attributes, key) => {
    if (!(key in catalog)) return match;
    const value = format(catalog[key]);
    const separatorIndex = value.search(/[:：]/);
    const content =
      separatorIndex < 0
        ? escapeHtml(value)
        : `<strong>${escapeHtml(value.slice(0, separatorIndex + 1))}</strong> ${escapeHtml(
            value.slice(separatorIndex + 1).trim(),
          )}`;
    return `<${tag}${attributes}>${content}</${tag}>`;
  });

  const textPattern = /<([a-z][\w:-]*)\b((?=[^>]*\bdata-i18n="([^"]+)")(?![^>]*\bdata-i18n-target=)[^>]*)>[\s\S]*?<\/\1>/gi;
  return output.replace(textPattern, (match, tag, attributes, key) => {
    if (!(key in catalog)) return match;
    return `<${tag}${attributes}>${escapeHtml(format(catalog[key]))}</${tag}>`;
  });
};

const applyAutomaticBindings = (html, catalog) => {
  let output = html.replace(
    /\b(alt|aria-label|title|content)="([^"]*)"/gi,
    (match, attribute, value) => {
      const key = sourceKeysByValue.get(normalize(value));
      return key && key in catalog
        ? `${attribute}="${escapeHtml(format(catalog[key]))}"`
        : match;
    },
  );

  return output.replace(
    /(<script\b[\s\S]*?<\/script>|<style\b[\s\S]*?<\/style>|<[^>]+>|[^<]+)/gi,
    (token) => {
      if (token.startsWith("<")) return token;
      const key = sourceKeysByValue.get(normalize(token));
      if (!key || !(key in catalog)) return token;
      const leading = token.match(/^\s*/)?.[0] || "";
      const trailing = token.match(/\s*$/)?.[0] || "";
      return `${leading}${escapeHtml(format(catalog[key]))}${trailing}`;
    },
  );
};

const rewriteResourcePaths = (html, language) => {
  if (language === defaultLanguage) return html;
  const rootResources = new Set([
    "app.js",
    "i18n.js",
    "language-init.js",
    "styles.css",
  ]);

  return html.replace(/\b(src|href)="([^"]+)"/gi, (match, attribute, value) => {
    if (/^(?:[a-z]+:|#|\/\/|data:)/i.test(value)) return match;
    if (value.startsWith("assets/") || rootResources.has(value)) {
      return `${attribute}="../${value}"`;
    }
    return match;
  });
};

const renderManifest = (language) => {
  const catalog = catalogs.get(language);
  const iconPrefix = language === defaultLanguage ? "" : "../";
  return `${JSON.stringify(
    {
      name: "MiuCam",
      short_name: "MiuCam",
      description: catalog["meta.homeDescription"],
      lang: language,
      start_url: "./",
      scope: "./",
      display: "browser",
      background_color: "#f8fafc",
      theme_color: "#5b5bd6",
      icons: [
        {
          src: `${iconPrefix}assets/brand/icon-192.png`,
          sizes: "192x192",
          type: "image/png",
        },
        {
          src: `${iconPrefix}assets/brand/icon-512.png`,
          sizes: "512x512",
          type: "image/png",
        },
      ],
    },
    null,
    2,
  )}\n`;
};

const localizedPublicUrl = (language, pageFile) => {
  const prefix = language === defaultLanguage ? "" : `${language}/`;
  return new URL(pageFile === "index.html" ? prefix : `${prefix}privacy.html`, publicBaseUrl).href;
};

const localizeStructuredData = (html, language, catalog, pageFile) =>
  html.replace(
    /(<script\s+type="application\/ld\+json">)([\s\S]*?)(<\/script>)/i,
    (match, opening, source, closing) => {
      try {
        const value = JSON.parse(source);
        value.url = localizedPublicUrl(language, pageFile);
        value.description = catalog["meta.homeDescription"];
        value.inLanguage = language;
        value.image = new URL("assets/brand/icon-512.png", publicBaseUrl).href;
        return `${opening}\n      ${JSON.stringify(value, null, 2).replaceAll("\n", "\n      ")}\n    ${closing}`;
      } catch (_) {
        return match;
      }
    },
  );

const renderPage = (pageFile, language) => {
  const catalog = catalogs.get(language);
  let html = read(pageFile);
  html = html.replace(
    /<html\s+lang="[^"]+"[^>]*>/i,
    `<html lang="${language}" dir="${language === "ar" ? "rtl" : "ltr"}" data-locale="${language}" data-localized-site="true">`,
  );
  html = applyExplicitBindings(html, catalog);
  html = applyAutomaticBindings(html, catalog);
  html = html.replace(/<option\b([^>]*)>/gi, (match, attributes) => {
    const value = attributes.match(/\bvalue="([^"]+)"/i)?.[1];
    const cleanAttributes = attributes.replace(/\s+selected(?:="selected")?/gi, "");
    return `<option${cleanAttributes}${value === language ? " selected" : ""}>`;
  });
  html = rewriteResourcePaths(html, language);

  html = html.replace(
    /(<link\s+rel="alternate"\s+hreflang="([^"]+)"\s+href=")[^"]+("\s*\/?>)/gi,
    (match, opening, hreflang, closing) => {
      const routeLanguage = hreflangRoutes[hreflang];
      return routeLanguage
        ? `${opening}${localizedPublicUrl(routeLanguage, pageFile)}${closing}`
        : match;
    },
  );

  const publicUrl = localizedPublicUrl(language, pageFile);
  html = html.replace(
    /(<link\s+rel="canonical"\s+href=")[^"]+("\s*\/?>)/i,
    `$1${publicUrl}$2`,
  );
  html = html.replace(
    /(<meta\s+property="og:url"\s+content=")[^"]+("\s*\/?>)/i,
    `$1${publicUrl}$2`,
  );
  html = html.replace(
    /(<meta\s+property="og:locale"\s+content=")[^"]+("\s*\/?>)/i,
    `$1${ogLocales[language]}$2`,
  );
  const socialImageUrl = new URL("assets/og-cover.png", publicBaseUrl).href;
  html = html.replace(
    /(<meta\s+property="og:image"\s+content=")[^"]+("\s*\/?>)/i,
    `$1${socialImageUrl}$2`,
  );
  html = html.replace(
    /(<meta\s+name="twitter:image"\s+content=")[^"]+("\s*\/?>)/i,
    `$1${socialImageUrl}$2`,
  );
  if (pageFile === "index.html") {
    html = localizeStructuredData(html, language, catalog, pageFile);
  }
  return html;
};

if (existsSync(outputRoot)) {
  const outputStats = statSync(outputRoot);
  if (!outputStats.isDirectory()) {
    throw new Error(`Website output path is not a directory: ${outputRoot}`);
  }
  const outputEntries = readdirSync(outputRoot);
  if (outputEntries.length > 0 && !outputEntries.includes(buildMarkerName)) {
    throw new Error(
      `Refusing to replace unrecognized non-empty website output directory: ${outputRoot}`,
    );
  }
}

rmSync(outputRoot, { recursive: true, force: true });
mkdirSync(outputRoot, { recursive: true });
writeFileSync(
  resolve(outputRoot, buildMarkerName),
  "Generated by website/scripts/build.mjs; safe for this script to replace.\n",
);

for (const entry of readdirSync(sourceRoot)) {
  if (["README.md", "scripts", "index.html", "privacy.html"].includes(entry)) continue;
  const source = resolve(sourceRoot, entry);
  const target = resolve(outputRoot, entry);
  const stats = statSync(source);
  if (stats.isDirectory()) {
    if (["assets", "locales"].includes(entry)) cpSync(source, target, { recursive: true });
  } else {
    cpSync(source, target);
  }
}

for (const language of languages) {
  const localeDirectory =
    language === defaultLanguage ? outputRoot : resolve(outputRoot, language);
  mkdirSync(localeDirectory, { recursive: true });
  for (const pageFile of pageFiles) {
    writeFileSync(resolve(localeDirectory, pageFile), renderPage(pageFile, language));
  }
  writeFileSync(resolve(localeDirectory, "site.webmanifest"), renderManifest(language));
}

const sitemapUrls = languages
  .map((language) => `  <url><loc>${localizedPublicUrl(language, "index.html")}</loc></url>`)
  .join("\n");
writeFileSync(
  resolve(outputRoot, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>\n`
    + `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n`
    + `${sitemapUrls}\n`
    + `</urlset>\n`,
);
writeFileSync(
  resolve(outputRoot, "robots.txt"),
  `User-agent: *\nAllow: /\n\nSitemap: ${new URL("sitemap.xml", publicBaseUrl).href}\n`,
);

console.log(
  `MiuCam localized site built: ${languages.length} languages × ${pageFiles.length} pages → ${outputRoot}`,
);

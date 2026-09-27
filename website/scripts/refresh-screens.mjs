import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const sourceDirectory = "docs/reports/app_acceptance_2026-09-27/screens";
const outputDirectory = "website/assets/screens";
const screenshots = [
  ["role-selection", "01_role"],
  ["client-live", "08_watch_live"],
  ["room-controls", "11_room_controls_bottom"],
  ["connection-recovery", "12_watch_connection_error"],
  ["server-preview", "14_server_preview_on"],
  ["notifications", "09_watch_history"],
];
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const sourceManifest = JSON.parse(readFileSync(resolve(
  repositoryRoot, sourceDirectory, "../manifest.json",
), "utf8"));
const expectedSources = new Map(sourceManifest.items.map((item) => [item.path, item]));

function webpDimensions(bytes) {
  if (bytes.toString("ascii", 0, 4) !== "RIFF"
      || bytes.toString("ascii", 8, 12) !== "WEBP") {
    throw new Error("Encoder did not produce a WebP image");
  }
  switch (bytes.toString("ascii", 12, 16)) {
    case "VP8 ":
      return [bytes.readUInt16LE(26) & 0x3fff, bytes.readUInt16LE(28) & 0x3fff];
    case "VP8L": {
      const size = bytes.readUInt32LE(21);
      return [(size & 0x3fff) + 1, ((size >>> 14) & 0x3fff) + 1];
    }
    case "VP8X":
      return [bytes.readUIntLE(24, 3) + 1, bytes.readUIntLE(27, 3) + 1];
    default:
      throw new Error("Unsupported WebP image header");
  }
}

mkdirSync(resolve(repositoryRoot, outputDirectory), { recursive: true });
const items = [];
for (const [name, sourceName] of screenshots) {
  const source = `${sourceDirectory}/${sourceName}.png`;
  const target = `${outputDirectory}/${name}.webp`;
  const sourceBytes = readFileSync(resolve(repositoryRoot, source));
  const sourceHash = sha256(sourceBytes);
  const sourceItem = expectedSources.get(`screens/${sourceName}.png`);
  if (sourceItem?.sha256 !== sourceHash) {
    throw new Error(`Screenshot does not match the acceptance report: ${source}`);
  }
  if (sourceBytes.toString("hex", 0, 8) !== "89504e470d0a1a0a"
      || sourceBytes.readUInt32BE(16) !== 390
      || sourceBytes.readUInt32BE(20) !== 844) {
    throw new Error(`Expected a 390 × 844 PNG: ${source}`);
  }

  const result = spawnSync("ffmpeg", [
    "-y", "-hide_banner", "-loglevel", "error",
    "-i", resolve(repositoryRoot, source),
    "-c:v", "libwebp", "-preset", "text", "-quality", "90",
    "-compression_level", "6", "-frames:v", "1",
    resolve(repositoryRoot, target),
  ], { encoding: "utf8" });
  if (result.error || result.status !== 0) {
    throw new Error(`Install ffmpeg with the libwebp encoder, then retry.\n${result.error || result.stderr}`);
  }
  const outputBytes = readFileSync(resolve(repositoryRoot, target));
  const [width, height] = webpDimensions(outputBytes);
  if (width !== 390 || height !== 844 || outputBytes.length > 100_000) {
    throw new Error(`Screenshot exceeds its dimension or 100 KB budget: ${target}`);
  }
  items.push({
    file: `${name}.webp`,
    source,
    sourceSha256: sourceHash,
    sha256: sha256(outputBytes),
    width,
    height,
    bytes: outputBytes.length,
  });
  console.log(`${name}.webp: ${width} × ${height}, ${outputBytes.length} bytes`);
}
writeFileSync(resolve(repositoryRoot, outputDirectory, "manifest.json"), `${JSON.stringify({
  sourceReport: "docs/reports/app_acceptance_2026-09-27/manifest.json",
  renderer: sourceManifest.renderer,
  locale: sourceManifest.locale,
  fixtures: sourceManifest.fixtures,
  conversion: "ffmpeg libwebp; text preset; quality 90; compression level 6; no resizing or content edits",
  items,
}, null, 2)}\n`);

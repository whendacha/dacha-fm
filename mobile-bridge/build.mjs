import { build } from "esbuild";
import { mkdir, copyFile, writeFile, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const root = fileURLToPath(new URL(".", import.meta.url));
const output = fileURLToPath(new URL("../docs/mobile/auth/", import.meta.url));
await mkdir(output, { recursive: true });
const result = await build({
  entryPoints: [join(root, "src/main.js")],
  outfile: join(output, "bridge.js"),
  bundle: true,
  format: "esm",
  platform: "browser",
  target: ["safari17", "chrome110"],
  inject: [join(root, "src/browser-shims.js")],
  minify: true,
  metafile: true,
  legalComments: "eof",
  define: { "process.env.NODE_ENV": '"production"', global: "globalThis" },
  logLevel: "info",
});
if (Object.values(result.metafile.outputs).some((file) => file.imports.length !== 0)) {
  throw new Error("The identity bridge must be a self-contained bundle without remote module imports.");
}
for (const file of ["index.html", "style.css", "mark.svg"]) {
  await copyFile(join(root, "src", file), join(output, file));
}
const html = await readFile(join(output, "index.html"), "utf8");
const scripts = [...html.matchAll(/<script\b[^>]*>/g)].map((match) => match[0]);
if (scripts.length !== 1 || scripts[0] !== '<script type="module" src="./bridge.js">') {
  throw new Error("The identity page must load only its local compiled bundle.");
}
await writeFile(fileURLToPath(new URL("../docs/.nojekyll", import.meta.url)), "");

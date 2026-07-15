/**
 * @factoria/eslint-config
 *
 * Implements the Layer Boundaries [HARD] rules from AGENTS.md as ESLint
 * enforcement. Technology-agnostic in PRINCIPLE, JS/TS-specific in
 * implementation — consuming templates inject their concrete layers and
 * restricted packages.
 *
 * Usage in a template's eslint.config.js:
 *
 *   import { createFactoriaConfig } from "@factoria/eslint-config";
 *
 *   export default [
 *     ...createFactoriaConfig({
 *       layers: [
 *         { name: "presentation", path: "src/components" },
 *         { name: "presentation", path: "src/app" },
 *         { name: "service",      path: "src/services" },
 *         { name: "data",         path: "src/data" },
 *       ],
 *       dataLayerPackages: ["@supabase/supabase-js", "@supabase/ssr"],
 *     }),
 *     // ...template's own additional config
 *   ];
 *
 * Layer order in the array IS the dependency order: earlier = higher.
 * A layer may only import from the layer directly below it.
 */

/**
 * @param {Object} options
 * @param {Array<{name: string, path: string}>} options.layers
 *   Ordered top (presentation) to bottom (data). Multiple entries may share
 *   a name (e.g. two presentation directories); they're treated as one layer.
 * @param {string[]} [options.dataLayerPackages]
 *   npm packages that ONLY the bottom layer may import (e.g. DB clients).
 * @param {string[]} [options.serverOnlyPackages]
 *   Packages no browser-adjacent layer should import (secrets, node-only).
 * @returns {import("eslint").Linter.Config[]}
 */
export function createFactoriaConfig({
  layers,
  dataLayerPackages = [],
  serverOnlyPackages = [],
}) {
  if (!layers || layers.length < 2) {
    throw new Error(
      "[@factoria/eslint-config] At least 2 layers required to enforce boundaries."
    );
  }

  // Group paths by layer name, preserving order of first appearance
  const layerOrder = [];
  const layerPaths = new Map();
  for (const { name, path } of layers) {
    if (!layerPaths.has(name)) {
      layerOrder.push(name);
      layerPaths.set(name, []);
    }
    layerPaths.get(name).push(path);
  }

  // Build no-restricted-paths zones:
  // each layer is forbidden from importing any layer that is not
  // itself or the one DIRECTLY below it.
  const zones = [];
  for (let i = 0; i < layerOrder.length; i++) {
    const targetPaths = layerPaths.get(layerOrder[i]);
    for (let j = 0; j < layerOrder.length; j++) {
      const isSelf = j === i;
      const isDirectlyBelow = j === i + 1;
      if (isSelf || isDirectlyBelow) continue;

      for (const target of targetPaths) {
        for (const from of layerPaths.get(layerOrder[j])) {
          zones.push({
            target,
            from,
            message:
              j < i
                ? `Layer boundary violation: '${layerOrder[i]}' must not import upward from '${layerOrder[j]}' (AGENTS.md, Layer Boundaries [HARD]).`
                : `Layer boundary violation: '${layerOrder[i]}' must not skip layers to reach '${layerOrder[j]}'. Go through '${layerOrder[i + 1]}' (AGENTS.md, Layer Boundaries [HARD]).`,
          });
        }
      }
    }
  }

  const bottomLayer = layerOrder[layerOrder.length - 1];
  const nonBottomPaths = layerOrder
    .slice(0, -1)
    .flatMap((name) => layerPaths.get(name));

  const configs = [
    // Rule 1: directory-to-directory layer boundaries
    {
      name: "factoria/layer-boundaries",
      files: ["**/*.{js,jsx,ts,tsx}"],
      rules: {
        "import/no-restricted-paths": ["error", { zones }],
      },
    },
  ];

  // Rule 2: data-layer packages only importable from the bottom layer
  if (dataLayerPackages.length > 0) {
    configs.push({
      name: "factoria/data-packages-restricted",
      files: nonBottomPaths.map((p) => `${p}/**/*.{js,jsx,ts,tsx}`),
      rules: {
        "no-restricted-imports": [
          "error",
          {
            paths: dataLayerPackages.map((pkg) => ({
              name: pkg,
              message: `'${pkg}' is a data-layer package. Only '${bottomLayer}' may import it — go through the service layer (AGENTS.md, Layer Boundaries [HARD]).`,
            })),
            // also block subpath imports like @supabase/supabase-js/dist/...
            patterns: dataLayerPackages.map((pkg) => ({
              group: [`${pkg}/*`],
              message: `Subpath of data-layer package '${pkg}' — same restriction applies (AGENTS.md).`,
            })),
          },
        ],
      },
    });
  }

  // Rule 3: server-only packages blocked everywhere except explicitly
  // server-side paths (templates opt paths OUT by overriding, not in)
  if (serverOnlyPackages.length > 0) {
    configs.push({
      name: "factoria/server-only-packages",
      files: ["**/*.{js,jsx,ts,tsx}"],
      rules: {
        "no-restricted-imports": [
          "error",
          {
            paths: serverOnlyPackages.map((pkg) => ({
              name: pkg,
              message: `'${pkg}' is server-only. If this file legitimately runs server-side, the template must override this rule for its path explicitly (visible exception > silent import).`,
            })),
          },
        ],
      },
    });
  }

  return configs;
}

export default createFactoriaConfig;
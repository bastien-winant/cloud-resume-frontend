// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import tailwindcss from "@tailwindcss/vite";

// https://astro.build/config
export default defineConfig({
  vite: {
    plugins: [tailwindcss()],
  },
  fonts: [{
    name: "Inter",
    cssVariable: "--font-inter",
    provider: fontProviders.fontsource(),
    // Specify weights that are actually used
    weights: [400],
    // Specify styles that are actually used
    styles: ["normal"],
    // Download only font files for characters used on the page
    subsets: ["latin"],
  }]
});

import { defineConfig } from "cf/config";

export default defineConfig({
	worker: {
		name: "tapeek",
		compatibilityDate: "2026-09-30",
		assets: {},
		domains: ["tapeek.paymond.me"],
	},
});

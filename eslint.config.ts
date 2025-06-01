import antfu from "@antfu/eslint-config";

export default antfu({
	astro: true,
	react: true,
	formatters: true,
	stylistic: {
		quotes: "double",
		semi: true,
		indent: "tab",
	},
});

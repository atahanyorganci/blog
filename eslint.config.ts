import antfu from "@antfu/eslint-config";
import tailwind from "eslint-plugin-tailwindcss";

export default antfu({
	astro: true,
	react: true,
	formatters: true,
	stylistic: {
		quotes: "double",
		semi: true,
		indent: "tab",
	},
}).append(
	tailwind.configs["flat/recommended"],
);

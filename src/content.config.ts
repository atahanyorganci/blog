import { glob } from "astro/loaders";
import { defineCollection, z } from "astro:content";

const blog = defineCollection({
	loader: glob({
		base: "./content/blog/",
		pattern: "**/*.{md,mdx}",
	}),
	schema: z.object({
		title: z.string(),
	}),
});

export const collections = { blog };

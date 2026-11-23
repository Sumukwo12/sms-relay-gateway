import type { MetadataRoute } from "next";
import { SITE_DESCRIPTION, SITE_NAME } from "./lib/site";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: SITE_NAME,
    short_name: "SMS Gateway",
    description: SITE_DESCRIPTION,
    start_url: "/dashboard",
    display: "standalone",
    background_color: "#eedfc7",
    theme_color: "#607938",
    icons: [{ src: "/icon.png", sizes: "256x256", type: "image/png" }],
  };
}

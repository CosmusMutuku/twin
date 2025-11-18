import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",           // required for S3 static hosting
  images: {
    unoptimized: true,        // required for export mode
  },
  trailingSlash: true,        // important for S3/index.html routing
};

export default nextConfig;

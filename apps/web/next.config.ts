import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Transpile shared workspace package
  transpilePackages: ["@realitycam/shared"],
};

export default nextConfig;

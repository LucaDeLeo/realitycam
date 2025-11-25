import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Transpile shared workspace package
  transpilePackages: ["@realitycam/shared"],
  // Enable React Compiler for automatic memoization
  experimental: {
    reactCompiler: true,
  },
};

export default nextConfig;

import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Transpile shared workspace package
  transpilePackages: ["@realitycam/shared"],
  // Enable React Compiler for automatic memoization
  reactCompiler: true,
};

export default nextConfig;

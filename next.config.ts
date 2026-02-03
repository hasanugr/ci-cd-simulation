import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: 'export',  // <--- BU SATIRI EKLE
  // Resim optimizasyonunu kapatıyoruz çünkü static export desteklemez
  images: {
    unoptimized: true, // <--- BU SATIRI EKLE
  },
};

export default nextConfig;

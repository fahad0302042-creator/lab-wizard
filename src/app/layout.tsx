import type { Metadata, Viewport } from "next";
import { Caveat, Kalam, Architects_Daughter } from "next/font/google";
import "./globals.css";
import { Toaster } from "@/components/ui/sonner";
import { ThemeProvider } from "@/components/theme-provider";

const caveat = Caveat({
  variable: "--font-caveat",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

const kalam = Kalam({
  variable: "--font-kalam",
  subsets: ["latin"],
  weight: ["300", "400", "700"],
});

const architects = Architects_Daughter({
  variable: "--font-architects",
  subsets: ["latin"],
  weight: ["400"],
});

export const metadata: Metadata = {
  title: "Lab Wizard — chemistry lab inventory",
  description:
    "A handwritten lab notebook for tracking chemicals, apparatus, consumption and breakages with QR scanning.",
  icons: {
    icon: "/logo.png",
    apple: "/logo.png",
  },
};

export const viewport: Viewport = {
  themeColor: "#FBF7EC",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body
        className={`${caveat.variable} ${kalam.variable} ${architects.variable} antialiased`}
      >
        <ThemeProvider>{children}</ThemeProvider>
        <Toaster
          position="top-center"
          toastOptions={{
            style: {
              background: "var(--card-fill)",
              border: "1.5px solid var(--border)",
              borderRadius: "2px 8px 3px 9px / 8px 3px 9px 2px",
              fontFamily: "var(--font-body), cursive",
              color: "var(--ink)",
            },
          }}
        />
      </body>
    </html>
  );
}

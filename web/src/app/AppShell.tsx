"use client";

import { usePathname } from "next/navigation";
import { Providers } from "./providers";
import { Header } from "@/components/layout/Header";
import { Footer } from "@/components/layout/Footer";
import { AudioPlayer } from "@/components/player/AudioPlayer";
import { SignInModal } from "@/components/layout/SignInModal";

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  if (pathname === "/mobile/auth") return <main>{children}</main>;
  return (
    <Providers>
      <div className="min-h-screen flex flex-col pb-24">
        <Header />
        <main className="flex-1">{children}</main>
        <Footer />
        <AudioPlayer />
        <SignInModal />
      </div>
    </Providers>
  );
}

import type { Metadata } from "next";
import { MeteorBridge } from "./MeteorBridge";

export const metadata: Metadata = {
  title: "Dacha FM — Meteor Wallet sign-in",
  description: "Sign in to your Dacha FM listener library with Meteor Wallet.",
  metadataBase: null,
  manifest: null,
  openGraph: null,
  twitter: null,
  robots: { index: false, follow: false },
  icons: { icon: "/mobile/auth/icon.png", apple: "/mobile/auth/icon.png" },
};

export const dynamic = "force-dynamic";

export default function Page() {
  const network = process.env.MOBILE_NEAR_NETWORK;
  const configured = !!process.env.MOBILE_API_URL && (network === "mainnet" || network === "testnet");
  return <MeteorBridge network={network === "mainnet" || network === "testnet" ? network : null} configured={configured} />;
}

import { MeteorBridge } from "./MeteorBridge";

export const dynamic = "force-dynamic";

export default function Page() {
  const network = process.env.MOBILE_NEAR_NETWORK;
  const configured = !!process.env.MOBILE_API_URL && (network === "mainnet" || network === "testnet");
  return <MeteorBridge network={network === "mainnet" || network === "testnet" ? network : null} configured={configured} />;
}

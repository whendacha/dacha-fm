import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ operation: string }> }) {
  const { operation } = await context.params;
  if (operation !== "challenge" && operation !== "verify") return NextResponse.json({ error: "Unknown operation" }, { status: 404 });

  const configured = process.env.MOBILE_API_URL;
  let base: URL;
  try {
    base = new URL(configured || "");
    if ((base.protocol !== "https:" && !(process.env.NODE_ENV === "development" && base.protocol === "http:" && ["localhost", "127.0.0.1"].includes(base.hostname))) || base.username || base.password || base.pathname !== "/" || base.search || base.hash) throw new Error();
  } catch {
    return NextResponse.json({ error: "Mobile API is not configured" }, { status: 503 });
  }

  let body: unknown;
  try { body = await request.json(); } catch { return NextResponse.json({ error: "Invalid JSON" }, { status: 400 }); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return NextResponse.json({ error: "Invalid request" }, { status: 400 });
  const data = body as Record<string, unknown>;
  if (operation === "challenge") {
    if (typeof data.code_challenge !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(data.code_challenge)) return NextResponse.json({ error: "Invalid challenge" }, { status: 400 });
  } else if (!["challenge_id", "account_id", "public_key", "signature"].every((key) => typeof data[key] === "string" && (data[key] as string).length > 0 && (data[key] as string).length <= 255)) {
    return NextResponse.json({ error: "Invalid proof" }, { status: 400 });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(new URL(`/api/mobile/v1/auth/meteor/${operation}`, base), {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data), cache: "no-store", signal: controller.signal,
    });
    const text = await response.text();
    if (!response.ok) return NextResponse.json({ error: response.status === 503 ? "Meteor sign-in is unavailable" : "Identity verification failed" }, { status: response.status >= 500 ? 503 : response.status });
    return new NextResponse(text, { status: 200, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Mobile API is unreachable" }, { status: 503 });
  } finally { clearTimeout(timeout); }
}

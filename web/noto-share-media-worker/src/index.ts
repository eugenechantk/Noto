import { type ShareMediaJob, validateJob } from "./job";

export interface Env {
  SHARE_MEDIA_QUEUE: Queue<ShareMediaJob>;
  NOTO_SHARE_MEDIA_TOKEN: string;
}

const MAX_BODY_BYTES = 16 * 1024;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function authorized(request: Request, secret: string | undefined): Promise<boolean> {
  const header = request.headers.get("authorization") ?? "";
  if (!secret || !header.startsWith("Bearer ")) return false;
  const given = new TextEncoder().encode(header.slice("Bearer ".length));
  const expected = new TextEncoder().encode(secret);
  if (given.byteLength !== expected.byteLength) return false;
  // Constant-time compare (portable; `crypto.subtle.timingSafeEqual` is Workers-only).
  let difference = 0;
  for (let i = 0; i < given.byteLength; i++) difference |= given[i] ^ expected[i];
  return difference === 0;
}

export async function handle(request: Request, env: Env): Promise<Response> {
  const { pathname } = new URL(request.url);
  if (pathname === "/noto/share-media/health") return json(200, { ok: true });
  if (pathname !== "/noto/share-media") return json(404, { error: "not found" });
  if (request.method !== "POST") return json(405, { error: "POST only" });
  if (!(await authorized(request, env.NOTO_SHARE_MEDIA_TOKEN))) return json(401, { error: "unauthorized" });

  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) return json(413, { error: "body too large" });
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return json(400, { error: "body must be JSON" });
  }
  const job = validateJob(body);
  if (typeof job === "string") return json(400, { error: job });

  await env.SHARE_MEDIA_QUEUE.send(job, { contentType: "json" });
  return json(202, { queued: job.captureId });
}

export default { fetch: handle } satisfies ExportedHandler<Env>;

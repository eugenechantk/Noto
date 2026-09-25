/** Mirrors `NotoShareCapture.ShareMediaJob` (Swift). */
export interface ShareMediaJob {
  version: 1;
  captureId: string;
  url: string;
  platform: "x" | "instagram";
  notePath: string;
  sharedAt: string;
  title: string | null;
}

const UUID = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i;
const NOTE_PATH = /^inbox\/\d{4}-\d{2}-\d{2}-[0-9a-f]{8}\.md$/;
const X_HOSTS = new Set(["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]);
const INSTAGRAM_HOSTS = new Set(["instagram.com", "www.instagram.com", "m.instagram.com"]);
const INSTAGRAM_KINDS = new Set(["p", "reel", "reels", "tv"]);

/** Same routing as `ShareMediaSource.platform(for:)` on the phone. */
export function platformFor(raw: string): "x" | "instagram" | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  const host = url.hostname.toLowerCase();
  const parts = url.pathname.split("/").filter(Boolean);
  if (X_HOSTS.has(host)) {
    const i = parts.indexOf("status");
    return i >= 0 && i + 1 < parts.length && /^\d+$/.test(parts[i + 1]) ? "x" : null;
  }
  if (INSTAGRAM_HOSTS.has(host)) {
    return parts.some((part, i) => INSTAGRAM_KINDS.has(part) && i + 1 < parts.length) ? "instagram" : null;
  }
  return null;
}

/** Returns the job, or a reason it is rejected. */
export function validateJob(value: unknown): ShareMediaJob | string {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return "body must be a JSON object";
  const job = value as Record<string, unknown>;
  if (job.version !== 1) return "unsupported version";
  if (typeof job.captureId !== "string" || !UUID.test(job.captureId)) return "captureId must be a UUID";
  if (typeof job.url !== "string" || job.url.length > 2048) return "url is required";
  const platform = platformFor(job.url);
  if (!platform) return "url is not an X or Instagram post";
  if (job.platform !== platform) return "platform does not match url";
  if (typeof job.notePath !== "string" || !NOTE_PATH.test(job.notePath)) return "notePath must be inbox/<date>-<sha8>.md";
  if (typeof job.sharedAt !== "string" || Number.isNaN(Date.parse(job.sharedAt))) return "sharedAt must be an ISO date";
  if (job.title !== undefined && job.title !== null && (typeof job.title !== "string" || job.title.length > 1000)) {
    return "title must be a string";
  }
  return {
    version: 1,
    captureId: job.captureId.toUpperCase(),
    url: job.url,
    platform,
    notePath: job.notePath,
    sharedAt: job.sharedAt,
    title: typeof job.title === "string" ? job.title : null,
  };
}

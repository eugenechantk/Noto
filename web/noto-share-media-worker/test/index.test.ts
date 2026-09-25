import { describe, expect, it } from "vitest";
import { handle, type Env } from "../src/index";
import { platformFor, validateJob } from "../src/job";

// Test case index
// 1. routes X and Instagram post URLs like the phone does (SC3)
// 2. accepts a well-formed job and normalises it (SC3)
// 3. rejects malformed jobs with a reason (SC3)
// 4. handler: health, auth, method, bad JSON, invalid job — nothing enqueued (SC3)
// 5. handler: valid job is enqueued as JSON and answered 202 (SC3)

const job = {
  version: 1,
  captureId: "2843e15b-efe8-4673-9b25-1251aa9d9f17",
  url: "https://x.com/jacobrodri_/status/2102386784814735508?s=46",
  platform: "x",
  notePath: "inbox/2026-09-23-1a2b3c4d.md",
  sharedAt: "2026-09-23T10:00:00Z",
  title: "Post",
};

function env(sent: unknown[]): Env {
  return {
    NOTO_SHARE_MEDIA_TOKEN: "s3cret",
    SHARE_MEDIA_QUEUE: { send: async (body: unknown) => void sent.push(body) } as unknown as Queue,
  } as Env;
}

function post(body: string, token = "s3cret", path = "/noto/share-media", method = "POST"): Request {
  return new Request(`https://cloudflare.eugenechantk.me${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: method === "GET" ? undefined : body,
  });
}

describe("platformFor", () => {
  it("routes X and Instagram post URLs like the phone does", () => {
    expect(platformFor("https://twitter.com/a/status/1")).toBe("x");
    expect(platformFor("https://x.com/i/web/status/7")).toBe("x");
    expect(platformFor("https://www.instagram.com/p/Daw8hiys2w1/?stkn=a")).toBe("instagram");
    expect(platformFor("https://www.instagram.com/someone/reel/ABC/")).toBe("instagram");
    expect(platformFor("https://x.com/jacobrodri_")).toBeNull();
    expect(platformFor("https://example.com/p/ABC")).toBeNull();
    expect(platformFor("not a url")).toBeNull();
  });
});

describe("validateJob", () => {
  it("accepts a well-formed job and normalises it", () => {
    expect(validateJob(job)).toEqual({ ...job, captureId: job.captureId.toUpperCase() });
  });

  it("rejects malformed jobs with a reason", () => {
    expect(validateJob([])).toBe("body must be a JSON object");
    expect(validateJob({ ...job, version: 2 })).toBe("unsupported version");
    expect(validateJob({ ...job, captureId: "x" })).toBe("captureId must be a UUID");
    expect(validateJob({ ...job, url: "https://example.com/a" })).toBe("url is not an X or Instagram post");
    expect(validateJob({ ...job, platform: "instagram" })).toBe("platform does not match url");
    expect(validateJob({ ...job, notePath: "inbox/../x.md" })).toBe("notePath must be inbox/<date>-<sha8>.md");
    expect(validateJob({ ...job, sharedAt: "yesterday" })).toBe("sharedAt must be an ISO date");
  });
});

describe("handle", () => {
  it("guards every non-happy path without enqueueing", async () => {
    const sent: unknown[] = [];
    const e = env(sent);
    expect((await handle(post("", "s3cret", "/noto/share-media/health", "GET"), e)).status).toBe(200);
    expect((await handle(post(JSON.stringify(job), "wrong"), e)).status).toBe(401);
    expect((await handle(post(JSON.stringify(job), "s3cret", "/noto/share-media", "GET"), e)).status).toBe(405);
    expect((await handle(post("{not json"), e)).status).toBe(400);
    expect((await handle(post(JSON.stringify({ ...job, url: "https://example.com" })), e)).status).toBe(400);
    expect((await handle(post(JSON.stringify(job), "s3cret", "/noto/other"), e)).status).toBe(404);
    expect(sent).toEqual([]);
  });

  it("enqueues a valid job and answers 202", async () => {
    const sent: unknown[] = [];
    const response = await handle(post(JSON.stringify(job)), env(sent));
    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ queued: job.captureId.toUpperCase() });
    expect(sent).toEqual([{ ...job, captureId: job.captureId.toUpperCase() }]);
  });
});

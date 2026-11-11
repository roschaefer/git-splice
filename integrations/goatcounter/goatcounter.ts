declare const Netlify: { env: { get: (name: string) => string | undefined } };

type Context = { ip: string; waitUntil: (promise: Promise<unknown>) => void };

const apiUrl = (site: string) => `https://${site}.goatcounter.com/api/v0/count`;

// The same 1x1 GIF that GoatCounter's own /count endpoint responds with.
const gif = Uint8Array.from([
	0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x1, 0x0, 0x1, 0x0, 0x80, 0x1, 0x0, 0x0, 0x0, 0x0, 0xff, 0xff,
	0xff, 0x21, 0xf9, 0x4, 0x1, 0xa, 0x0, 0x1, 0x0, 0x2c, 0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0, 0x0,
	0x2, 0x2, 0x4c, 0x1, 0x0, 0x3b,
]);

const gifResponse = () =>
	new Response(gif, {
		headers: { "content-type": "image/gif", "cache-control": "no-store" },
	});

export const primaryLanguage = (acceptLanguage: string | null): string =>
	acceptLanguage?.split(",")[0]?.split(";")[0]?.trim() ?? "";

export const toApiHit = (request: Request, ip: string) => {
	const params = new URL(request.url).searchParams;
	const path = params.get("p");
	if (!path) {
		return null;
	}

	return {
		path,
		title: params.get("t") ?? "",
		ref: params.get("r") ?? "",
		event: params.get("e") === "true",
		size: params.get("s") ?? "",
		query: params.get("q") ?? "",
		bot: Number.parseInt(params.get("b") ?? "0", 10) || 0,
		user_agent: request.headers.get("user-agent") ?? "",
		language: primaryLanguage(request.headers.get("accept-language")),
		ip,
	};
};

export type ApiHit = NonNullable<ReturnType<typeof toApiHit>>;

export const send = async (hit: ApiHit, token: string, site: string) => {
	const response = await fetch(apiUrl(site), {
		method: "POST",
		headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
		body: JSON.stringify({ hits: [hit] }),
	});
	if (!response.ok) {
		console.error(`GoatCounter API responded ${response.status}: ${await response.text()}`);
	}
};

export default async (request: Request, context: Context) => {
	const hit = toApiHit(request, context.ip);
	const token = Netlify.env.get("GOATCOUNTER_API_TOKEN");
	const site = Netlify.env.get("GOATCOUNTER_SITE");

	if (!token || !site || !/^[a-z0-9-]+$/.test(site)) {
		console.error("GOATCOUNTER_SITE or GOATCOUNTER_API_TOKEN is missing or invalid, not counting");
	} else if (hit) {
		context.waitUntil(send(hit, token, site).catch((error) => console.error(error)));
	}

	return gifResponse();
};

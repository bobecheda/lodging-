// connect-desk: connects a desk PC to the cloud (docs/sync.md).
//
// POST {
//   mode: "connect" | "reconnect",
//   install_code?: string,      // connect only: a one-time code
//   owner_email: string,
//   owner_password: string,     // the owner's desk password
//   owner_user_id: string,      // the owner's users.id on the desk
//   device_id: string           // the desk's device id
// }
// → 200 { device_email, device_secret }   (the secret is shown only here)
// → 4xx { error }                         (a sentence for the owner)
//
// connect: creates the owner's account the first time (same password as on
// the desk), or checks it; records this desk and uses up the install code;
// then creates or re-keys this desk's account. reconnect: the owner's email
// and password stand in for a code, and the desk gets a new secret (e.g. it
// was lost with a Windows user). At most 10 failed tries an hour per owner
// email. The service key never leaves this function, and Supabase's own
// error text never reaches the desk (it is logged here instead).
import { createClient } from "jsr:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

type Body = {
  mode?: string;
  install_code?: string;
  owner_email?: string;
  owner_password?: string;
  owner_user_id?: string;
  device_id?: string;
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const say = {
  badRequest: "Something is missing from the request.",
  unreachable: "The cloud could not be reached. Try again in a moment.",
  tooManyTries: "Too many tries. Wait an hour and try again.",
  otherOwner: "This lodging's cloud account belongs to another owner email.",
  wrongPassword: "Wrong email or password for the owner's cloud account.",
  neverConnected: "This desk has never been connected.",
  ownerNotCreated: "The owner's cloud account could not be created. Try again.",
  emailTaken: "This email already has a cloud account. Use its password.",
  badCode: "That install code isn't valid, has expired or has been used.",
  deskNotSaved: "This desk could not be connected. Try again.",
} as const;

function newSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

const noSession = { auth: { persistSession: false, autoRefreshToken: false } };

/// Logs what Supabase said (for the function's logs only).
function logged(step: string, error: unknown): void {
  console.error(`connect-desk: ${step}:`, error);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only." });
  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: say.badRequest });
  }
  const mode = body.mode;
  const email = body.owner_email?.trim().toLowerCase() ?? "";
  const password = body.owner_password ?? "";
  const ownerUserId = body.owner_user_id ?? "";
  const deviceId = body.device_id ?? "";
  if (
    (mode !== "connect" && mode !== "reconnect") ||
    !email.includes("@") || password.length === 0 || !ownerUserId ||
    !/^[0-9a-f-]{36}$/.test(deviceId) ||
    (mode === "connect" && !body.install_code)
  ) {
    return json(400, { error: say.badRequest });
  }

  const admin = createClient(url, serviceKey, noSession);
  const anon = createClient(url, anonKey, noSession);

  // Every attempt is recorded; ten failures an hour lock this email out.
  const { data: allowed, error: limitError } = await admin.rpc(
    "connect_attempt_allowed",
    { p_email: email },
  );
  if (limitError) {
    logged("rate limit check", limitError);
    return json(500, { error: say.unreachable });
  }
  const finish = async (status: number, payload: Record<string, unknown>) => {
    const { error } = await admin.rpc("record_connect_attempt", {
      p_email: email,
      p_ok: status === 200,
    });
    if (error) logged("recording the attempt", error);
    return json(status, payload);
  };
  const refuse = (status: number, error: string) => finish(status, { error });
  if (allowed !== true) return refuse(429, say.tooManyTries);

  // The owner: there is at most one, and it must be this desk's owner.
  const { data: owner, error: ownerError } = await admin.rpc("cloud_owner");
  if (ownerError) {
    logged("reading the owner", ownerError);
    return refuse(500, say.unreachable);
  }
  let ownerAuthId: string;
  let createdOwner = false;
  if (owner) {
    if (owner.email !== email || owner.user_id !== ownerUserId) {
      return refuse(403, say.otherOwner);
    }
    const { data, error } = await anon.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      if (error) logged("owner sign-in", error);
      return refuse(401, say.wrongPassword);
    }
    ownerAuthId = data.user.id;
  } else {
    if (mode === "reconnect") return refuse(409, say.neverConnected);
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      app_metadata: { role: "owner", user_id: ownerUserId },
    });
    if (error || !data.user) {
      logged("creating the owner", error);
      const taken = (error as { code?: string } | null)?.code === "email_exists";
      return refuse(400, taken ? say.emailTaken : say.ownerNotCreated);
    }
    ownerAuthId = data.user.id;
    createdOwner = true;
  }
  const undoOwner = async () => {
    if (!createdOwner) return;
    const { error } = await admin.auth.admin.deleteUser(ownerAuthId);
    if (error) logged("undoing the new owner", error);
  };

  if (mode === "connect") {
    const { data: unused, error } = await admin.rpc("install_code_unused", {
      p_code: body.install_code,
    });
    if (error) logged("checking the install code", error);
    if (unused !== true) {
      await undoOwner();
      return refuse(403, say.badCode);
    }
  }

  // This desk's own account: one per device, re-keyed on every (re)connect.
  const deviceEmail = `${deviceId}@desk.lodging.invalid`;
  const secret = newSecret();
  const appMetadata = { role: "desk", device_id: deviceId };
  const { data: existingId, error: lookupError } = await admin.rpc(
    "desk_auth_user",
    { p_device_id: deviceId },
  );
  if (lookupError) {
    logged("looking up the desk", lookupError);
    await undoOwner();
    return refuse(500, say.unreachable);
  }

  const register = async (deviceAuthId: string) => {
    const { error } = await admin.rpc("register_desk", {
      p_code: body.install_code,
      p_device_id: deviceId,
      p_device_auth_id: deviceAuthId,
      p_owner_auth_id: ownerAuthId,
      p_owner_user_id: ownerUserId,
      p_owner_email: email,
    });
    if (!error) return null;
    logged("registering the desk", error);
    if (error.message.includes("install code")) return say.badCode;
    if (error.message.includes("another owner")) return say.otherOwner;
    return say.deskNotSaved;
  };

  if (existingId) {
    // An existing desk account: record the desk (and use up the code)
    // first, so a refused connect never re-keys a desk that still works.
    if (mode === "connect") {
      const problem = await register(existingId);
      if (problem) {
        await undoOwner();
        return refuse(403, problem);
      }
    }
    const { error } = await admin.auth.admin.updateUserById(existingId, {
      password: secret,
      app_metadata: appMetadata,
    });
    if (error) {
      logged("re-keying the desk", error);
      return refuse(500, say.deskNotSaved);
    }
  } else {
    if (mode === "reconnect") return refuse(409, say.neverConnected);
    const { data, error } = await admin.auth.admin.createUser({
      email: deviceEmail,
      password: secret,
      email_confirm: true,
      app_metadata: appMetadata,
    });
    if (error || !data.user) {
      logged("creating the desk account", error);
      await undoOwner();
      return refuse(500, say.deskNotSaved);
    }
    const problem = await register(data.user.id);
    if (problem) {
      const { error: undoError } = await admin.auth.admin.deleteUser(data.user.id);
      if (undoError) logged("undoing the new desk account", undoError);
      await undoOwner();
      return refuse(403, problem);
    }
  }

  return finish(200, { device_email: deviceEmail, device_secret: secret });
});

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
// the desk), or checks it; creates or re-keys this desk's account; uses up
// the install code. reconnect: the owner's email and password stand in for
// a code, and the desk gets a new secret (e.g. it was lost with a Windows
// user). The service key never leaves this function.
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

const refuse = (status: number, error: string) => json(status, { error });

function newSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

const noSession = { auth: { persistSession: false, autoRefreshToken: false } };

Deno.serve(async (req) => {
  if (req.method !== "POST") return refuse(405, "POST only.");
  let body: Body;
  try {
    body = await req.json();
  } catch {
    return refuse(400, "The request could not be read.");
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
    return refuse(400, "Something is missing from the request.");
  }

  const admin = createClient(url, serviceKey, noSession);
  const anon = createClient(url, anonKey, noSession);

  // The owner: there is at most one, and it must be this desk's owner.
  const { data: owner, error: ownerError } = await admin.rpc("cloud_owner");
  if (ownerError) return refuse(500, "The cloud could not be reached.");
  let ownerAuthId: string;
  let createdOwner = false;
  if (owner) {
    if (owner.email !== email || owner.user_id !== ownerUserId) {
      return refuse(403, "This lodging's cloud account belongs to another owner email.");
    }
    const { data, error } = await anon.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      return refuse(401, "Wrong email or password for the owner's cloud account.");
    }
    ownerAuthId = data.user.id;
  } else {
    if (mode === "reconnect") return refuse(409, "This desk has never been connected.");
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      app_metadata: { role: "owner", user_id: ownerUserId },
    });
    if (error || !data.user) {
      return refuse(400, error?.message ?? "The owner's account could not be created.");
    }
    ownerAuthId = data.user.id;
    createdOwner = true;
  }
  const undoOwner = async () => {
    if (createdOwner) await admin.auth.admin.deleteUser(ownerAuthId);
  };

  if (mode === "connect") {
    const { data: unused } = await admin.rpc("install_code_unused", {
      p_code: body.install_code,
    });
    if (unused !== true) {
      await undoOwner();
      return refuse(403, "That install code isn't valid or has been used.");
    }
  }

  // This desk's own account: one per device, re-keyed on every (re)connect.
  const deviceEmail = `${deviceId}@desk.lodging.invalid`;
  const secret = newSecret();
  const appMetadata = { role: "desk", device_id: deviceId };
  const { data: existingId } = await admin.rpc("desk_auth_user", {
    p_device_id: deviceId,
  });
  let deviceAuthId: string;
  if (existingId) {
    const { error } = await admin.auth.admin.updateUserById(existingId, {
      password: secret,
      app_metadata: appMetadata,
    });
    if (error) return refuse(500, "This desk's account could not be updated.");
    deviceAuthId = existingId;
  } else {
    if (mode === "reconnect") return refuse(409, "This desk has never been connected.");
    const { data, error } = await admin.auth.admin.createUser({
      email: deviceEmail,
      password: secret,
      email_confirm: true,
      app_metadata: appMetadata,
    });
    if (error || !data.user) {
      await undoOwner();
      return refuse(500, "This desk's account could not be created.");
    }
    deviceAuthId = data.user.id;
  }

  if (mode === "connect") {
    const { error } = await admin.rpc("register_desk", {
      p_code: body.install_code,
      p_device_id: deviceId,
      p_device_auth_id: deviceAuthId,
      p_owner_auth_id: ownerAuthId,
      p_owner_user_id: ownerUserId,
      p_owner_email: email,
    });
    if (error) {
      if (!existingId) await admin.auth.admin.deleteUser(deviceAuthId);
      await undoOwner();
      return refuse(403, error.message);
    }
  }

  return json(200, { device_email: deviceEmail, device_secret: secret });
});

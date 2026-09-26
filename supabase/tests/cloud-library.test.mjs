import assert from "node:assert/strict";
import { before, after, test } from "node:test";
import { randomBytes, randomUUID } from "node:crypto";
import pg from "pg";

// Deliberately refuses remote or general-purpose databases. Apply the migration
// to a disposable local database with this name prefix before running the suite.
const connectionString = process.env.DACHA_CLOUD_TEST_URL;
assert.ok(connectionString, "Set DACHA_CLOUD_TEST_URL to a disposable local database");
const destination = new URL(connectionString);
assert.ok(["localhost", "127.0.0.1", "[::1]"].includes(destination.hostname));
assert.match(destination.pathname, /^\/dacha_cloud_test(?:_[a-z0-9_]+)?$/);
const runID = randomBytes(6).toString("hex");
const accountIDs = [];
const challengeIDs = [];
let admin, service;

async function connect(role) {
  const client = new pg.Client({ connectionString, statement_timeout: 10_000 });
  await client.connect();
  if (role) await client.query(`set role ${role}`);
  return client;
}

async function rpc(client, name, args = []) {
  const placeholders = args.map((_, index) => `$${index + 1}`).join(",");
  return (await client.query(`select public.${name}(${placeholders}) as value`, args)).rows[0].value;
}

async function waitUntilBlocked(pid) {
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    const state = (await admin.query("select wait_event_type from pg_stat_activity where pid=$1", [pid])).rows[0];
    if (state?.wait_event_type === "Lock") return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.fail("Expected the concurrent request to wait for the held account lock");
}

const token = () => randomBytes(32).toString("hex");
const empty = (version = 0) => ({ version, favorites: [], playlists: [], blocked_artist_ids: [] });
const code = (expected) => (error) => error.code === expected;

async function challenge() {
  const id = randomUUID(), nonce = randomBytes(32).toString("base64url"), pkce = randomBytes(32).toString("base64url");
  challengeIDs.push(id);
  const value = await rpc(service, "dacha_cloud_create_challenge", [id, nonce, pkce]);
  return { ...value, expectedNonce: nonce, expectedPKCE: pkce };
}

async function identity(account) {
  const accountID = account ?? `test-${runID}-${accountIDs.length}.near`;
  if (!accountIDs.includes(accountID)) accountIDs.push(accountID);
  const request = await challenge(), hash = token();
  const response = await rpc(service, "dacha_cloud_finish_auth", [request.id, accountID, hash]);
  return { accountID, hash, response };
}

before(async () => {
  admin = await connect();
  service = await connect("service_role");
  const role = (await service.query("select current_user as role")).rows[0].role;
  assert.equal(role, "service_role");
  assert.ok((await admin.query("select to_regprocedure('public.dacha_cloud_library_get(text)') as fn")).rows[0].fn,
    "Apply the migration to the disposable database first");
});

after(async () => {
  if (admin) {
    await admin.query("delete from dacha_cloud.accounts where account_id = any($1)", [accountIDs]);
    await admin.query("delete from dacha_cloud.challenges where id = any($1::uuid[])", [challengeIDs]);
    await admin.end();
  }
  await service?.end();
});

test("all private tables enforce RLS and no client role can call an RPC", async () => {
  const tables = (await admin.query("select relrowsecurity, relforcerowsecurity from pg_class where relnamespace='dacha_cloud'::regnamespace and relkind='r'")).rows;
  assert.equal(tables.length, 5);
  assert.ok(tables.every((row) => row.relrowsecurity && row.relforcerowsecurity));
  const functions = (await admin.query("select oid, prosecdef from pg_proc where pronamespace='public'::regnamespace and proname like 'dacha_cloud_%'")).rows;
  assert.equal(functions.length, 8);
  for (const fn of functions) {
    assert.equal(fn.prosecdef, false);
    for (const role of ["anon", "authenticated"]) {
      const privilege = (await admin.query("select has_function_privilege($1, $2::oid, 'execute') as allowed", [role, fn.oid])).rows[0].allowed;
      assert.equal(privilege, false);
    }
  }
  const anon = await connect("anon");
  try {
    await assert.rejects(rpc(anon, "dacha_cloud_library_get", [token()]), code("42501"));
    await assert.rejects(anon.query("select * from dacha_cloud.accounts"), code("42501"));
  } finally { await anon.end(); }
});

test("challenges have exact stored fields, expiration, bounded nonce and uniqueness", async () => {
  const request = await challenge();
  const read = await rpc(service, "dacha_cloud_get_challenge", [request.id]);
  assert.deepEqual(Object.keys(read).sort(), ["code_challenge", "expires_at", "id", "nonce"]);
  assert.equal(read.nonce, request.expectedNonce);
  assert.equal(read.code_challenge, request.expectedPKCE);
  assert.ok(Date.parse(read.expires_at) > Date.now() + 290_000);
  await assert.rejects(rpc(service, "dacha_cloud_create_challenge", [request.id, request.nonce, request.code_challenge]), code("PT409"));
  await assert.rejects(rpc(service, "dacha_cloud_create_challenge", [randomUUID(), "A".repeat(42) + "B", request.code_challenge]), code("PT400"));
  await admin.query("update dacha_cloud.challenges set expires_at=clock_timestamp()-interval '1 second' where id=$1", [request.id]);
  await assert.rejects(rpc(service, "dacha_cloud_get_challenge", [request.id]), code("PT401"));
});

test("consumption is single-use, sessions last 30 days and later sign-in preserves library", async () => {
  const person = await identity();
  assert.equal(person.response.account_id, person.accountID);
  assert.ok(Date.parse(person.response.expires_at) > Date.now() + 29 * 86400_000);
  assert.deepEqual(await rpc(service, "dacha_cloud_library_get", [person.hash]), empty());
  const saved = await rpc(service, "dacha_cloud_library_put", [person.hash, { ...empty(), blocked_artist_ids: ["42"] }]);
  assert.equal(saved.version, 1);
  const again = await identity(person.accountID);
  assert.deepEqual(await rpc(service, "dacha_cloud_library_get", [again.hash]), saved);
  await assert.rejects(rpc(service, "dacha_cloud_finish_auth", [challengeIDs.at(-1), person.accountID, token()]), code("PT401"));
});

test("concurrent challenge redemption yields only one session", async () => {
  const request = await challenge(), accountID = `test-${runID}-race.near`;
  accountIDs.push(accountID);
  const other = await connect("service_role");
  try {
    const outcomes = await Promise.allSettled([
      rpc(service, "dacha_cloud_finish_auth", [request.id, accountID, token()]),
      rpc(other, "dacha_cloud_finish_auth", [request.id, accountID, token()]),
    ]);
    assert.equal(outcomes.filter((value) => value.status === "fulfilled").length, 1);
    assert.equal(outcomes.find((value) => value.status === "rejected").reason.code, "PT401");
    assert.equal((await admin.query("select count(*)::int as n from dacha_cloud.sessions where account_id=$1", [accountID])).rows[0].n, 1);
  } finally { await other.end(); }
});

test("libraries stay private by token and basic invalid snapshots are rejected", async () => {
  const one = await identity(), two = await identity();
  await rpc(service, "dacha_cloud_library_put", [one.hash, { ...empty(), blocked_artist_ids: ["private-author"] }]);
  assert.deepEqual(await rpc(service, "dacha_cloud_library_get", [two.hash]), empty());
  await assert.rejects(rpc(service, "dacha_cloud_library_get", [token()]), code("PT401"));
  for (const snapshot of [null, [], { ...empty(), version: -1 }, { ...empty(), version: 1.5 },
    { ...empty(), version: 2147483647 }, { ...empty(), favorites: {} }, { ...empty(), extra: true },
    { version: 0, favorites: [], playlists: [] }, { ...empty(), blocked_artist_ids: ["x".repeat(1048576)] }]) {
    await assert.rejects(rpc(service, "dacha_cloud_library_put", [two.hash, snapshot]), code("PT400"));
  }
});

test("concurrent saves use compare-and-swap and never silently overwrite", async () => {
  const person = await identity(), other = await connect("service_role");
  try {
    const outcomes = await Promise.allSettled([
      rpc(service, "dacha_cloud_library_put", [person.hash, { ...empty(), blocked_artist_ids: ["one"] }]),
      rpc(other, "dacha_cloud_library_put", [person.hash, { ...empty(), blocked_artist_ids: ["two"] }]),
    ]);
    assert.equal(outcomes.filter((value) => value.status === "fulfilled").length, 1);
    assert.equal(outcomes.find((value) => value.status === "rejected").reason.code, "PT409");
    const stored = await rpc(service, "dacha_cloud_library_get", [person.hash]);
    assert.deepEqual(stored, outcomes.find((value) => value.status === "fulfilled").value);
    assert.equal(stored.version, 1);
  } finally { await other.end(); }
});

test("deletion revokes every session and pending saves cannot recreate an account", async () => {
  const person = await identity(), second = await identity(person.accountID), writer = await connect("service_role");
  const pid = (await writer.query("select pg_backend_pid() as pid")).rows[0].pid;
  await service.query("begin");
  try {
    await rpc(service, "dacha_cloud_delete_account", [person.hash]);
    const save = rpc(writer, "dacha_cloud_library_put", [second.hash, empty()]);
    const rejected = assert.rejects(save, code("PT401"));
    await waitUntilBlocked(pid);
    await service.query("commit");
    await rejected;
    for (const table of ["accounts", "sessions", "libraries"]) {
      assert.equal((await admin.query(`select count(*)::int as n from dacha_cloud.${table} where account_id=$1`, [person.accountID])).rows[0].n, 0);
    }
    await assert.rejects(rpc(service, "dacha_cloud_library_get", [person.hash]), code("PT401"));
  } finally { await service.query("rollback"); await writer.end(); }
});

test("a save that wins the lock is still fully removed by a following deletion", async () => {
  const person = await identity(), deleter = await connect("service_role");
  const pid = (await deleter.query("select pg_backend_pid() as pid")).rows[0].pid;
  await service.query("begin");
  try {
    await rpc(service, "dacha_cloud_library_put", [person.hash, { ...empty(), blocked_artist_ids: ["saved-first"] }]);
    const deletion = rpc(deleter, "dacha_cloud_delete_account", [person.hash]);
    await waitUntilBlocked(pid);
    await service.query("commit");
    assert.deepEqual(await deletion, { ok: true });
    assert.equal((await admin.query("select count(*)::int as n from dacha_cloud.libraries where account_id=$1", [person.accountID])).rows[0].n, 0);
  } finally { await service.query("rollback"); await deleter.end(); }
});

test("a save waiting behind logout rechecks the revoked token before writing", async () => {
  const person = await identity(), writer = await connect("service_role");
  const pid = (await writer.query("select pg_backend_pid() as pid")).rows[0].pid;
  await service.query("begin");
  try {
    await rpc(service, "dacha_cloud_logout", [person.hash]);
    const save = rpc(writer, "dacha_cloud_library_put", [person.hash, empty()]);
    const rejected = assert.rejects(save, code("PT401"));
    await waitUntilBlocked(pid);
    await service.query("commit");
    await rejected;
    assert.equal((await admin.query("select version from dacha_cloud.libraries where account_id=$1", [person.accountID])).rows[0].version, 0);
  } finally { await service.query("rollback"); await writer.end(); }
});

test("logout revokes just the current session; expiry denies an otherwise valid token", async () => {
  const person = await identity(), second = await identity(person.accountID);
  assert.deepEqual(await rpc(service, "dacha_cloud_logout", [person.hash]), { ok: true });
  await assert.rejects(rpc(service, "dacha_cloud_library_get", [person.hash]), code("PT401"));
  assert.deepEqual(await rpc(service, "dacha_cloud_library_get", [second.hash]), empty());
  await admin.query("update dacha_cloud.sessions set expires_at=clock_timestamp()-interval '1 second' where token_hash=$1", [second.hash]);
  await assert.rejects(rpc(service, "dacha_cloud_library_get", [second.hash]), code("PT401"));
});

test("rate counter permits 120 calls, denies further calls and cleans expired records", async () => {
  const expired = await challenge(), person = await identity();
  await admin.query("update dacha_cloud.challenges set expires_at=clock_timestamp()-interval '1 second' where id=$1", [expired.id]);
  await admin.query("update dacha_cloud.sessions set expires_at=clock_timestamp()-interval '1 second' where token_hash=$1", [person.hash]);
  await admin.query("update dacha_cloud.auth_rate set started_at=clock_timestamp(),attempts=0");
  for (let attempt = 0; attempt < 120; attempt++) assert.equal((await rpc(service, "dacha_cloud_auth_rate")).allowed, true);
  const denied = await rpc(service, "dacha_cloud_auth_rate");
  assert.equal(denied.allowed, false);
  assert.ok(denied.retry_after_seconds >= 1 && denied.retry_after_seconds <= 60);
  assert.equal((await admin.query("select count(*)::int as n from dacha_cloud.auth_rate")).rows[0].n, 1);
  assert.equal((await admin.query("select count(*)::int as n from dacha_cloud.challenges where id=$1", [expired.id])).rows[0].n, 0);
  assert.equal((await admin.query("select count(*)::int as n from dacha_cloud.sessions where token_hash=$1", [person.hash])).rows[0].n, 0);
  await admin.query("update dacha_cloud.auth_rate set started_at=clock_timestamp()-interval '61 seconds'");
  assert.equal((await rpc(service, "dacha_cloud_auth_rate")).allowed, true);
});

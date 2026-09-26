-- Mobile listener data is deliberately independent of public/custodial users.
CREATE TABLE mobile_accounts (id UUID PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE mobile_identities (
 provider TEXT NOT NULL CHECK(provider IN ('apple','meteor')), subject TEXT NOT NULL,
 account_id UUID NOT NULL REFERENCES mobile_accounts(id) ON DELETE CASCADE,
 apple_refresh_token TEXT, PRIMARY KEY(provider,subject)
);
CREATE TABLE mobile_sessions (token_hash TEXT PRIMARY KEY, account_id UUID NOT NULL REFERENCES mobile_accounts(id) ON DELETE CASCADE, expires_at TIMESTAMPTZ NOT NULL);
CREATE INDEX mobile_sessions_account ON mobile_sessions(account_id);
CREATE TABLE mobile_challenges (id UUID PRIMARY KEY, nonce BYTEA NOT NULL CHECK(octet_length(nonce)=32), message TEXT NOT NULL, recipient TEXT NOT NULL, code_challenge TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL);
CREATE TABLE mobile_codes (code_hash TEXT PRIMARY KEY, account_id UUID NOT NULL REFERENCES mobile_accounts(id) ON DELETE CASCADE, code_challenge TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL);
CREATE TABLE mobile_libraries (account_id UUID PRIMARY KEY REFERENCES mobile_accounts(id) ON DELETE CASCADE, version BIGINT NOT NULL DEFAULT 0 CHECK(version>=0), snapshot JSONB NOT NULL DEFAULT '{"favorites":[],"playlists":[],"blocked_artist_ids":[]}');
-- Explicit operator approval; audio validation alone never exposes a track.
CREATE TABLE mobile_catalog_approvals (song_id INTEGER PRIMARY KEY REFERENCES songs(id) ON DELETE CASCADE, approved_at TIMESTAMPTZ NOT NULL DEFAULT now(), approved_by TEXT NOT NULL CHECK(length(approved_by)>0));
CREATE TABLE mobile_reports (id UUID PRIMARY KEY, account_id UUID REFERENCES mobile_accounts(id) ON DELETE SET NULL, track_id TEXT, artist_id TEXT, reason TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), resolved_at TIMESTAMPTZ, CHECK(track_id IS NOT NULL OR artist_id IS NOT NULL));
CREATE INDEX mobile_reports_pending ON mobile_reports(created_at) WHERE resolved_at IS NULL;

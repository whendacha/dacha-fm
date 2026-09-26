//! Isolated listener API. Never calls upstream wallet provisioning or public voting.
use crate::AppState;
use axum::{
    extract::{DefaultBodyLimit, Query, State},
    http::{HeaderMap, StatusCode},
    routing::{delete, get, post},
    Json, Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::{DateTime, Utc};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::{
    collections::{HashMap, HashSet},
    sync::{Mutex, OnceLock},
    time::{Duration, Instant},
};
use uuid::Uuid;
mod apple;
#[cfg(test)]
mod tests;
type Error = (StatusCode, String);
type Result<T> = std::result::Result<T, Error>;
fn bad(s: &str) -> Error {
    (StatusCode::BAD_REQUEST, s.into())
}
fn unauthorized() -> Error {
    (StatusCode::UNAUTHORIZED, "Authentication required".into())
}
fn unavailable() -> Error {
    (
        StatusCode::SERVICE_UNAVAILABLE,
        "Integration unavailable".into(),
    )
}
fn db_error(e: sqlx::Error) -> Error {
    tracing::error!(error=%e,"Mobile database operation failed");
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        "Database operation failed".into(),
    )
}
fn hash(s: &str) -> String {
    hex::encode(Sha256::digest(s.as_bytes()))
}
fn random_token() -> String {
    let mut b = [0; 32];
    rand::thread_rng().fill_bytes(&mut b);
    URL_SAFE_NO_PAD.encode(b)
}
fn env(s: &str) -> Option<String> {
    std::env::var(s).ok().filter(|v| !v.trim().is_empty())
}
fn https(s: &str) -> bool {
    reqwest::Url::parse(s)
        .map(|u| {
            u.scheme() == "https"
                && u.host_str().is_some()
                && u.username().is_empty()
                && u.password().is_none()
        })
        .unwrap_or(false)
}
fn meteor_config() -> Result<(String, String, String)> {
    let domain = env("MOBILE_AUTH_DOMAIN").ok_or_else(unavailable)?;
    let recipient = env("MOBILE_NEP413_RECIPIENT").ok_or_else(unavailable)?;
    let rpc = env("MOBILE_NEAR_RPC_URL").ok_or_else(unavailable)?;
    if !https(&domain) || !https(&rpc) || recipient.len() > 255 {
        return Err(unavailable());
    }
    Ok((domain, recipient, rpc))
}
pub fn router() -> Router<AppState> {
    Router::new()
        .nest(
            "/api/mobile/v1",
            Router::new()
                .route("/config", get(config))
                .route("/tracks", get(tracks))
                .route("/artists", get(artists))
                .route("/library", get(library_get).put(library_put))
                .route("/reports", post(report))
                .route("/auth/meteor/challenge", post(challenge))
                .route("/auth/meteor/verify", post(verify))
                .route("/auth/exchange", post(exchange))
                .route("/auth/apple", post(apple::login))
                .route("/auth/logout", post(logout))
                .route("/account", delete(delete_account)),
        )
        .layer(DefaultBodyLimit::max(1024 * 1024))
        .layer(axum::middleware::from_fn(no_store))
}
async fn no_store(
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let mut response = next.run(request).await;
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        axum::http::HeaderValue::from_static("no-store"),
    );
    response
}
async fn config() -> Json<Value> {
    Json(
        json!({"meteor_enabled":meteor_config().is_ok(),"apple_enabled":apple::configured(),"privacy_url":env("MOBILE_PRIVACY_URL").filter(|s|https(s)),"support_url":env("MOBILE_SUPPORT_URL").filter(|s|https(s))}),
    )
}
// Bounded process-global limiter cannot be bypassed using untrusted forwarding headers.
// Deployments additionally need edge per-IP limits; this protects RPC and anonymous writes.
fn throttle(bucket: &'static str, max: u32) -> Result<()> {
    static COUNTERS: OnceLock<Mutex<HashMap<&'static str, (Instant, u32)>>> = OnceLock::new();
    let mut map = COUNTERS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .map_err(|_| unavailable())?;
    let entry = map.entry(bucket).or_insert((Instant::now(), 0));
    if entry.0.elapsed() > Duration::from_secs(60) {
        *entry = (Instant::now(), 0)
    }
    if entry.1 >= max {
        return Err((StatusCode::TOO_MANY_REQUESTS, "Try again later".into()));
    }
    entry.1 += 1;
    Ok(())
}
async fn user(s: &AppState, h: &HeaderMap) -> Result<Uuid> {
    let token = h
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .filter(|v| v.len() == 43)
        .ok_or_else(unauthorized)?;
    sqlx::query_scalar(
        "SELECT account_id FROM mobile_sessions WHERE token_hash=$1 AND expires_at>now()",
    )
    .bind(hash(token))
    .fetch_optional(&s.db)
    .await
    .map_err(db_error)?
    .ok_or_else(unauthorized)
}
async fn optional_user(s: &AppState, h: &HeaderMap) -> Result<Option<Uuid>> {
    if h.contains_key("authorization") {
        Ok(Some(user(s, h).await?))
    } else {
        Ok(None)
    }
}
async fn session(tx: &mut sqlx::Transaction<'_, sqlx::Postgres>, id: Uuid) -> Result<Value> {
    let token = random_token();
    sqlx::query("INSERT INTO mobile_sessions VALUES($1,$2,now()+interval '30 days')")
        .bind(hash(&token))
        .bind(id)
        .execute(&mut **tx)
        .await
        .map_err(db_error)?;
    Ok(json!({"access_token":token,"user_id":id}))
}
async fn identity(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    provider: &str,
    subject: &str,
    refresh: Option<&str>,
) -> Result<Uuid> {
    // Serialize concurrent first-login and deletion for the same provider subject.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
        .bind(format!("{}:{}", provider, subject))
        .execute(&mut **tx)
        .await
        .map_err(db_error)?;
    let existing: Option<Uuid> = sqlx::query_scalar(
        "SELECT account_id FROM mobile_identities WHERE provider=$1 AND subject=$2",
    )
    .bind(provider)
    .bind(subject)
    .fetch_optional(&mut **tx)
    .await
    .map_err(db_error)?;
    let id = if let Some(id) = existing {
        id
    } else {
        let id = Uuid::new_v4();
        sqlx::query("INSERT INTO mobile_accounts VALUES($1,now())")
            .bind(id)
            .execute(&mut **tx)
            .await
            .map_err(db_error)?;
        sqlx::query("INSERT INTO mobile_identities(provider,subject,account_id) VALUES($1,$2,$3)")
            .bind(provider)
            .bind(subject)
            .bind(id)
            .execute(&mut **tx)
            .await
            .map_err(db_error)?;
        sqlx::query("INSERT INTO mobile_libraries(account_id) VALUES($1)")
            .bind(id)
            .execute(&mut **tx)
            .await
            .map_err(db_error)?;
        id
    };
    if let Some(token) = refresh {
        sqlx::query(
            "UPDATE mobile_identities SET apple_refresh_token=$1 WHERE provider=$2 AND subject=$3",
        )
        .bind(token)
        .bind(provider)
        .bind(subject)
        .execute(&mut **tx)
        .await
        .map_err(db_error)?;
    }
    Ok(id)
}
#[derive(Clone, Debug, Serialize, Deserialize, sqlx::FromRow)]
struct Track {
    id: String,
    title: String,
    artist_id: String,
    artist_name: String,
    audio_url: String,
    artwork_url: Option<String>,
    duration: Option<f64>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
struct Playlist {
    id: String,
    name: String,
    tracks: Vec<Track>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct Library {
    #[serde(default)]
    version: i64,
    favorites: Vec<Track>,
    playlists: Vec<Playlist>,
    blocked_artist_ids: Vec<String>,
}
const CATALOG: &str = r#"
    SELECT s.uuid AS id, s.title, u.id::text AS artist_id,
           COALESCE(u.display_name,u.account_id) AS artist_name,
           s.audio_url,
           CASE WHEN s.cover_image_url LIKE 'https://%' THEN s.cover_image_url END AS artwork_url,
           s.audio_duration_seconds::float8 AS duration
    FROM songs s
    JOIN users u ON u.id=s.uploader_id
    JOIN mobile_catalog_approvals a ON a.song_id=s.id
    WHERE s.is_validated AND NOT s.is_hidden AND NOT s.is_deleted
      AND NOT u.is_banned AND s.audio_url LIKE 'https://%'
"#;
#[derive(Deserialize)]
struct Page {
    q: Option<String>,
    artist_id: Option<String>,
    page: Option<i64>,
    limit: Option<i64>,
}
fn page_args(page: i64, limit: i64) -> Result<(i64, i64)> {
    if !(1..=10000).contains(&page) || !(1..=100).contains(&limit) {
        return Err(bad("Invalid pagination"));
    }
    Ok(((page - 1) * limit, limit))
}
async fn blocked(s: &AppState, h: &HeaderMap) -> Result<Vec<String>> {
    if let Some(id) = optional_user(s, h).await? {
        let v: Value =
            sqlx::query_scalar("SELECT snapshot FROM mobile_libraries WHERE account_id=$1")
                .bind(id)
                .fetch_one(&s.db)
                .await
                .map_err(db_error)?;
        Ok(serde_json::from_value::<Library>(v)
            .map_err(|_| unavailable())?
            .blocked_artist_ids)
    } else {
        Ok(vec![])
    }
}
async fn tracks(
    State(s): State<AppState>,
    h: HeaderMap,
    Query(p): Query<Page>,
) -> Result<Json<Value>> {
    let page = p.page.unwrap_or(1);
    let (offset, limit) = page_args(page, p.limit.unwrap_or(30))?;
    let blocks = blocked(&s, &h).await?;
    let q = p.q.unwrap_or_default();
    if q.len() > 200 {
        return Err(bad("Search too long"));
    }
    let mut rows=sqlx::query_as::<_,Track>(&format!("{CATALOG} AND NOT(u.id::text=ANY($1)) AND ($2='' OR s.title ILIKE '%'||$2||'%' OR COALESCE(u.display_name,u.account_id) ILIKE '%'||$2||'%') AND ($3::text IS NULL OR u.id::text=$3) ORDER BY s.id DESC LIMIT $4 OFFSET $5")).bind(blocks).bind(q).bind(p.artist_id).bind(limit+1).bind(offset).fetch_all(&s.db).await.map_err(db_error)?;
    let more = rows.len() > limit as usize;
    rows.truncate(limit as usize);
    Ok(Json(json!({"tracks":rows,"page":page,"has_more":more})))
}
async fn artists(
    State(s): State<AppState>,
    h: HeaderMap,
    Query(p): Query<Page>,
) -> Result<Json<Value>> {
    let page = p.page.unwrap_or(1);
    let (offset, limit) = page_args(page, p.limit.unwrap_or(30))?;
    let blocks = blocked(&s, &h).await?;
    let q = p.q.unwrap_or_default();
    if q.len() > 200 {
        return Err(bad("Search too long"));
    }
    let rows=sqlx::query(&format!("SELECT artist_id AS id,artist_name AS name,count(*) AS track_count FROM ({CATALOG}) c WHERE NOT(artist_id=ANY($1)) AND artist_name ILIKE '%'||$2||'%' GROUP BY artist_id,artist_name ORDER BY artist_id LIMIT $3 OFFSET $4")).bind(blocks).bind(q).bind(limit+1).bind(offset).fetch_all(&s.db).await.map_err(db_error)?;
    let more = rows.len() > limit as usize;
    let artists:Vec<Value>=rows.iter().take(limit as usize).map(|r|json!({"id":r.get::<String,_>("id"),"name":r.get::<String,_>("name"),"artwork_url":null,"track_count":r.get::<i64,_>("track_count")})).collect();
    Ok(Json(json!({"artists":artists,"page":page,"has_more":more})))
}
fn validate_library(l: &Library) -> Result<()> {
    if l.version < 0
        || l.favorites.len() > 2000
        || l.playlists.len() > 100
        || l.blocked_artist_ids.len() > 1000
        || l.playlists.iter().map(|p| p.tracks.len()).sum::<usize>() > 10000
    {
        return Err(bad("Library limit exceeded"));
    }
    let mut ids = HashSet::new();
    for p in &l.playlists {
        if p.id.is_empty()
            || p.id.len() > 128
            || !ids.insert(&p.id)
            || p.name.trim().is_empty()
            || p.name.chars().count() > 100
            || p.name.chars().any(char::is_control)
            || p.tracks.len() > 2000
        {
            return Err(bad("Invalid playlist"));
        }
    }
    if l.blocked_artist_ids
        .iter()
        .any(|s| s.parse::<i32>().map(|v| v <= 0).unwrap_or(true))
    {
        return Err(bad("Invalid artist"));
    }
    Ok(())
}
async fn canonicalize(s: &AppState, l: &mut Library, strict: bool) -> Result<()> {
    let ids: Vec<String> = l
        .favorites
        .iter()
        .chain(l.playlists.iter().flat_map(|p| p.tracks.iter()))
        .map(|t| t.id.clone())
        .collect();
    let tracks = sqlx::query_as::<_, Track>(&format!("{CATALOG} AND s.uuid=ANY($1)"))
        .bind(&ids)
        .fetch_all(&s.db)
        .await
        .map_err(db_error)?;
    let map: HashMap<String, Track> = tracks.into_iter().map(|t| (t.id.clone(), t)).collect();
    if strict && ids.iter().any(|id| !map.contains_key(id)) {
        return Err(bad("Track unavailable"));
    }
    let blocks: HashSet<_> = l.blocked_artist_ids.iter().cloned().collect();
    let clean = |list: &mut Vec<Track>| {
        let mut seen = HashSet::new();
        *list = list
            .iter()
            .filter_map(|t| map.get(&t.id))
            .filter(|t| !blocks.contains(&t.artist_id) && seen.insert(t.id.clone()))
            .cloned()
            .collect()
    };
    clean(&mut l.favorites);
    for p in &mut l.playlists {
        clean(&mut p.tracks)
    }
    l.blocked_artist_ids.sort();
    l.blocked_artist_ids.dedup();
    Ok(())
}
async fn library_get(State(s): State<AppState>, h: HeaderMap) -> Result<Json<Library>> {
    let id = user(&s, &h).await?;
    let row = sqlx::query("SELECT version,snapshot FROM mobile_libraries WHERE account_id=$1")
        .bind(id)
        .fetch_one(&s.db)
        .await
        .map_err(db_error)?;
    let mut l: Library = serde_json::from_value(row.get("snapshot")).map_err(|_| unavailable())?;
    l.version = row.get("version");
    canonicalize(&s, &mut l, false).await?;
    Ok(Json(l))
}
async fn library_put(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(mut l): Json<Library>,
) -> Result<Json<Library>> {
    let id = user(&s, &h).await?;
    validate_library(&l)?;
    canonicalize(&s, &mut l, true).await?;
    let version = l.version;
    l.version = l
        .version
        .checked_add(1)
        .ok_or_else(|| bad("Invalid version"))?;
    let r=sqlx::query("UPDATE mobile_libraries SET snapshot=$1,version=version+1 WHERE account_id=$2 AND version=$3").bind(serde_json::to_value(&l).unwrap()).bind(id).bind(version).execute(&s.db).await.map_err(db_error)?;
    if r.rows_affected() != 1 {
        return Err((
            StatusCode::CONFLICT,
            "Library changed; fetch and merge explicitly".into(),
        ));
    }
    Ok(Json(l))
}
#[derive(Deserialize)]
struct Report {
    track_id: Option<String>,
    artist_id: Option<String>,
    reason: String,
}
async fn report(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(r): Json<Report>,
) -> Result<StatusCode> {
    throttle("reports", 30)?;
    let id = optional_user(&s, &h).await?;
    if r.reason.trim().is_empty()
        || r.reason.len() > 2000
        || r.track_id.is_none() && r.artist_id.is_none()
    {
        return Err(bad("Invalid report"));
    }
    if let Some(t) = &r.track_id {
        let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM songs WHERE uuid=$1)")
            .bind(t)
            .fetch_one(&s.db)
            .await
            .map_err(db_error)?;
        if !exists {
            return Err(bad("Unknown track"));
        }
    }
    if let Some(a) = &r.artist_id {
        let a = a.parse::<i32>().map_err(|_| bad("Invalid artist"))?;
        let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM users WHERE id=$1)")
            .bind(a)
            .fetch_one(&s.db)
            .await
            .map_err(db_error)?;
        if !exists {
            return Err(bad("Unknown artist"));
        }
    }
    sqlx::query("INSERT INTO mobile_reports(id,account_id,track_id,artist_id,reason) VALUES($1,$2,$3,$4,$5)").bind(Uuid::new_v4()).bind(id).bind(r.track_id).bind(r.artist_id).bind(r.reason).execute(&s.db).await.map_err(db_error)?;
    Ok(StatusCode::CREATED)
}
#[derive(Deserialize)]
struct ChallengeRequest {
    code_challenge: String,
}
fn valid_challenge(c: &str) -> bool {
    c.len() == 43
        && URL_SAFE_NO_PAD
            .decode(c)
            .map(|v| v.len() == 32)
            .unwrap_or(false)
}
fn verify_pkce(v: &str, c: &str) -> bool {
    (43..=128).contains(&v.len())
        && v.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-._~".contains(&b))
        && URL_SAFE_NO_PAD.encode(Sha256::digest(v.as_bytes())) == c
}
fn challenge_live(e: DateTime<Utc>) -> bool {
    e > Utc::now()
}
async fn challenge(
    State(s): State<AppState>,
    Json(r): Json<ChallengeRequest>,
) -> Result<Json<Value>> {
    throttle("auth", 120)?;
    let (domain, recipient, _) = meteor_config()?;
    if !valid_challenge(&r.code_challenge) {
        return Err(bad("Invalid PKCE challenge"));
    }
    let id = Uuid::new_v4();
    let mut nonce = [0; 32];
    rand::thread_rng().fill_bytes(&mut nonce);
    let message=format!("Sign in to {domain} as a Dacha FM listener. No transaction or wallet permission is requested. Challenge: {id}");
    let expires = Utc::now() + chrono::Duration::minutes(5);
    sqlx::query("INSERT INTO mobile_challenges VALUES($1,$2,$3,$4,$5,$6)")
        .bind(id)
        .bind(nonce.to_vec())
        .bind(&message)
        .bind(&recipient)
        .bind(r.code_challenge)
        .bind(expires)
        .execute(&s.db)
        .await
        .map_err(db_error)?;
    Ok(Json(
        json!({"id":id,"message":message,"nonce":nonce.to_vec(),"recipient":recipient,"expires_at":expires}),
    ))
}
#[derive(Deserialize)]
struct Verify {
    challenge_id: Uuid,
    account_id: String,
    public_key: String,
    signature: String,
}
async fn verify(State(s): State<AppState>, Json(r): Json<Verify>) -> Result<Json<Value>> {
    throttle("auth", 120)?;
    let (_, _, rpc) = meteor_config()?;
    if r.account_id
        .parse::<near_primitives::types::AccountId>()
        .is_err()
        || !r.public_key.starts_with("ed25519:")
        || r.signature.len() > 128
    {
        return Err(bad("Invalid proof"));
    }
    let row = sqlx::query("SELECT * FROM mobile_challenges WHERE id=$1 AND expires_at>now()")
        .bind(r.challenge_id)
        .fetch_optional(&s.db)
        .await
        .map_err(db_error)?
        .ok_or_else(unauthorized)?;
    let nonce: Vec<u8> = row.get("nonce");
    if nonce.len() != 32
        || !challenge_live(row.get("expires_at"))
        || !crate::auth::nep413::verify_nep413_signature(
            &r.public_key,
            &r.signature,
            &row.get::<String, _>("message"),
            &nonce,
            &row.get::<String, _>("recipient"),
        )
        .unwrap_or(false)
    {
        return Err(unauthorized());
    }
    let response:Value=s.http_client.post(rpc).timeout(Duration::from_secs(10)).json(&json!({"jsonrpc":"2.0","id":"mobile","method":"query","params":{"request_type":"view_access_key","finality":"final","account_id":r.account_id,"public_key":r.public_key}})).send().await.map_err(|_|unavailable())?.error_for_status().map_err(|_|unavailable())?.json().await.map_err(|_|unavailable())?;
    if response.get("error").is_some()
        || response
            .pointer("/result/permission")
            .and_then(Value::as_str)
            != Some("FullAccess")
    {
        return Err(unauthorized());
    }
    let mut tx = s.db.begin().await.map_err(db_error)?;
    let consumed = sqlx::query("DELETE FROM mobile_challenges WHERE id=$1 AND expires_at>now()")
        .bind(r.challenge_id)
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    if consumed.rows_affected() != 1 {
        return Err(unauthorized());
    }
    let id = identity(&mut tx, "meteor", &r.account_id, None).await?;
    let code = random_token();
    sqlx::query("INSERT INTO mobile_codes VALUES($1,$2,$3,now()+interval '60 seconds')")
        .bind(hash(&code))
        .bind(id)
        .bind(row.get::<String, _>("code_challenge"))
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    tx.commit().await.map_err(db_error)?;
    Ok(Json(json!({"code":code})))
}
#[derive(Deserialize)]
struct Exchange {
    code: String,
    code_verifier: String,
}
async fn exchange(State(s): State<AppState>, Json(r): Json<Exchange>) -> Result<Json<Value>> {
    throttle("auth", 120)?;
    let mut tx = s.db.begin().await.map_err(db_error)?;
    let row=sqlx::query("SELECT account_id,code_challenge FROM mobile_codes WHERE code_hash=$1 AND expires_at>now() FOR UPDATE").bind(hash(&r.code)).fetch_optional(&mut *tx).await.map_err(db_error)?.ok_or_else(unauthorized)?;
    if !verify_pkce(&r.code_verifier, &row.get::<String, _>("code_challenge")) {
        return Err(unauthorized());
    }
    sqlx::query("DELETE FROM mobile_codes WHERE code_hash=$1")
        .bind(hash(&r.code))
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    let result = session(&mut tx, row.get("account_id")).await?;
    tx.commit().await.map_err(db_error)?;
    Ok(Json(result))
}
async fn logout(State(s): State<AppState>, h: HeaderMap) -> Result<StatusCode> {
    user(&s, &h).await?;
    let token = h
        .get("authorization")
        .unwrap()
        .to_str()
        .unwrap()
        .strip_prefix("Bearer ")
        .unwrap();
    sqlx::query("DELETE FROM mobile_sessions WHERE token_hash=$1")
        .bind(hash(token))
        .execute(&s.db)
        .await
        .map_err(db_error)?;
    Ok(StatusCode::NO_CONTENT)
}
async fn delete_account(State(s): State<AppState>, h: HeaderMap) -> Result<StatusCode> {
    let id = user(&s, &h).await?;
    let mut tx = s.db.begin().await.map_err(db_error)?;
    let identities = sqlx::query(
        "SELECT provider,subject,apple_refresh_token FROM mobile_identities WHERE account_id=$1",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await
    .map_err(db_error)?;
    for r in identities {
        let provider: String = r.get("provider");
        let subject: String = r.get("subject");
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
            .bind(format!("{}:{}", provider, subject))
            .execute(&mut *tx)
            .await
            .map_err(db_error)?;
        if provider == "apple" {
            // Re-read after the identity lock: a concurrent login may have rotated it.
            let token: Option<String> = sqlx::query_scalar("SELECT apple_refresh_token FROM mobile_identities WHERE account_id=$1 AND provider='apple'")
                .bind(id).fetch_optional(&mut *tx).await.map_err(db_error)?.flatten();
            apple::revoke(&s, token.ok_or_else(unavailable)?).await?;
        }
    }
    sqlx::query("DELETE FROM mobile_accounts WHERE id=$1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    tx.commit().await.map_err(db_error)?;
    Ok(StatusCode::NO_CONTENT)
}

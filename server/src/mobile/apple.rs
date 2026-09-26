use super::*;
use aes_gcm::{aead::Aead, Aes256Gcm, KeyInit, Nonce};
use jsonwebtoken::{Algorithm, DecodingKey, Validation};
#[derive(Deserialize)]
pub(super) struct Login {
    identity_token: String,
    nonce: String,
    authorization_code: String,
}
#[derive(Deserialize)]
struct Claims {
    sub: String,
    nonce: String,
    exp: u64,
}
struct Config {
    client_id: String,
    client_secret: String,
    key: [u8; 32],
}
fn configuration() -> Result<Config> {
    let client_id = env("MOBILE_APPLE_CLIENT_ID").ok_or_else(unavailable)?;
    let client_secret = env("MOBILE_APPLE_CLIENT_SECRET").ok_or_else(unavailable)?;
    let bytes = URL_SAFE_NO_PAD
        .decode(env("MOBILE_TOKEN_ENCRYPTION_KEY").ok_or_else(unavailable)?)
        .map_err(|_| unavailable())?;
    let key: [u8; 32] = bytes.try_into().map_err(|_| unavailable())?;
    Ok(Config {
        client_id,
        client_secret,
        key,
    })
}
pub(super) fn configured() -> bool {
    configuration().is_ok()
}
fn encrypt(key: &[u8; 32], plaintext: &str) -> Result<String> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| unavailable())?;
    let mut nonce = [0; 12];
    rand::thread_rng().fill_bytes(&mut nonce);
    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce), plaintext.as_bytes())
        .map_err(|_| unavailable())?;
    let mut bytes = nonce.to_vec();
    bytes.extend(ciphertext);
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}
fn decrypt(key: &[u8; 32], encrypted: &str) -> Result<String> {
    let bytes = URL_SAFE_NO_PAD
        .decode(encrypted)
        .map_err(|_| unavailable())?;
    if bytes.len() < 28 {
        return Err(unavailable());
    }
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| unavailable())?;
    String::from_utf8(
        cipher
            .decrypt(Nonce::from_slice(&bytes[..12]), &bytes[12..])
            .map_err(|_| unavailable())?,
    )
    .map_err(|_| unavailable())
}
async fn claims(s: &AppState, c: &Config, token: &str, nonce: &str) -> Result<Claims> {
    let header = jsonwebtoken::decode_header(token).map_err(|_| unauthorized())?;
    if header.alg != Algorithm::RS256 {
        return Err(unauthorized());
    }
    let kid = header.kid.ok_or_else(unauthorized)?;
    let keys: jsonwebtoken::jwk::JwkSet = s
        .http_client
        .get("https://appleid.apple.com/auth/keys")
        .timeout(Duration::from_secs(10))
        .send()
        .await
        .map_err(|_| unavailable())?
        .error_for_status()
        .map_err(|_| unavailable())?
        .json()
        .await
        .map_err(|_| unavailable())?;
    let key = keys.find(&kid).ok_or_else(unauthorized)?;
    let key = DecodingKey::from_jwk(key).map_err(|_| unauthorized())?;
    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_audience(&[&c.client_id]);
    validation.set_issuer(&["https://appleid.apple.com"]);
    validation.leeway = 0;
    let claims = jsonwebtoken::decode::<Claims>(token, &key, &validation)
        .map_err(|_| unauthorized())?
        .claims;
    if claims.sub.is_empty()
        || claims.nonce != hash(nonce)
        || claims.exp <= Utc::now().timestamp() as u64
    {
        return Err(unauthorized());
    }
    Ok(claims)
}
pub(super) async fn login(State(s): State<AppState>, Json(r): Json<Login>) -> Result<Json<Value>> {
    throttle("auth", 120)?;
    let c = configuration()?;
    if !(32..=256).contains(&r.nonce.len())
        || r.authorization_code.is_empty()
        || r.authorization_code.len() > 4096
        || r.identity_token.len() > 16384
    {
        return Err(bad("Invalid Apple credentials"));
    }
    let identity_claims = claims(&s, &c, &r.identity_token, &r.nonce).await?;
    let response = s
        .http_client
        .post("https://appleid.apple.com/auth/token")
        .timeout(Duration::from_secs(15))
        .form(&[
            ("client_id", c.client_id.as_str()),
            ("client_secret", c.client_secret.as_str()),
            ("code", r.authorization_code.as_str()),
            ("grant_type", "authorization_code"),
        ])
        .send()
        .await
        .map_err(|_| unavailable())?;
    if !response.status().is_success() {
        return Err((StatusCode::BAD_GATEWAY, "Apple code exchange failed".into()));
    }
    let tokens: Value = response.json().await.map_err(|_| unavailable())?;
    let id_token = tokens
        .get("id_token")
        .and_then(Value::as_str)
        .ok_or_else(unauthorized)?;
    let exchanged = claims(&s, &c, id_token, &r.nonce).await?;
    if exchanged.sub != identity_claims.sub {
        return Err(unauthorized());
    }
    let refresh = tokens
        .get("refresh_token")
        .and_then(Value::as_str)
        .filter(|v| !v.is_empty())
        .ok_or_else(unavailable)?;
    let encrypted = encrypt(&c.key, refresh)?;
    let mut tx = s.db.begin().await.map_err(db_error)?;
    let id = identity(&mut tx, "apple", &identity_claims.sub, Some(&encrypted)).await?;
    let session = session(&mut tx, id).await?;
    tx.commit().await.map_err(db_error)?;
    Ok(Json(session))
}
pub(super) async fn revoke(s: &AppState, encrypted: String) -> Result<()> {
    let c = configuration()?;
    let token = decrypt(&c.key, &encrypted)?;
    let response = s
        .http_client
        .post("https://appleid.apple.com/auth/revoke")
        .timeout(Duration::from_secs(15))
        .form(&[
            ("client_id", c.client_id.as_str()),
            ("client_secret", c.client_secret.as_str()),
            ("token", token.as_str()),
            ("token_type_hint", "refresh_token"),
        ])
        .send()
        .await
        .map_err(|_| unavailable())?;
    if !response.status().is_success() {
        return Err((
            StatusCode::BAD_GATEWAY,
            "Apple revocation failed; account retained".into(),
        ));
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn encrypted_tokens_authenticate() {
        let key = [1; 32];
        let enc = encrypt(&key, "refresh-secret").unwrap();
        assert_eq!(decrypt(&key, &enc).unwrap(), "refresh-secret");
        assert!(decrypt(&[2; 32], &enc).is_err());
        assert!(!enc.contains("refresh-secret"));
    }
}

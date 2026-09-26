use super::*;
#[test]
fn pagination_bounds() {
    assert!(page_args(0, 30).is_err());
    assert!(page_args(1, 101).is_err());
    assert_eq!(page_args(2, 30).unwrap(), (30, 30));
}
#[test]
fn pkce_rfc_vector() {
    assert!(verify_pkce(
        "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    ));
    assert!(!verify_pkce("short", "anything"));
}
#[test]
fn library_validation() {
    let mut s = Library::default();
    s.playlists.push(Playlist {
        id: "x".into(),
        name: " ".into(),
        tracks: vec![],
    });
    assert!(validate_library(&s).is_err());
    s.playlists[0].name = "My music".into();
    assert!(validate_library(&s).is_ok());
    s.playlists.push(s.playlists[0].clone());
    assert!(validate_library(&s).is_err());
}
#[test]
fn challenge_expiry() {
    assert!(!challenge_live(
        chrono::Utc::now() - chrono::Duration::seconds(1)
    ));
    assert!(challenge_live(
        chrono::Utc::now() + chrono::Duration::seconds(60)
    ));
}
#[test]
fn nep413_binds_recipient_nonce_and_callback() {
    use ed25519_dalek::{Signer, SigningKey};
    let key = SigningKey::from_bytes(&[7; 32]);
    let nonce = [1; 32];
    #[derive(borsh::BorshSerialize)]
    struct Payload {
        tag: u32,
        message: String,
        nonce: [u8; 32],
        recipient: String,
        callback: Option<String>,
    }
    let payload = Payload {
        tag: (1 << 31) + 413,
        message: "Login".into(),
        nonce,
        recipient: "example.org".into(),
        callback: None,
    };
    let sig = key.sign(&Sha256::digest(borsh::to_vec(&payload).unwrap()));
    let pk = format!(
        "ed25519:{}",
        bs58::encode(key.verifying_key().as_bytes()).into_string()
    );
    let signature = base64::engine::general_purpose::STANDARD.encode(sig.to_bytes());
    assert!(crate::auth::nep413::verify_nep413_signature(
        &pk,
        &signature,
        "Login",
        &nonce,
        "example.org"
    )
    .unwrap());
    assert!(!crate::auth::nep413::verify_nep413_signature(
        &pk, &signature, "Login", &nonce, "evil.org"
    )
    .unwrap());
    let changed = Payload {
        callback: Some("dachafm://auth/callback".into()),
        ..payload
    };
    let sig = key.sign(&Sha256::digest(borsh::to_vec(&changed).unwrap()));
    assert!(!crate::auth::nep413::verify_nep413_signature(
        &pk,
        &base64::engine::general_purpose::STANDARD.encode(sig.to_bytes()),
        "Login",
        &nonce,
        "example.org"
    )
    .unwrap());
}
/// Run against a migrated disposable database. Never a production database.
#[tokio::test]
async fn database_session_revocation_and_library_conflicts() {
    let Ok(url) = std::env::var("TEST_DATABASE_URL") else {
        eprintln!("SKIP database test: TEST_DATABASE_URL absent");
        return;
    };
    let pool = sqlx::PgPool::connect(&url).await.unwrap();
    let mut tx = pool.begin().await.unwrap();
    let subject = format!("test-{}", Uuid::new_v4());
    let id = identity(&mut tx, "meteor", &subject, None).await.unwrap();
    let again = identity(&mut tx, "meteor", &subject, None).await.unwrap();
    assert_eq!(id, again);
    let session = session(&mut tx, id).await.unwrap();
    let token = session["access_token"].as_str().unwrap();
    let stored: String =
        sqlx::query_scalar("SELECT token_hash FROM mobile_sessions WHERE account_id=$1")
            .bind(id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    assert_ne!(stored, token);
    assert_eq!(stored, hash(token));
    for expected in [1, 0] {
        let changed = sqlx::query(
            "UPDATE mobile_libraries SET version=version+1 WHERE account_id=$1 AND version=0",
        )
        .bind(id)
        .execute(&mut *tx)
        .await
        .unwrap();
        assert_eq!(changed.rows_affected(), expected);
    }
    let other = Uuid::new_v4();
    assert_eq!(
        sqlx::query("UPDATE mobile_libraries SET version=version+1 WHERE account_id=$1")
            .bind(other)
            .execute(&mut *tx)
            .await
            .unwrap()
            .rows_affected(),
        0
    );
    sqlx::query("DELETE FROM mobile_accounts WHERE id=$1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM mobile_sessions WHERE account_id=$1")
        .bind(id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    assert_eq!(count, 0);
    tx.rollback().await.unwrap();
}
#[tokio::test]
async fn database_challenge_and_code_consume_once() {
    let Ok(url) = std::env::var("TEST_DATABASE_URL") else {
        return;
    };
    let pool = sqlx::PgPool::connect(&url).await.unwrap();
    let mut tx = pool.begin().await.unwrap();
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO mobile_challenges VALUES($1,$2,'message','recipient','challenge',now()+interval '60 seconds')").bind(id).bind(vec![0u8;32]).execute(&mut *tx).await.unwrap();
    for expected in [1, 0] {
        assert_eq!(
            sqlx::query("DELETE FROM mobile_challenges WHERE id=$1 AND expires_at>now()")
                .bind(id)
                .execute(&mut *tx)
                .await
                .unwrap()
                .rows_affected(),
            expected
        )
    }
    let user = identity(&mut tx, "meteor", &format!("test-{}", Uuid::new_v4()), None)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO mobile_codes VALUES('test-code',$1,'challenge',now()+interval '60 seconds')",
    )
    .bind(user)
    .execute(&mut *tx)
    .await
    .unwrap();
    for expected in [1, 0] {
        assert_eq!(
            sqlx::query(
                "DELETE FROM mobile_codes WHERE code_hash='test-code' AND expires_at>now()"
            )
            .execute(&mut *tx)
            .await
            .unwrap()
            .rows_affected(),
            expected
        )
    }
    tx.rollback().await.unwrap();
}
#[tokio::test]
async fn database_catalog_requires_independent_approval_and_visibility() {
    let Ok(url) = std::env::var("TEST_DATABASE_URL") else {
        return;
    };
    let pool = sqlx::PgPool::connect(&url).await.unwrap();
    let mut tx = pool.begin().await.unwrap();
    let slug = Uuid::new_v4().to_string();
    let artist: i32 =
        sqlx::query_scalar("INSERT INTO users(account_id,slug) VALUES($1,$1) RETURNING id")
            .bind(format!("test-{slug}"))
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    let song:i32=sqlx::query_scalar("INSERT INTO songs(uuid,uploader_id,title,audio_url,audio_hash,is_validated) VALUES($1,$2,'Test','https://example.org/audio.mp3',$1,true) RETURNING id").bind(&slug).bind(artist).fetch_one(&mut *tx).await.unwrap();
    let query = format!("{CATALOG} AND s.id=$1");
    assert!(sqlx::query_as::<_, Track>(&query)
        .bind(song)
        .fetch_all(&mut *tx)
        .await
        .unwrap()
        .is_empty());
    sqlx::query(
        "INSERT INTO mobile_catalog_approvals(song_id,approved_by) VALUES($1,'test operator')",
    )
    .bind(song)
    .execute(&mut *tx)
    .await
    .unwrap();
    assert_eq!(
        sqlx::query_as::<_, Track>(&query)
            .bind(song)
            .fetch_all(&mut *tx)
            .await
            .unwrap()
            .len(),
        1
    );
    sqlx::query("UPDATE songs SET is_hidden=true WHERE id=$1")
        .bind(song)
        .execute(&mut *tx)
        .await
        .unwrap();
    assert!(sqlx::query_as::<_, Track>(&query)
        .bind(song)
        .fetch_all(&mut *tx)
        .await
        .unwrap()
        .is_empty());
    sqlx::query("UPDATE songs SET is_hidden=false WHERE id=$1")
        .bind(song)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("UPDATE users SET is_banned=true WHERE id=$1")
        .bind(artist)
        .execute(&mut *tx)
        .await
        .unwrap();
    assert!(sqlx::query_as::<_, Track>(&query)
        .bind(song)
        .fetch_all(&mut *tx)
        .await
        .unwrap()
        .is_empty());
    tx.rollback().await.unwrap();
}
#[test]
fn malformed_and_oversized_inputs_are_rejected() {
    assert!(!valid_challenge(&"!".repeat(43)));
    assert!(!verify_pkce(&"a".repeat(129), "unused"));
    let mut library = Library::default();
    library.blocked_artist_ids.push("alice.near".into());
    assert!(validate_library(&library).is_err());
    library.blocked_artist_ids.clear();
    library.playlists.push(Playlist {
        id: "id".into(),
        name: "line\nbreak".into(),
        tracks: vec![],
    });
    assert!(validate_library(&library).is_err());
    library.playlists[0].name = "n".repeat(101);
    assert!(validate_library(&library).is_err());
    assert!(!https("http://example.org"));
    assert!(!https("https://user:pass@example.org"));
    assert!(https("https://example.org"));
}

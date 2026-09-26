-- Dacha FM private cloud library. Only the Edge API's service_role can call
-- these invoker RPCs. Wallet proof/PKCE and deep content bounds are verified
-- by that API before finish_auth/library_put; no wallet secret enters SQL.

create schema dacha_cloud;
revoke all on schema dacha_cloud from public, anon, authenticated;
grant usage on schema dacha_cloud to service_role;
alter default privileges in schema dacha_cloud revoke all on tables from public, anon, authenticated;
alter default privileges in schema dacha_cloud revoke execute on functions from public, anon, authenticated;

create table dacha_cloud.accounts (
    account_id text primary key check (
        char_length(account_id) between 2 and 64
        and account_id ~ '^([a-z0-9]+[-_])*[a-z0-9]+(\.([a-z0-9]+[-_])*[a-z0-9]+)*$'
    ),
    created_at timestamptz not null default clock_timestamp()
);

create table dacha_cloud.libraries (
    account_id text primary key references dacha_cloud.accounts(account_id) on delete cascade,
    version integer not null default 0 check (version >= 0),
    snapshot jsonb not null default '{"version":0,"favorites":[],"playlists":[],"blocked_artist_ids":[]}'::jsonb,
    updated_at timestamptz not null default clock_timestamp(),
    constraint library_basic_shape check (
        jsonb_typeof(snapshot) = 'object'
        and snapshot ?& array['version', 'favorites', 'playlists', 'blocked_artist_ids']
        and (snapshot - array['version', 'favorites', 'playlists', 'blocked_artist_ids']) = '{}'::jsonb
        and snapshot->'version' = to_jsonb(version)
        and jsonb_typeof(snapshot->'favorites') = 'array'
        and jsonb_typeof(snapshot->'playlists') = 'array'
        and jsonb_typeof(snapshot->'blocked_artist_ids') = 'array'
        and octet_length(snapshot::text) <= 1048576
    )
);

create table dacha_cloud.sessions (
    token_hash text primary key check (token_hash ~ '^[0-9a-f]{64}$'),
    account_id text not null references dacha_cloud.accounts(account_id) on delete cascade,
    expires_at timestamptz not null
);
create index dacha_sessions_account_idx on dacha_cloud.sessions(account_id);
create index dacha_sessions_expiry_idx on dacha_cloud.sessions(expires_at);

create table dacha_cloud.challenges (
    id uuid primary key,
    nonce text not null check (nonce ~ '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$'),
    code_challenge text not null check (code_challenge ~ '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$'),
    expires_at timestamptz not null
);
create index dacha_challenges_expiry_idx on dacha_cloud.challenges(expires_at);

-- Exactly one bounded global rate window; denied requests cannot grow a table.
create table dacha_cloud.auth_rate (
    singleton boolean primary key default true check (singleton),
    started_at timestamptz not null,
    attempts integer not null check (attempts between 0 and 120)
);
insert into dacha_cloud.auth_rate(singleton, started_at, attempts)
values (true, clock_timestamp(), 0);

alter table dacha_cloud.accounts enable row level security;
alter table dacha_cloud.accounts force row level security;
alter table dacha_cloud.libraries enable row level security;
alter table dacha_cloud.libraries force row level security;
alter table dacha_cloud.sessions enable row level security;
alter table dacha_cloud.sessions force row level security;
alter table dacha_cloud.challenges enable row level security;
alter table dacha_cloud.challenges force row level security;
alter table dacha_cloud.auth_rate enable row level security;
alter table dacha_cloud.auth_rate force row level security;
create policy service_access on dacha_cloud.accounts to service_role using (true) with check (true);
create policy service_access on dacha_cloud.libraries to service_role using (true) with check (true);
create policy service_access on dacha_cloud.sessions to service_role using (true) with check (true);
create policy service_access on dacha_cloud.challenges to service_role using (true) with check (true);
create policy service_access on dacha_cloud.auth_rate to service_role using (true) with check (true);
revoke all on all tables in schema dacha_cloud from public, anon, authenticated;
grant select, insert, update, delete on all tables in schema dacha_cloud to service_role;

-- Every session operation uses the same account lock order. Rechecking the
-- session after obtaining the lock prevents a pending write surviving logout
-- or deletion. This helper never creates an account or a library.
create function dacha_cloud.lock_session_account(p_token_hash text)
returns text language plpgsql security invoker set search_path = '' as $$
declare
    v_account_id text;
begin
    if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
        raise sqlstate 'PT401' using message = 'Unauthorized';
    end if;
    select s.account_id into v_account_id from dacha_cloud.sessions s
      where s.token_hash = p_token_hash and s.expires_at > clock_timestamp();
    if v_account_id is null then
        raise sqlstate 'PT401' using message = 'Unauthorized';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('dacha_cloud:' || v_account_id, 0));
    perform 1 from dacha_cloud.accounts a where a.account_id = v_account_id for update;
    if not found then
        raise sqlstate 'PT401' using message = 'Unauthorized';
    end if;
    perform 1 from dacha_cloud.sessions s where s.token_hash = p_token_hash
      and s.account_id = v_account_id and s.expires_at > clock_timestamp();
    if not found then
        raise sqlstate 'PT401' using message = 'Unauthorized';
    end if;
    return v_account_id;
end;
$$;
revoke all on function dacha_cloud.lock_session_account(text) from public, anon, authenticated;
grant execute on function dacha_cloud.lock_session_account(text) to service_role;

create function public.dacha_cloud_auth_rate()
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_now timestamptz := clock_timestamp();
    v_started timestamptz;
    v_attempts integer;
begin
    -- Indexed, bounded cleanup. SKIP LOCKED avoids blocking a live auth/delete.
    delete from dacha_cloud.challenges where id in (
        select id from dacha_cloud.challenges where expires_at <= v_now
        order by expires_at limit 500 for update skip locked
    );
    delete from dacha_cloud.sessions where token_hash in (
        select token_hash from dacha_cloud.sessions where expires_at <= v_now
        order by expires_at limit 500 for update skip locked
    );
    select started_at, attempts into v_started, v_attempts
      from dacha_cloud.auth_rate where singleton for update;
    if v_started + interval '1 minute' <= v_now then
        update dacha_cloud.auth_rate set started_at = v_now, attempts = 1 where singleton;
        return jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
    elsif v_attempts < 120 then
        update dacha_cloud.auth_rate set attempts = attempts + 1 where singleton;
        return jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
    end if;
    return jsonb_build_object('allowed', false, 'retry_after_seconds',
        greatest(1, ceil(extract(epoch from v_started + interval '1 minute' - v_now))::integer));
end;
$$;

create function public.dacha_cloud_create_challenge(p_id uuid, p_nonce text, p_code_challenge text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_row dacha_cloud.challenges;
begin
    if p_id is null or p_nonce is null or p_code_challenge is null
       or p_nonce !~ '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$'
       or p_code_challenge !~ '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' then
        raise sqlstate 'PT400' using message = 'Invalid challenge';
    end if;
    insert into dacha_cloud.challenges(id, nonce, code_challenge, expires_at)
      values (p_id, p_nonce, p_code_challenge, clock_timestamp() + interval '5 minutes')
      returning * into v_row;
    return to_jsonb(v_row);
exception when unique_violation then
    raise sqlstate 'PT409' using message = 'Challenge already exists';
end;
$$;

create function public.dacha_cloud_get_challenge(p_id uuid)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_row dacha_cloud.challenges;
begin
    select * into v_row from dacha_cloud.challenges
      where id = p_id and expires_at > clock_timestamp();
    if not found then
        raise sqlstate 'PT401' using message = 'Challenge is missing or expired';
    end if;
    return to_jsonb(v_row);
end;
$$;

create function public.dacha_cloud_finish_auth(p_id uuid, p_account_id text, p_token_hash text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_expires timestamptz;
begin
    if p_id is null or p_account_id is null or p_token_hash is null
       or char_length(p_account_id) not between 2 and 64
       or p_account_id !~ '^([a-z0-9]+[-_])*[a-z0-9]+(\.([a-z0-9]+[-_])*[a-z0-9]+)*$'
       or p_token_hash !~ '^[0-9a-f]{64}$' then
        raise sqlstate 'PT400' using message = 'Invalid verified identity';
    end if;
    delete from dacha_cloud.challenges where id = p_id and expires_at > clock_timestamp();
    if not found then
        raise sqlstate 'PT401' using message = 'Challenge is missing, expired, or already used';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('dacha_cloud:' || p_account_id, 0));
    insert into dacha_cloud.accounts(account_id) values (p_account_id) on conflict do nothing;
    perform 1 from dacha_cloud.accounts a where a.account_id = p_account_id for update;
    insert into dacha_cloud.libraries(account_id) values (p_account_id) on conflict do nothing;
    v_expires := clock_timestamp() + interval '30 days';
    insert into dacha_cloud.sessions(token_hash, account_id, expires_at)
      values (p_token_hash, p_account_id, v_expires);
    return jsonb_build_object('account_id', p_account_id, 'expires_at', v_expires);
exception when unique_violation then
    raise sqlstate 'PT409' using message = 'Session already exists';
end;
$$;

create function public.dacha_cloud_library_get(p_token_hash text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_account text;
    v_snapshot jsonb;
begin
    v_account := dacha_cloud.lock_session_account(p_token_hash);
    select snapshot into v_snapshot from dacha_cloud.libraries where account_id = v_account;
    if not found then
        raise sqlstate 'PT401' using message = 'Library no longer exists';
    end if;
    return v_snapshot;
end;
$$;

create function public.dacha_cloud_library_put(p_token_hash text, p_snapshot jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_account text;
    v_version integer;
    v_expected integer;
    v_snapshot jsonb;
begin
    v_account := dacha_cloud.lock_session_account(p_token_hash);
    if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object'
       or not (p_snapshot ?& array['version', 'favorites', 'playlists', 'blocked_artist_ids'])
       or (p_snapshot - array['version', 'favorites', 'playlists', 'blocked_artist_ids']) <> '{}'::jsonb
       or jsonb_typeof(p_snapshot->'version') <> 'number'
       or (p_snapshot->>'version') !~ '^(0|[1-9][0-9]{0,9})$'
       or jsonb_typeof(p_snapshot->'favorites') <> 'array'
       or jsonb_typeof(p_snapshot->'playlists') <> 'array'
       or jsonb_typeof(p_snapshot->'blocked_artist_ids') <> 'array'
       or octet_length(p_snapshot::text) > 1048576 then
        raise sqlstate 'PT400' using message = 'Invalid library snapshot';
    end if;
    if (p_snapshot->>'version')::bigint >= 2147483647 then
        raise sqlstate 'PT400' using message = 'Invalid library version';
    end if;
    v_expected := (p_snapshot->>'version')::integer;
    select version into v_version from dacha_cloud.libraries where account_id = v_account for update;
    if not found then
        raise sqlstate 'PT401' using message = 'Library no longer exists';
    end if;
    if v_expected <> v_version then
        raise sqlstate 'PT409' using message = 'Library changed on another device';
    end if;
    v_snapshot := jsonb_set(p_snapshot, '{version}', to_jsonb(v_version + 1), false);
    update dacha_cloud.libraries set version = v_version + 1, snapshot = v_snapshot,
      updated_at = clock_timestamp() where account_id = v_account;
    return v_snapshot;
end;
$$;

create function public.dacha_cloud_logout(p_token_hash text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
    perform dacha_cloud.lock_session_account(p_token_hash);
    delete from dacha_cloud.sessions where token_hash = p_token_hash;
    return jsonb_build_object('ok', true);
end;
$$;

create function public.dacha_cloud_delete_account(p_token_hash text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_account text;
begin
    v_account := dacha_cloud.lock_session_account(p_token_hash);
    delete from dacha_cloud.accounts where account_id = v_account;
    return jsonb_build_object('ok', true);
end;
$$;

-- Explicitly restrict just our functions; leave unrelated project APIs alone.
revoke all on function public.dacha_cloud_auth_rate() from public, anon, authenticated;
revoke all on function public.dacha_cloud_create_challenge(uuid, text, text) from public, anon, authenticated;
revoke all on function public.dacha_cloud_get_challenge(uuid) from public, anon, authenticated;
revoke all on function public.dacha_cloud_finish_auth(uuid, text, text) from public, anon, authenticated;
revoke all on function public.dacha_cloud_library_get(text) from public, anon, authenticated;
revoke all on function public.dacha_cloud_library_put(text, jsonb) from public, anon, authenticated;
revoke all on function public.dacha_cloud_logout(text) from public, anon, authenticated;
revoke all on function public.dacha_cloud_delete_account(text) from public, anon, authenticated;
grant execute on function public.dacha_cloud_auth_rate() to service_role;
grant execute on function public.dacha_cloud_create_challenge(uuid, text, text) to service_role;
grant execute on function public.dacha_cloud_get_challenge(uuid) to service_role;
grant execute on function public.dacha_cloud_finish_auth(uuid, text, text) to service_role;
grant execute on function public.dacha_cloud_library_get(text) to service_role;
grant execute on function public.dacha_cloud_library_put(text, jsonb) to service_role;
grant execute on function public.dacha_cloud_logout(text) to service_role;
grant execute on function public.dacha_cloud_delete_account(text) to service_role;

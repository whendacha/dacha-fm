-- Add reversible hidden songs without letting build 4 erase a newer preference.
-- Keep legacy stored snapshots valid; GET supplies an empty field, and the next
-- PUT writes the complete shape. No account/session/auth/RLS changes are needed.

alter table dacha_cloud.libraries
    alter column snapshot set default '{"version":0,"favorites":[],"playlists":[],"blocked_artist_ids":[],"hidden_tracks":[]}'::jsonb,
    drop constraint library_basic_shape,
    add constraint library_basic_shape check (
        jsonb_typeof(snapshot) = 'object'
        and snapshot ?& array['version', 'favorites', 'playlists', 'blocked_artist_ids']
        and (snapshot - array['version', 'favorites', 'playlists', 'blocked_artist_ids', 'hidden_tracks']) = '{}'::jsonb
        and snapshot->'version' = to_jsonb(version)
        and jsonb_typeof(snapshot->'favorites') = 'array'
        and jsonb_typeof(snapshot->'playlists') = 'array'
        and jsonb_typeof(snapshot->'blocked_artist_ids') = 'array'
        and case when snapshot ? 'hidden_tracks' then
            case when jsonb_typeof(snapshot->'hidden_tracks') = 'array'
                 then jsonb_array_length(snapshot->'hidden_tracks') <= 2000
                 else false end
            else true end
        and octet_length(snapshot::text) <= 1048576
    );

create or replace function public.dacha_cloud_library_get(p_token_hash text)
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
    return v_snapshot || jsonb_build_object('hidden_tracks', coalesce(v_snapshot->'hidden_tracks', '[]'::jsonb));
end;
$$;

create or replace function public.dacha_cloud_library_put(p_token_hash text, p_snapshot jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_account text;
    v_version integer;
    v_expected integer;
    v_stored jsonb;
    v_snapshot jsonb;
begin
    v_account := dacha_cloud.lock_session_account(p_token_hash);
    if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object'
       or not (p_snapshot ?& array['version', 'favorites', 'playlists', 'blocked_artist_ids'])
       or (p_snapshot - array['version', 'favorites', 'playlists', 'blocked_artist_ids', 'hidden_tracks']) <> '{}'::jsonb
       or jsonb_typeof(p_snapshot->'version') <> 'number'
       or (p_snapshot->>'version') !~ '^(0|[1-9][0-9]{0,9})$'
       or jsonb_typeof(p_snapshot->'favorites') <> 'array'
       or jsonb_typeof(p_snapshot->'playlists') <> 'array'
       or jsonb_typeof(p_snapshot->'blocked_artist_ids') <> 'array'
       or octet_length(p_snapshot::text) > 1048576 then
        raise sqlstate 'PT400' using message = 'Invalid library snapshot';
    end if;
    if p_snapshot ? 'hidden_tracks' then
        if jsonb_typeof(p_snapshot->'hidden_tracks') <> 'array' then
            raise sqlstate 'PT400' using message = 'Invalid hidden tracks';
        end if;
        if jsonb_array_length(p_snapshot->'hidden_tracks') > 2000 then
            raise sqlstate 'PT400' using message = 'Too many hidden tracks';
        end if;
    end if;
    if (p_snapshot->>'version')::bigint >= 2147483647 then
        raise sqlstate 'PT400' using message = 'Invalid library version';
    end if;
    v_expected := (p_snapshot->>'version')::integer;
    select version, snapshot into v_version, v_stored from dacha_cloud.libraries
      where account_id = v_account for update;
    if not found then
        raise sqlstate 'PT401' using message = 'Library no longer exists';
    end if;
    if v_expected <> v_version then
        raise sqlstate 'PT409' using message = 'Library changed on another device';
    end if;
    -- A legacy client's omission is not an explicit clear. Read the current
    -- value only after obtaining the shared account lock and checking version.
    v_snapshot := p_snapshot || jsonb_build_object(
        'version', v_version + 1,
        'hidden_tracks', coalesce(p_snapshot->'hidden_tracks', v_stored->'hidden_tracks', '[]'::jsonb)
    );
    if octet_length(v_snapshot::text) > 1048576 then
        raise sqlstate 'PT400' using message = 'Library snapshot is too large';
    end if;
    update dacha_cloud.libraries set version = v_version + 1, snapshot = v_snapshot,
      updated_at = clock_timestamp() where account_id = v_account;
    return v_snapshot;
end;
$$;

-- CREATE OR REPLACE preserves the existing owner and service-only EXECUTE ACLs.

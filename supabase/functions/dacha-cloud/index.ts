import { createHandler, createPostgrestRPC } from './handler.mjs';

const url = Deno.env.get('SUPABASE_URL');
const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}');
const secret = keys.default ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
Deno.serve(createHandler({ db: createPostgrestRPC(url, secret) }));

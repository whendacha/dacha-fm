import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, sign } from 'node:crypto';
import { createHandler } from './handler.mjs';
import { CLOUD_MESSAGE, RECIPIENT, b64url, HTTPError } from './protocol.mjs';
const base = 'https://test.supabase.co/functions/v1/dacha-cloud/api/mobile/v1/';
const empty = {version:0,favorites:[],playlists:[],blocked_artist_ids:[]};
function setup(permission = 'FullAccess') {
  const challenges = new Map(), sessions = new Map(), libraries = new Map(); let rpcCalls=0;
  const db = async (name,p={}) => {
    if(name==='dacha_cloud_auth_rate') return {allowed:true,retry_after_seconds:0};
    if(name==='dacha_cloud_create_challenge') { const v={id:p.p_id,nonce:p.p_nonce,code_challenge:p.p_code_challenge,expires_at:new Date(Date.now()+300000).toISOString()}; challenges.set(v.id,v);return v; }
    if(name==='dacha_cloud_get_challenge') { const v=challenges.get(p.p_id); if(!v)throw new HTTPError(401,'invalid_challenge');return v; }
    if(name==='dacha_cloud_finish_auth') { if(!challenges.delete(p.p_id))throw new HTTPError(401,'invalid_challenge');sessions.set(p.p_token_hash,p.p_account_id);if(!libraries.has(p.p_account_id))libraries.set(p.p_account_id,structuredClone(empty));return{account_id:p.p_account_id}; }
    const account=sessions.get(p.p_token_hash); if(!account) throw new HTTPError(401,'unauthorized');
    if(name==='dacha_cloud_library_get')return libraries.get(account);
    if(name==='dacha_cloud_library_put') {const current=libraries.get(account);if(current.version!==p.p_snapshot.version)throw new HTTPError(409,'conflict');const next={...p.p_snapshot,version:current.version+1};libraries.set(account,next);return next;}
    if(name==='dacha_cloud_logout'){sessions.delete(p.p_token_hash);return null;}
    if(name==='dacha_cloud_delete_account'){libraries.delete(account);for(const [k,v]of sessions)if(v===account)sessions.delete(k);return null;}
    throw new Error('unexpected RPC '+name);
  };
  const handler=createHandler({db,fetcher:async(url,options)=>{
    rpcCalls++;assert.equal(url,'https://rpc.mainnet.fastnear.com');const body=JSON.parse(options.body);assert.equal(body.params.request_type,'view_access_key');assert.equal(options.redirect,'error');
    return Response.json({jsonrpc:'2.0',id:'dacha-cloud-key',result:{permission}});
  }});
  const request=async(path,body,token,method=body===undefined?'GET':'POST')=>handler(new Request(base+path,{method,headers:{...(body===undefined?{}:{'Content-Type':'application/json'}),...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)}));
  return {request,handler,challenges,sessions,libraries,rpcCalls:()=>rpcCalls};
}
function proof(challenge,message=CLOUD_MESSAGE) {
  const {publicKey,privateKey}=generateKeyPairSync('ed25519');const raw=publicKey.export({format:'der',type:'spki'}).subarray(-32);
  let n=BigInt('0x'+raw.toString('hex')),key='';const alphabet='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';while(n){key=alphabet[Number(n%58n)]+key;n/=58n;}for(const b of raw){if(b)break;key='1'+key;}
  const str=x=>{const b=Buffer.from(x),l=Buffer.alloc(4);l.writeUInt32LE(b.length);return Buffer.concat([l,b]);};const tag=Buffer.alloc(4);tag.writeUInt32LE(2147484061);
  const bytes=Buffer.concat([tag,str(message),Buffer.from(challenge.nonce),str(RECIPIENT),Buffer.from([0])]);
  return {challenge_id:challenge.id,account_id:'dacha-test.near',public_key:'ed25519:'+key,signature:sign(null,createHash('sha256').update(bytes).digest(),privateKey).toString('base64')};
}
async function challenge(s) {
  const verifier=b64url(Buffer.alloc(32,6));const r=await s.request('auth/meteor/challenge',{code_challenge:createHash('sha256').update(verifier).digest('base64url')});assert.equal(r.status,200);return{verifier,value:await r.json()};
}
test('public config is available but library always requires opaque authentication',async()=> {
  const s=setup(); assert.equal((await s.request('config')).status,200);
  assert.equal((await s.request('library')).status,401);
  assert.equal((await s.request('library',undefined,b64url(Buffer.alloc(32,8)))).status,401);
  assert.equal((await s.request('tracks')).status,404);
});
test('server challenge, PKCE, proof, single-use session and revocation work together',async()=> {
  const s=setup();const c=await challenge(s);assert.equal(c.value.message,CLOUD_MESSAGE);assert.equal(c.value.nonce.length,32);
  const signed=proof(c.value);
  assert.equal((await s.request('auth/meteor/verify',{...signed,code_verifier:b64url(Buffer.alloc(32,5))})).status,401);
  assert.equal(s.rpcCalls(),0);assert.equal(s.challenges.size,1);
  const r=await s.request('auth/meteor/verify',{...signed,code_verifier:c.verifier});assert.equal(r.status,200);
  const session=await r.json();assert.equal(session.user_id,'dacha-test.near');assert.equal(session.kind,'verified-cloud-wallet');assert.equal(session.access_token.length,43);
  assert.equal(s.sessions.has(session.access_token),false);assert.equal(s.sessions.size,1);
  assert.equal((await s.request('auth/meteor/verify',{...signed,code_verifier:c.verifier})).status,401);
  assert.equal((await s.request('library',undefined,session.access_token)).status,200);
  assert.equal((await s.request('library',empty,session.access_token,'PUT')).status,200);
  assert.equal((await s.request('library',empty,session.access_token,'PUT')).status,409);
  assert.equal((await s.request('auth/logout',{},session.access_token)).status,204);
  assert.equal((await s.request('library',undefined,session.access_token)).status,401);
});
test('local-scope proof and function-call keys cannot open cloud sessions',async()=> {
  const s=setup();const c=await challenge(s);
  const signed=proof(c.value,'Dacha FM sign-in\nVerify your Meteor account for the library on this device. No transaction or wallet permission is requested.');
  assert.equal((await s.request('auth/meteor/verify',{...signed,code_verifier:c.verifier})).status,401);assert.equal(s.sessions.size,0);
  const f=setup({FunctionCall:{receiver_id:'example.near'}});const fc=await challenge(f);
  assert.equal((await f.request('auth/meteor/verify',{...proof(fc.value),code_verifier:fc.verifier})).status,401);assert.equal(f.sessions.size,0);
});
test('untrusted origins and oversized bodies are rejected without leaks',async()=> {
  const s=setup();const r=await s.handler(new Request(base+'config',{headers:{Origin:'https://attacker.example'}}));assert.equal(r.status,403);
  const huge=await s.handler(new Request(base+'auth/meteor/challenge',{method:'POST',headers:{'Content-Type':'application/json'},body:'x'.repeat(5000)}));assert.equal(huge.status,413);
  assert.equal(r.headers.get('Cache-Control'),'no-store');
});
test('HTTP library save forwards hidden tracks but preserves absence in legacy requests',async()=> {
  const token=b64url(Buffer.alloc(32,9)), writes=[];
  const handler=createHandler({db:async(name,args)=>{
    assert.equal(name,'dacha_cloud_library_put');writes.push(args.p_snapshot);
    return {...args.p_snapshot,version:args.p_snapshot.version+1,hidden_tracks:args.p_snapshot.hidden_tracks??[]};
  }});
  const track={id:'d1c6f613-3cec-4348-ac6e-05204634ed41',title:'Song',artist_id:'32',artist_name:'Artist',audio_url:'https://main.fastfs.io/song.mp3',artwork_url:null,duration:15};
  const put=body=>handler(new Request(base+'library',{method:'PUT',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify(body)}));
  assert.equal((await put({...empty,hidden_tracks:[track]})).status,200);
  assert.deepEqual(writes[0].hidden_tracks,[track]);
  assert.equal((await put(empty)).status,200);
  assert.equal(Object.hasOwn(writes[1],'hidden_tracks'),false);
  assert.equal((await put({...empty,hidden_tracks:null})).status,400);
  assert.equal(writes.length,2);
});

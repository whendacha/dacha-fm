import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, sign } from 'node:crypto';
import { CLOUD_MESSAGE, RECIPIENT, b64url, digestHex, verifyProof, verifyPKCE, normalizeLibrary, HTTPError } from './protocol.mjs';

const account = 'dacha-test.near';
function base58(bytes) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  let n = BigInt('0x' + Buffer.from(bytes).toString('hex'));
  let out = ''; while (n) { out = alphabet[Number(n % 58n)] + out; n /= 58n; }
  return '1'.repeat([...bytes].findIndex(x => x !== 0)) + out;
}
function fixture(message = CLOUD_MESSAGE) {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const raw = publicKey.export({format:'der',type:'spki'}).subarray(-32);
  const nonce = Buffer.alloc(32, 17);
  const str = x => { const b = Buffer.from(x); const n = Buffer.alloc(4); n.writeUInt32LE(b.length); return Buffer.concat([n,b]); };
  const tag = Buffer.alloc(4); tag.writeUInt32LE(2147484061);
  const payload = Buffer.concat([tag,str(message),nonce,str(RECIPIENT),Buffer.from([0])]);
  return { challenge:{nonce:b64url(nonce)}, proof:{account_id:account,public_key:'ed25519:'+base58(raw),signature:sign(null,createHash('sha256').update(payload).digest(),privateKey).toString('base64')} };
}
test('cloud proof verifies independent NEP-413 payload and returns account',async()=> {
  const f=fixture(); assert.equal(await verifyProof(f.challenge,f.proof),account);
});
test('local-only message cannot authorize cloud sign-in',async()=> {
  const f=fixture('Dacha FM sign-in\nVerify your Meteor account for the library on this device. No transaction or wallet permission is requested.');
  await assert.rejects(verifyProof(f.challenge,f.proof),HTTPError);
});
test('wrong nonce and malformed proof fail closed',async()=> {
  const f=fixture(); await assert.rejects(verifyProof({nonce:b64url(Buffer.alloc(32,18))},f.proof),HTTPError);
  await assert.rejects(verifyProof(f.challenge,{...f.proof,signature:'bad'}),HTTPError);
  await assert.rejects(verifyProof(f.challenge,{...f.proof,account_id:'UPPER.near'}),HTTPError);
});
test('PKCE requires canonical verifier and matching S256',async()=> {
  const verifier=b64url(Buffer.alloc(32,9));
  const challenge=createHash('sha256').update(verifier).digest('base64url');
  assert.equal(await verifyPKCE(challenge,verifier),true);
  assert.equal(await verifyPKCE(challenge,b64url(Buffer.alloc(32,8))),false);
  assert.equal(await verifyPKCE(challenge,'short'),false);
  assert.equal((await digestHex(verifier)).length,64);
});
const track={id:'d1c6f613-3cec-4348-ac6e-05204634ed41',title:'Song',artist_id:'32',artist_name:'Artist',audio_url:'https://main.fastfs.io/song.mp3',artwork_url:null,duration:15};
test('library keeps playlist order and removes blocked/duplicate records',()=> {
  const value=normalizeLibrary({version:3,favorites:[track,track],playlists:[{id:'list-1',name:'Evening',tracks:[track,track]}],blocked_artist_ids:[]});
  assert.equal(value.version,3);assert.equal(value.favorites.length,1);assert.equal(value.playlists[0].tracks.length,1);
  assert.equal(normalizeLibrary({...value,blocked_artist_ids:['32']}).favorites.length,0);
});
test('invalid libraries and unsafe URLs cannot enter cloud storage',()=> {
  for(const audio_url of ['http://main.fastfs.io/a','file:///etc/passwd','https://localhost/a','https://user:password@main.fastfs.io/a']) {
    assert.throws(()=>normalizeLibrary({version:0,favorites:[{...track,audio_url}],playlists:[],blocked_artist_ids:[]}),HTTPError);
  }
  assert.throws(()=>normalizeLibrary({version:-1,favorites:[],playlists:[],blocked_artist_ids:[]}),HTTPError);
  assert.throws(()=>normalizeLibrary({version:0,favorites:[],playlists:[{id:'p',name:'',tracks:[]}],blocked_artist_ids:[]}),HTTPError);
});
test('hidden tracks are validated and deduplicated without removing library memberships',()=> {
  const value=normalizeLibrary({version:3,favorites:[track],playlists:[{id:'list-1',name:'Evening',tracks:[track]}],blocked_artist_ids:[],hidden_tracks:[track,track]});
  assert.deepEqual(value.hidden_tracks,[track]);
  assert.deepEqual(value.favorites,[track]);
  assert.deepEqual(value.playlists[0].tracks,[track]);
  assert.deepEqual(normalizeLibrary({...value,hidden_tracks:[]}).hidden_tracks,[]);
});
test('legacy omission stays omitted for the locked database merge',()=> {
  const value=normalizeLibrary({version:2,favorites:[],playlists:[],blocked_artist_ids:[]});
  assert.equal(Object.hasOwn(value,'hidden_tracks'),false);
});
test('hidden tracks retain full metadata independently of hidden-artist filtering',()=> {
  const value=normalizeLibrary({version:0,favorites:[track],playlists:[{id:'list-1',name:'Evening',tracks:[track]}],blocked_artist_ids:['32'],hidden_tracks:[track]});
  assert.deepEqual(value.hidden_tracks,[track]);
  assert.deepEqual(value.favorites,[]);
  assert.deepEqual(value.playlists[0].tracks,[]);
});
test('malformed or excessive hidden tracks cannot enter storage',()=> {
  const base={version:0,favorites:[],playlists:[],blocked_artist_ids:[]};
  for(const hidden_tracks of [null,{},[null],[{...track,id:'not-a-uuid'}],[{...track,audio_url:'http://main.fastfs.io/song.mp3'}],[{...track,title:''}],Array(2001).fill(track)]) {
    assert.throws(()=>normalizeLibrary({...base,hidden_tracks}),HTTPError);
  }
  assert.deepEqual(normalizeLibrary({...base,hidden_tracks:Array(2000).fill(track)}).hidden_tracks,[track]);
});

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Controller } = require('./controller.cjs');
test('seek-only, unknown, and unchanged updates emit no snapshots', () => {
  const { c, messages } = fixture();
  const before = messages.length;
  c.update('Changed', { zones_seek_changed: [{ zone_id: 'g', seek_position: 10 }] });
  c.update('Changed', { zones_removed: ['missing'] });
  c.update('Changed', { zones_changed: [{ ...c.zones.get('g'), now_playing: { image_key: 'new-art' } }] });
  c.update('Unknown');
  c.update('Subscribed', { zones: [...c.zones.values()] });
  assert.equal(messages.length, before);
  c.update('Changed', { zones_changed: [{ ...c.zones.get('g'), state: 'paused' }] });
  assert.equal(messages.length, before + 1);
  c.update('Changed', { zones_removed: ['g'] });
  assert.equal(messages.length, before + 2);
});
test('snapshots project only the fields consumed by Swift', () => {
  const { c, messages } = fixture();
  c.update('Changed', { zones_added: [{ zone_id: 'new', display_name: 'New', state: 'playing', now_playing: { image_key: 'art' }, outputs: [{ output_id: 'x', display_name: 'X', source_controls: {}, volume: { type: 'db', value: -30, min: -80, max: 0, step: 1, is_muted: false } }] }] });
  assert.deepEqual(messages.at(-1).zones.at(-1), { zone_id: 'new', display_name: 'New', state: 'playing', outputs: [{ output_id: 'x', display_name: 'X', volume: { type: 'db', value: -30, is_muted: false, is_fixed: undefined } }] });
});
function fixture() {
  const messages = [], calls = [];
  const c = new Controller(m => messages.push(m));
  c.connect({ change_volume: (...args) => { calls.push(args.slice(0, 3)); args[3](false); }, mute: (...args) => { calls.push(args.slice(0, 2)); args[2](false); } }, 'Test');
  c.eligible = new Set(['a', 'b']);
  c.update('Subscribed', { zones: [{ zone_id: 'g', state: 'playing', outputs: [
    { output_id: 'a', display_name: '8C', volume: { type: 'db', is_muted: true } },
    { output_id: 'b', display_name: 'WiiM', volume: { type: 'number', is_muted: false } },
    { output_id: 'c', volume: { type: 'number' } }
  ] }] });
  const cmd = (action, output_ids = ['a', 'b']) => ({ type: 'command', id: '1', action, generation: c.generation, output_ids });
  return { c, messages, calls, cmd };
}
test('group volume uses native steps and excludes unconfigured outputs', async () => {
  const { c, calls, cmd, messages } = fixture();
  await c.command(cmd('up'));
  assert.deepEqual(calls, [['a', 'relative_step', 1], ['b', 'relative_step', 1]]);
  await c.command(cmd('down', ['c']));
  assert.match(messages.at(-1).error, /no volume/);
  assert.equal(calls.length, 2);
});
test('mute mixed group then unmute fully muted group', async () => {
  const { c, calls, cmd } = fixture();
  await c.command(cmd('mute'));
  assert.deepEqual(calls, [['a', 'mute'], ['b', 'mute']]);
  c.zones.get('g').outputs[1].volume.is_muted = true;
  await c.command(cmd('mute'));
  assert.deepEqual(calls.slice(2), [['a', 'unmute'], ['b', 'unmute']]);
});
test('stale connection and stopped targets are rejected', async () => {
  const { c, calls, cmd, messages } = fixture();
  const old = cmd('up'); c.disconnect();
  await c.command(old); assert.match(messages.at(-1).error, /disconnected/);
  assert.equal(calls.length, 0);
  const f = fixture(); f.c.zones.get('g').state = 'paused';
  await f.c.command(f.cmd('up')); assert.equal(f.calls.length, 0);
});
test('incremental volume uses relative and unsupported mute fails', async () => {
  const { c, calls, cmd, messages } = fixture();
  c.zones.get('g').outputs[0].volume = { type: 'incremental' };
  await c.command(cmd('down', ['a'])); assert.deepEqual(calls, [['a', 'relative', -1]]);
  await c.command(cmd('mute', ['a'])); assert.match(messages.at(-1).error, /support mute/);
});
test('repeats are dropped while busy and partial group errors reported', async () => {
  const { c, calls, cmd, messages } = fixture(); let finish;
  c.transport.change_volume = (id, how, value, cb) => { calls.push(id); if (id === 'a') finish = cb; else cb('Failed'); };
  const pending = c.command(cmd('up'));
  await c.command(cmd('up')); assert.equal(messages.at(-1).error, 'busy');
  finish(false); await pending;
  assert.match(messages.at(-1).error, /WiiM: Failed/); assert.equal(calls.length, 2);
});

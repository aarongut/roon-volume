const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Tide16 } = require('./tide16.cjs');
const { Controller } = require('./controller.cjs');

class Socket extends EventTarget {
  constructor() { super(); this.readyState = 0; this.calls = []; this.level = -30; this.muted = false; this.measuring = false; }
  open() { this.readyState = 1; this.dispatchEvent(new Event('open')); }
  message(message) { this.dispatchEvent(new MessageEvent('message', { data: JSON.stringify(message) })); }
  send(data) {
    const m = JSON.parse(data); this.calls.push(m);
    if (this.silent) return;
    if (m.endpoint === 'set_volume_db') this.level = m.value;
    if (m.endpoint === 'set_mute') this.muted = m.value;
    const dataValue = { get_volume_db: this.level, get_mute: this.muted, get_dirac_measuring_mode: this.measuring }[m.endpoint];
    queueMicrotask(() => this.message({ req: m.endpoint, status: 'OK', data: dataValue }));
  }
  close() { this.readyState = 3; this.dispatchEvent(new Event('close')); }
}
async function fixture(t) {
  const socket = new Socket();
  const tide = new Tide16(() => {}, { socketFactory: () => socket, timeout: 30, retry: 1000 });
  t.after(() => tide.stop());
  tide.configure('10.0.0.130'); socket.open();
  await new Promise(resolve => setImmediate(resolve));
  return { tide, socket };
}
test('Tide16 uses current device feedback, half-dB steps, bounds, and mute', async t => {
  const { tide, socket } = await fixture(t);
  assert.equal(tide.volume.is_fixed, false);
  socket.level = -18;
  await tide.control('up', 'mute', () => true);
  assert.equal(socket.level, -17.5); assert.equal(tide.volume.value, -17.5);
  await tide.control('down', 'mute', () => true); assert.equal(socket.level, -18);
  socket.level = 0;
  await tide.control('up', 'mute', () => true); assert.equal(socket.level, 0);
  socket.level = -127.5;
  await tide.control('down', 'mute', () => true); assert.equal(socket.level, -127.5);
  await tide.control('mute', 'mute', () => true); assert.equal(tide.volume.is_muted, true);
  await tide.control('mute', 'unmute', () => true); assert.equal(tide.volume.is_muted, false);
});
test('remote notifications update feedback; calibration and stale targets prevent writes', async t => {
  const { tide, socket } = await fixture(t);
  socket.message({ notification: 'volume_change_db', value: -45 });
  assert.equal(tide.volume.value, -45);
  socket.message({ notification: 'volume_change_db', value: 200 });
  assert.equal(tide.volume.value, -45);
  await assert.rejects(tide.control('up', 'mute', () => false), /target changed/);
  socket.measuring = true;
  await assert.rejects(tide.control('up', 'mute', () => true), /unavailable/);
  assert.equal(tide.volume.is_fixed, true);
  assert.equal(socket.calls.filter(m => m.endpoint.startsWith('set_')).length, 0);
});
test('timeout invalidates state and late replies cannot revive the connection', async t => {
  const { tide, socket } = await fixture(t);
  socket.silent = true;
  await assert.rejects(tide.control('up', 'mute', () => true), /timed out/);
  socket.message({ req: 'get_volume_db', status: 'OK', data: -20 });
  assert.equal(tide.ready, false); assert.equal(tide.volume.is_fixed, true);
  assert.equal(tide.volume.value, null);
  assert.equal(socket.calls.filter(m => m.endpoint.startsWith('set_')).length, 0);
});
test('Chromecast fixed volume is replaced by Tide16; grouped commands use each device', async t => {
  const { tide, socket } = await fixture(t);
  const messages = [], calls = [];
  const c = new Controller(m => messages.push(m), tide);
  c.connect({ change_volume: (...args) => { calls.push(args.slice(0, 3)); args[3](false); } }, 'Test');
  await c.command({ type: 'configure', output_ids: ['theater', '8c'], tide_output_id: 'theater', tide_host: '10.0.0.130' });
  c.update('Subscribed', { zones: [{ zone_id: 'group', state: 'playing', outputs: [
    { output_id: 'theater', display_name: 'Theater Audio', volume: { type: 'number', is_fixed: true, value: 100 } },
    { output_id: '8c', display_name: '8C', volume: { type: 'db', value: -40 } }
  ] }] });
  const cmd = () => ({ type: 'command', generation: c.generation, action: 'up', output_ids: ['theater', '8c'] });
  assert.equal(messages.at(-1).zones[0].outputs[0].volume.value, -30);
  await c.command(cmd());
  assert.equal(socket.level, -29.5); assert.deepEqual(calls, [['8c', 'relative_step', 1]]);
  socket.close();
  await c.command(cmd());
  assert.match(messages.at(-1).error, /no volume control/);
  assert.equal(calls.length, 1);
});
test('configuration changes during a device read cancel the write and release backpressure', async t => {
  const { tide, socket } = await fixture(t);
  const c = new Controller(() => {}, tide);
  c.connect({}, 'Test');
  await c.command({ type: 'configure', output_ids: ['theater'], tide_output_id: 'theater', tide_host: '10.0.0.130' });
  c.update('Subscribed', { zones: [{ zone_id: 'z', state: 'playing', outputs: [{ output_id: 'theater', display_name: 'Theater Audio' }] }] });
  const pending = c.command({ action: 'up', generation: c.generation, output_ids: ['theater'] });
  await c.command({ type: 'configure', output_ids: [], tide_host: null });
  await pending;
  assert.equal(c.busy, false);
  assert.equal(socket.calls.filter(m => m.endpoint.startsWith('set_')).length, 0);
});

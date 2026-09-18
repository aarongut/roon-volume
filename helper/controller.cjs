'use strict';
class Controller {
  constructor(send) { this.send = send; this.generation = 0; this.zones = new Map(); this.transport = null; this.eligible = new Set(); this.busy = false; }
  connect(transport, core) { this.generation++; this.transport = transport; this.core = core; this.zones.clear(); this.busy = false; this.snapshot(); }
  disconnect() { this.generation++; this.transport = null; this.zones.clear(); this.busy = false; this.snapshot(); }
  update(response, body = {}) {
    if (response === 'Subscribed') this.zones = new Map((body.zones || []).map(z => [z.zone_id, z]));
    if (response === 'Changed') {
      for (const id of body.zones_removed || []) this.zones.delete(id);
      for (const z of [...body.zones_added || [], ...body.zones_changed || []]) this.zones.set(z.zone_id, z);
    }
    if (response === 'Unsubscribed') { this.disconnect(); return; }
    this.snapshot();
  }
  snapshot() { this.send({ type: 'snapshot', connected: !!this.transport, core: this.core, generation: this.generation, zones: [...this.zones.values()] }); }
  async command(cmd) {
    const result = (error, outputs = []) => this.send({ type: 'result', id: cmd.id, generation: cmd.generation, error: error || null, outputs });
    if (cmd.type === 'configure') { this.eligible = new Set((cmd.output_ids || []).filter(x => typeof x === 'string')); return; }
    if (!['up', 'down', 'mute'].includes(cmd.action)) return result('Unknown action');
    if (!this.transport || cmd.generation !== this.generation) return result('Roon disconnected');
    if (this.busy) return result('busy'); // Drop repeats rather than building a delayed queue.
    const ids = [...new Set(cmd.output_ids || [])];
    const zone = [...this.zones.values()].find(z => z.state === 'playing' && ids.every(id => z.outputs.some(o => o.output_id === id)));
    const outputs = ids.map(id => zone?.outputs.find(o => o.output_id === id));
    if (!ids.length || outputs.some(o => !o || !this.eligible.has(o.output_id) || !o.volume || o.volume.is_fixed)) return result('Target is no longer playing or has no volume control');
    if (cmd.action === 'mute' && outputs.some(o => typeof o.volume.is_muted !== 'boolean')) return result('This output does not support mute');
    const transport = this.transport, generation = this.generation;
    const mute = outputs.every(o => o.volume.is_muted) ? 'unmute' : 'mute';
    this.busy = true;
    try {
      const errors = await Promise.all(outputs.map(o => new Promise(resolve => {
        let timer = setTimeout(() => resolve(`${o.display_name}: timed out`), 2000);
        const cb = err => { clearTimeout(timer); resolve(err ? `${o.display_name}: ${err}` : null); };
        try {
          if (cmd.action === 'mute') transport.mute(o.output_id, mute, cb);
          else transport.change_volume(o.output_id, o.volume.type === 'incremental' ? 'relative' : 'relative_step', cmd.action === 'up' ? 1 : -1, cb);
        } catch (err) { cb(err.message); }
      })));
      if (generation === this.generation) result(errors.filter(Boolean).join('; '), ids);
    } finally { if (generation === this.generation) this.busy = false; }
  }
}
module.exports = { Controller };

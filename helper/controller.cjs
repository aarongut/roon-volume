'use strict';
const { Tide16 } = require('./tide16.cjs');
class Controller {
  constructor(send, tide) { this.send = send; this.generation = 0; this.zones = new Map(); this.transport = null; this.eligible = new Set(); this.busy = false; this.tide = tide || new Tide16(() => this.tideChanged()); this.tideOutput = null; this.tideAvailable = false; }
  tideChanged() {
    const available = !this.tide.volume.is_fixed;
    if (available !== this.tideAvailable) { this.tideAvailable = available; this.generation++; }
    this.snapshot();
  }
  connect(transport, core) { this.generation++; this.transport = transport; this.core = core; this.zones.clear(); this.busy = false; this.snapshot(); }
  disconnect() { this.generation++; this.transport = null; this.zones.clear(); this.busy = false; this.snapshot(); }
  update(response, body = {}) {
    let changed = false;
    if (response === 'Subscribed') {
      const zones = new Map((body.zones || []).map(z => [z.zone_id, projectZone(z)]));
      changed = JSON.stringify([...zones.values()]) !== JSON.stringify([...this.zones.values()]);
      this.zones = zones;
    }
    if (response === 'Changed') {
      for (const id of body.zones_removed || []) changed = this.zones.delete(id) || changed;
      for (const z of [...body.zones_added || [], ...body.zones_changed || []]) {
        const zone = projectZone(z);
        if (JSON.stringify(zone) !== JSON.stringify(this.zones.get(z.zone_id))) {
          this.zones.set(z.zone_id, zone);
          changed = true;
        }
      }
    }
    if (response === 'Unsubscribed') { this.disconnect(); return; }
    if (changed) this.snapshot();
  }
  projectedZones() {
    return [...this.zones.values()].map(z => ({ ...z, outputs: z.outputs.map(o => o.output_id === this.tideOutput ? { ...o, volume: this.tide.volume } : o) }));
  }
  snapshot() { this.send({ type: 'snapshot', connected: !!this.transport, core: this.core, generation: this.generation, tide_status: this.tideOutput ? this.tide.status : null, zones: this.projectedZones() }); }
  async command(cmd) {
    const result = (error, outputs = []) => this.send({ type: 'result', id: cmd.id, generation: cmd.generation, error: error || null, outputs });
    if (cmd.type === 'configure') {
      this.eligible = new Set((cmd.output_ids || []).filter(x => typeof x === 'string'));
      const output = typeof cmd.tide_output_id === 'string' ? cmd.tide_output_id : null;
      const host = typeof cmd.tide_host === 'string' && /^[a-zA-Z0-9.-]+$/.test(cmd.tide_host) ? cmd.tide_host : null;
      if (output !== this.tideOutput || host !== this.tide.host) {
        this.generation++; this.tideOutput = output; this.tide.configure(host); this.snapshot();
      }
      return;
    }
    if (!['up', 'down', 'mute'].includes(cmd.action)) return result('Unknown action');
    if (!this.transport || cmd.generation !== this.generation) return result('Roon disconnected');
    if (this.busy) return result('busy'); // Drop repeats rather than building a delayed queue.
    const ids = [...new Set(cmd.output_ids || [])];
    const zone = this.projectedZones().find(z => z.state === 'playing' && ids.every(id => z.outputs.some(o => o.output_id === id)));
    const outputs = ids.map(id => zone?.outputs.find(o => o.output_id === id));
    if (!ids.length || outputs.some(o => !o || !this.eligible.has(o.output_id) || !o.volume || o.volume.is_fixed)) return result('Target is no longer playing or has no volume control');
    if (cmd.action === 'mute' && outputs.some(o => typeof o.volume.is_muted !== 'boolean')) return result('This output does not support mute');
    const transport = this.transport, generation = this.generation;
    const mute = outputs.every(o => o.volume.is_muted) ? 'unmute' : 'mute';
    const operation = {}; this.busy = operation;
    try {
      const errors = await Promise.all(outputs.map(o => o.output_id === this.tideOutput
        ? this.tide.control(cmd.action, mute, () => generation === this.generation && this.eligible.has(o.output_id) && [...this.zones.values()].some(z => z.state === 'playing' && z.outputs.some(x => x.output_id === o.output_id))).then(() => null, err => `${o.display_name}: ${err.message}`)
        : new Promise(resolve => {
        let timer = setTimeout(() => resolve(`${o.display_name}: timed out`), 2000);
        const cb = err => { clearTimeout(timer); resolve(err ? `${o.display_name}: ${err}` : null); };
        try {
          if (cmd.action === 'mute') transport.mute(o.output_id, mute, cb);
          else transport.change_volume(o.output_id, o.volume.type === 'incremental' ? 'relative' : 'relative_step', cmd.action === 'up' ? 1 : -1, cb);
        } catch (err) { cb(err.message); }
      })));
      if (generation === this.generation) result(errors.filter(Boolean).join('; '), ids);
    } finally { if (this.busy === operation) this.busy = false; }
  }
}
function projectZone(zone) {
  return {
    zone_id: zone.zone_id, display_name: zone.display_name, state: zone.state,
    outputs: (zone.outputs || []).map(output => ({
      output_id: output.output_id, display_name: output.display_name,
      ...(output.volume ? { volume: {
        type: output.volume.type, value: output.volume.value,
        is_muted: output.volume.is_muted, is_fixed: output.volume.is_fixed
      } } : {})
    }))
  };
}
module.exports = { Controller };

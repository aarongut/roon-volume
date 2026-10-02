'use strict';

// Tide16 uses endpoint names to correlate replies, with no request IDs. Never
// reuse a timed-out connection: a late reply must not complete a newer request.
class Tide16 {
  constructor(onChange, { socketFactory = url => new WebSocket(url), timeout = 2000, retry = 3000 } = {}) {
    this.onChange = onChange; this.socketFactory = socketFactory;
    this.timeout = timeout; this.retry = retry; this.pending = new Map();
    this.host = null; this.socket = null; this.ready = false;
    this.value = null; this.muted = null; this.measuring = null;
    this.status = 'Not configured';
  }
  configure(host) {
    if (host === this.host) return;
    this.host = host;
    this.drop('Connecting');
    if (host) this.open();
    else { this.status = 'Not configured'; this.onChange(); }
  }
  open() {
    clearTimeout(this.reconnect);
    let socket;
    try { socket = this.socketFactory(`ws://${this.host}:5555`); }
    catch { this.drop('Unable to connect'); return; }
    this.socket = socket;
    this.connectTimer = setTimeout(() => this.drop('Connection timed out'), this.timeout);
    socket.addEventListener('open', async () => {
      if (this.socket !== socket) return;
      clearTimeout(this.connectTimer);
      try {
        await this.refresh(socket);
        if (this.socket !== socket) return;
        this.ready = true; this.status = 'Connected'; this.onChange();
        this.heartbeat = setInterval(() => {
          // A command may already be refreshing these endpoints.
          if (!this.pending.size) this.refresh(socket).catch(() => {});
        }, 15000);
      } catch { /* request failure drops the connection */ }
    });
    socket.addEventListener('message', event => {
      if (this.socket !== socket) return;
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      const fields = { volume_change_db: 'value', mute_change: 'muted', dirac_measurement_mode: 'measuring' };
      if (fields[message.notification]) {
        if (this.valid(fields[message.notification], message.value)) {
          this[fields[message.notification]] = message.value; this.onChange();
        }
        return;
      }
      const request = this.pending.get(message.req);
      if (!request) return;
      this.pending.delete(message.req); clearTimeout(request.timer);
      if (message.status !== 'OK') {
        request.reject(new Error(`Tide16 rejected ${message.req}`));
        this.drop('Device rejected request');
      } else request.resolve(message.data);
    });
    for (const event of ['close', 'error']) socket.addEventListener(event, () => {
      if (this.socket === socket) this.drop('Disconnected');
    });
  }
  valid(field, value) {
    return field === 'value' ? typeof value === 'number' && Number.isFinite(value) && value >= -127.5 && value <= 0 : typeof value === 'boolean';
  }
  request(endpoint, parameters = {}, socket = this.socket) {
    if (!socket || socket !== this.socket || socket.readyState !== 1) return Promise.reject(new Error('Tide16 disconnected'));
    if (this.pending.has(endpoint)) return Promise.reject(new Error('Tide16 busy'));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => this.drop('Request timed out'), this.timeout);
      this.pending.set(endpoint, { resolve, reject, timer });
      try { socket.send(JSON.stringify({ endpoint, ...parameters })); }
      catch { this.drop('Unable to send request'); }
    });
  }
  async refresh(socket = this.socket) {
    try {
      const [value, muted, measuring] = await Promise.all([
        this.request('get_volume_db', {}, socket), this.request('get_mute', {}, socket),
        this.request('get_dirac_measuring_mode', {}, socket)
      ]);
      if (socket !== this.socket) throw new Error('Tide16 disconnected');
      if (!this.valid('value', value) || !this.valid('muted', muted) || !this.valid('measuring', measuring)) {
        this.drop('Invalid device feedback'); throw new Error('Invalid Tide16 feedback');
      }
      this.value = value; this.muted = muted; this.measuring = measuring; this.onChange();
    } catch (error) { throw error; }
  }
  get volume() {
    return { type: 'db', value: this.value === null ? null : Math.round(this.value * 2) / 2, is_muted: this.muted, is_fixed: !this.ready || this.measuring !== false };
  }
  async control(action, mute, isCurrent) {
    if (!this.ready || this.measuring !== false) throw new Error('Tide16 unavailable');
    const socket = this.socket;
    // Read before writing so front-panel and remote changes are respected.
    await this.refresh(socket);
    if (!isCurrent() || socket !== this.socket || !this.ready || this.measuring !== false) throw new Error('Tide16 target changed or unavailable');
    if (action === 'mute') await this.request('set_mute', { value: mute === 'mute' }, socket);
    else await this.request('set_volume_db', { value: Math.max(-127.5, Math.min(0, Math.round(this.value * 2) / 2 + (action === 'up' ? 0.5 : -0.5))) }, socket);
    await this.refresh(socket);
  }
  drop(status) {
    clearTimeout(this.connectTimer); clearTimeout(this.reconnect); clearInterval(this.heartbeat);
    const socket = this.socket; this.socket = null;
    this.ready = false; this.value = null; this.muted = null; this.measuring = null; this.status = status;
    for (const request of this.pending.values()) { clearTimeout(request.timer); request.reject(new Error(`Tide16: ${status}`)); }
    this.pending.clear();
    if (socket) { try { socket.close(); } catch {} }
    this.onChange();
    if (this.host) this.reconnect = setTimeout(() => this.open(), this.retry);
  }
  stop() { this.host = null; this.drop('Not configured'); }
}
module.exports = { Tide16 };

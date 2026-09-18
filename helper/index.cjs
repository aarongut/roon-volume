'use strict';
// Roon's library logs protocol traffic; reserve stdout exclusively for IPC.
console.log = (...args) => console.error(...args);
const fs = require('node:fs');
const readline = require('node:readline');
const { Controller } = require('./controller.cjs');
const RoonApi = require('node-roon-api');
const Transport = require('node-roon-api-transport');
const dataDir = process.argv[2];
if (!dataDir) throw new Error('Application Support path is required');
fs.mkdirSync(dataDir, { recursive: true, mode: 0o700 });
process.umask(0o077);
process.chdir(dataDir);
const send = message => process.stdout.write(JSON.stringify(message) + '\n');
const controller = new Controller(send);
let paired;
const roon = new RoonApi({
  extension_id: 'tech.frat.roon-volume', display_name: 'Roon Volume', display_version: '0.1.0',
  publisher: 'Roon Volume', email: 'roon-volume@localhost', log_level: 'none',
  core_paired(core) {
    paired = core;
    const transport = core.services.RoonApiTransport;
    controller.connect(transport, core.display_name);
    transport.subscribe_zones((response, body) => { if (paired === core) controller.update(response, body); });
  },
  core_unpaired(core) { if (paired === core) { paired = null; controller.disconnect(); } }
});
roon.init_services({ required_services: [Transport] });
const input = readline.createInterface({ input: process.stdin });
input.on('line', line => {
  try { controller.command(JSON.parse(line)).catch(err => send({ type: 'error', error: err.message })); }
  catch (err) { send({ type: 'error', error: 'Invalid command' }); }
});
input.on('close', () => process.exit(0));
controller.snapshot();
roon.start_discovery();

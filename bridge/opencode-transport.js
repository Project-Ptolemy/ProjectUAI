'use strict';

// Native OpenCode's Bun transport offers these suites. Controlled requests with
// the same key, body and headers succeed with this offer but receive a free-model
// refusal with Node's default offer. Certificate and TLS-version defaults stay
// with Node; this profile does not require Bun or newer OpenSSL curve support.
const CIPHERS = [
  'TLS_AES_128_GCM_SHA256', 'TLS_AES_256_GCM_SHA384', 'TLS_CHACHA20_POLY1305_SHA256',
  'ECDHE-ECDSA-AES128-GCM-SHA256', 'ECDHE-RSA-AES128-GCM-SHA256',
  'ECDHE-ECDSA-AES256-GCM-SHA384', 'ECDHE-RSA-AES256-GCM-SHA384',
  'ECDHE-ECDSA-CHACHA20-POLY1305', 'ECDHE-RSA-CHACHA20-POLY1305',
  'ECDHE-ECDSA-AES128-SHA', 'ECDHE-RSA-AES128-SHA',
  'ECDHE-ECDSA-AES256-SHA', 'ECDHE-RSA-AES256-SHA',
  'AES128-GCM-SHA256', 'AES256-GCM-SHA384', 'AES128-SHA', 'AES256-SHA',
].join(':');

function optionsFor(url) {
  try {
    const u = new URL(url);
    if (u.protocol === 'https:' && u.hostname === 'opencode.ai' && !u.port && !u.username && !u.password &&
      !u.search && !u.hash && /^\/(?:zen\/v1|inference\/v1|inference\/openai\/v1)\/(?:chat\/completions|responses)\/?$/.test(u.pathname)) {
      return { ciphers: CIPHERS };
    }
  } catch { /* Other providers retain their ordinary transport. */ }
  return {};
}

module.exports = { optionsFor };

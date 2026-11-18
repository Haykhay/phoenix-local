import assert from 'node:assert/strict';
import { once } from 'node:events';
import http from 'node:http';
import { test } from 'node:test';

import { verifyBackstage } from './check-backstage.mjs';

test('verifies readiness, guest auth, templates, registry account, and orchestrator API', async () => {
  const seen = [];
  const server = http.createServer((request, response) => {
    seen.push(request.url);
    response.setHeader('content-type', 'application/json');
    if (request.url === '/.backstage/health/v1/readiness') return response.end('{}');
    if (request.url === '/api/auth/guest/refresh') {
      return response.end(JSON.stringify({ backstageIdentity: { token: 'test-token' } }));
    }
    if (request.url?.startsWith('/api/catalog/entities?filter=kind%3DTemplate')) {
      return response.end(JSON.stringify([
        { metadata: { name: 'phoenix-environment' } },
        { metadata: { name: 'phoenix-workload' } },
        { metadata: { name: 'phoenix-new-group' } },
      ]));
    }
    if (request.url?.startsWith('/api/catalog/entities?filter=kind%3DResource%2Cspec.type%3Daws-account')) {
      return response.end(JSON.stringify([{ metadata: {
        name: 'research-aws-account', annotations: { 'phoenix/account-id': '111111111111' },
      } }]));
    }
    if (request.url === '/api/orchestrator/requests') return response.end('[]');
    response.statusCode = 404;
    return response.end('{}');
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  try {
    const result = await verifyBackstage(`http://127.0.0.1:${address.port}`);
    assert.deepEqual(result, { templates: 3, accounts: 1, requests: 0 });
    assert.ok(seen.includes('/api/orchestrator/requests'));
  } finally {
    server.close();
  }
});

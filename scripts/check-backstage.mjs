import { pathToFileURL } from 'node:url';

async function json(url, init) {
  const response = await fetch(url, init);
  if (!response.ok) throw new Error(`${url} returned ${response.status}`);
  return response.json();
}

export async function verifyBackstage(baseUrl) {
  await json(`${baseUrl}/.backstage/health/v1/readiness`);
  const auth = await json(`${baseUrl}/api/auth/guest/refresh`, {
    headers: { origin: baseUrl },
  });
  const token = auth?.backstageIdentity?.token;
  if (!token) throw new Error('guest auth did not return a Backstage token');
  const headers = { authorization: `Bearer ${token}` };

  const entities = async filter => {
    const url = new URL('/api/catalog/entities', baseUrl);
    url.searchParams.set('filter', filter);
    return json(url, { headers });
  };
  const templates = await entities('kind=Template');
  const templateNames = new Set(templates.map(entity => entity.metadata?.name));
  for (const name of ['phoenix-environment', 'phoenix-workload', 'phoenix-new-group']) {
    if (!templateNames.has(name)) throw new Error(`catalog template missing: ${name}`);
  }

  const accounts = await entities('kind=Resource,spec.type=aws-account');
  const account = accounts.find(entity => entity.metadata?.name === 'research-aws-account');
  if (account?.metadata?.annotations?.['phoenix/account-id'] !== '111111111111') {
    throw new Error('Floci registry account was not projected into the catalog');
  }

  const requests = await json(`${baseUrl}/api/orchestrator/requests`, { headers });
  if (!Array.isArray(requests)) throw new Error('orchestrator requests response is not an array');
  return { templates: templates.length, accounts: accounts.length, requests: requests.length };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const baseUrl = process.argv[2];
  if (!baseUrl) throw new Error('usage: check-backstage.mjs <base-url>');
  const result = await verifyBackstage(baseUrl);
  console.log(`Backstage verified: ${result.templates} templates, ${result.accounts} accounts, ${result.requests} orchestration requests`);
}

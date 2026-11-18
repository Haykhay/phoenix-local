const [url, attemptsValue = '60'] = process.argv.slice(2);
if (!url) throw new Error('usage: check-http.mjs <url> [attempts]');

const attempts = Number(attemptsValue);
for (let attempt = 1; attempt <= attempts; attempt += 1) {
  try {
    const response = await fetch(url);
    if (response.ok) process.exit(0);
  } catch {
    // The service may still be starting.
  }
  await new Promise(resolve => setTimeout(resolve, 1_000));
}
throw new Error(`${url} did not become healthy after ${attempts} attempts`);

export function configFromEnv(env = process.env) {
  const config = {
    env: env.PLAID_ENV ?? 'sandbox', countries: (env.PLAID_COUNTRY_CODES ?? 'US').split(',').map(code => code.trim()), clientID: env.PLAID_CLIENT_ID,
    secret: env.PLAID_SECRET, apiToken: env.TENDER_API_TOKEN,
    key: Buffer.from(env.TENDER_ENCRYPTION_KEY ?? '', 'base64'),
    redirect: env.PLAID_REDIRECT_URI,
    user: env.TENDER_USER_ID ?? 'tender-personal',
    dataFile: env.TENDER_DATA_FILE ?? `./data/bank-links-${env.PLAID_ENV ?? 'sandbox'}.enc`,
    linkMode: env.TENDER_LINK_MODE ?? 'native', publicURL: env.TENDER_PUBLIC_URL,
    team: env.APPLE_TEAM_ID, bundle: env.APPLE_BUNDLE_ID ?? 'com.sean.tender',
  };
  const secureURL = value => { try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash; } catch { return false; } };
  if (!config.countries.length || config.countries.some(code => !['US', 'CA'].includes(code)) || !['sandbox', 'production'].includes(config.env) || !config.clientID || !config.secret || !config.apiToken || config.apiToken.length < 32 || config.key.length !== 32 || (config.linkMode === 'browser' ? !secureURL(config.publicURL) : !secureURL(config.redirect)) || !['native', 'browser'].includes(config.linkMode)) {
    throw new Error('Configure Plaid keys, HTTPS public URL (browser) or redirect (native), a 32+ character API token, and a base64 32-byte encryption key in .env.');
  }
  return config;
}

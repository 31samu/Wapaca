import {readFile} from 'node:fs/promises';

export function configuredSubscriptions(config, env = process.env) {
  const sources = env.CALENDAR_URL ? [{id:'legacy',url:env.CALENDAR_URL,name:'Calendar',legacyIds:true}]
    : config.subscriptions ?? (config.subscriptionUrl ? [{id:'legacy',url:config.subscriptionUrl,name:'TimeEdit',legacyIds:true}] : []);
  const ids = new Set(), urls = new Set();
  return sources.map(source => {
    const url = new URL(source.url);
    if (url.protocol !== 'https:') throw new Error('Calendar subscriptions must use HTTPS.');
    if (!source.id || ids.has(source.id) || urls.has(url.href)) throw new Error('Subscriptions need unique IDs and URLs.');
    ids.add(source.id); urls.add(url.href);
    return {...source, url:url.href, name:source.name || url.hostname,
      kind:source.kind || (url.hostname.endsWith('.timeedit.net') || url.hostname === 'timeedit.net' ? 'timeedit' : 'generic')};
  });
}

export async function loadSnapshots(config) {
  const sources = configuredSubscriptions(config);
  const cache = JSON.parse(await readFile('data/calendars.json','utf8').catch(error => {
    if (error.code !== 'ENOENT') throw error;
    return 'null';
  }));
  if (cache) return sources.map(source => ({...source,...cache.subscriptions.find(saved => saved.id === source.id && saved.url === source.url),...source}));
  const ics = await readFile('data/calendar.ics','utf8');
  const metadata = JSON.parse(await readFile('data/source.json','utf8').catch(()=>'{}'));
  if (!sources.length) return [{id:'legacy',legacyIds:true,ics,...metadata}];
  return sources.map(source => ({...source,...(source.legacyIds ? {ics,...metadata} : {})}));
}

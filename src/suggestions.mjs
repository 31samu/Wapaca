// Suggestions are local heuristics, not official course/module boundaries.
export function suggestModules(events, course = '', excludedEventIds = []) {
  const excluded = new Set(excludedEventIds);
  const days = value => Date.parse(value + 'T00:00:00Z') / 86400000;
  const intro = event => /^(intro(?:duction)?\b|introduktion\b)/i.test(event.title);
  const final = event => /\b(examination|examen|tentamen|final presentations?|slutpresentation)\b/i.test(event.title + ' ' + event.summary);
  const topic = event => {
    const title = event.title.replace(/^(introduction|introduktion|lecture|föreläsning)\s*[:–-]?\s*/i, '').trim();
    if (/https?:|registration|\b(tutor(?:ing|ials?)?|practice|seminar|workshop|intro|presentations?|examination|following|peer|writing support)\b/i.test(title) || title.length > 70) return '';
    return title;
  };
  const candidates = events.filter(event => event.calendarKind !== 'generic' && !event.cancelled && !event.allDay && !excluded.has(event.uid)
    && ![0,6].includes(new Date(event.date + 'T00:00:00Z').getUTCDay())
    && (!course || event.summary.split(',').map(s => s.trim()).includes(course)))
    .sort((a,b) => a.start.localeCompare(b.start) || a.uid.localeCompare(b.uid));
  const groups = []; let current = [];
  for (const event of candidates) {
    const previous = current.at(-1);
    const gap = previous ? days(event.date) - days(previous.date) : 0;
    const changedTopic = intro(event) && topic(event) && current.some(e => topic(e)) && !current.some(e => topic(e).toLowerCase() === topic(event).toLowerCase());
    if (previous && event.date !== previous.date && (final(previous) || (gap >= 14 && !final(event)) || changedTopic || days(event.date)-days(current[0].date)>70)) {
      groups.push(current); current = [];
    }
    current.push(event);
  }
  if (current.length) groups.push(current);
  return groups.filter(group => group.length >= 2).map(group => {
    const first = group[0], last = group.at(-1);
    const introduction = group.find(intro), examination = group.findLast(final);
    const named = group.find(e => intro(e) && topic(e)) || group.filter(e => topic(e)).sort((a,b) => topic(a).length-topic(b).length)[0];
    const reasons = [];
    if (introduction) reasons.push(`${introduction.date}: ${introduction.title}`);
    if (named && named !== introduction) reasons.push(`Topic from ${named.date}: ${named.title}`);
    if (examination) reasons.push(`${examination.date}: ${examination.title}`);
    const before = candidates[candidates.indexOf(first)-1];
    if (before && days(first.date)-days(before.date)>=14) reasons.push(`${days(first.date)-days(before.date)} days since the previous course session.`);
    if (!reasons.length) reasons.push('Sessions grouped by schedule gaps. No clear module title or examination found.');
    return {name:named ? topic(named) : 'Suggested module',start:first.date,end:last.date,count:group.length,reasons,
      confidence:examination && (introduction || named) ? 'Stronger evidence' : 'Tentative range'};
  });
}

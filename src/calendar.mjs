import ICAL from 'ical.js';

export function localParts(instant, timeZone) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
  }).formatToParts(new Date(instant)).map(p => [p.type, p.value]));
  return { date: `${parts.year}-${parts.month}-${parts.day}`, time: `${parts.hour}:${parts.minute}` };
}

export function cleanDescription(value = '') {
  return (value || '').replace(/(?:^|\n)\s*ID\s+\d+\s*$/i, '').trim();
}

// The first prototype accepts concrete UTC events and date-only events. Reject
// unsupported calendar semantics instead of silently rendering wrong dates.
export function parseCalendar(source, timeZone = 'Europe/Stockholm') {
  const calendar = new ICAL.Component(ICAL.parse(source));
  if (calendar.name !== 'vcalendar') throw new Error('Expected an iCalendar VCALENDAR.');
  const keys = new Set();
  const events = calendar.getAllSubcomponents('vevent').map(component => {
    const event = new ICAL.Event(component);
    if (event.isRecurring() || event.isRecurrenceException()) {
      throw new Error('Recurring events need expansion support before this feed can be previewed.');
    }
    if (!event.uid || keys.has(event.uid)) throw new Error('Missing or duplicate event UID; resolve before rendering.');
    keys.add(event.uid);
    // Cancellation notices may contain only the UID and status, without dates.
    if (String(component.getFirstPropertyValue('status')).toUpperCase() === 'CANCELLED') return null;
    if (!event.startDate || !event.endDate) throw new Error('An event is missing its dates.');
    const allDay = event.startDate.isDate;
    if (event.endDate.isDate !== allDay) throw new Error('Mixed date and time values in an event.');
    if (!allDay && (event.startDate.zone.tzid !== 'UTC' || event.endDate.zone.tzid !== 'UTC')) {
      throw new Error('This prototype supports UTC timed events. Named and floating timezones need validation first.');
    }
    const start = allDay ? event.startDate.toString() : event.startDate.toJSDate().toISOString();
    const end = allDay ? event.endDate.toString() : event.endDate.toJSDate().toISOString();
    if (end < start) throw new Error('An event ends before it starts.');
    const startLocal = allDay ? {date: start, time: ''} : localParts(start, timeZone);
    const endLocal = allDay ? {date: end, time: ''} : localParts(end, timeZone);
    const description = cleanDescription(event.description);
    const summary = event.summary || 'Untitled event';
    const summaryParts = summary.split(',').map(part => part.trim());
    const courseIndex = summaryParts.findIndex(part => /^\d[A-Z]{2}\d{3}$/.test(part));
    const fallbackTitle = courseIndex > 0 ? summaryParts.slice(0, courseIndex).join(', ') : summary;
    const title = description.split('\n').find(line => line.trim())?.trim() || fallbackTitle;
    const location = (event.location || '').replace(/\s+/g, ' ').trim();
    const room = location.match(/\b[A-Z]\d{3,4}[A-Z]?(?=\b|_)/)?.[0] || location;
    const mentionedRooms = [...description.matchAll(/\b[A-Z]\d{3,4}[A-Z]?\b/g)].map(match => match[0]);
    const roomConflict = Boolean(room && mentionedRooms.some(value => value !== room));
    return {
      uid: event.uid, start, end, allDay, date: startLocal.date,
      startTime: startLocal.time, endDate: endLocal.date, endTime: endLocal.time,
      title, summary, description, location,
      room: room + (/zoom/i.test(location) && !/zoom/i.test(room) ? ' · Zoom' : ''),
      roomConflict,
      kind: /examination|presentation/i.test(summary + ' ' + title) ? 'presentation'
        : /workshop|\bWS\b/i.test(summary) ? 'workshop' : 'session',
      cancelled: String(component.getFirstPropertyValue('status')).toUpperCase() === 'CANCELLED'
    };
  }).filter(Boolean);
  events.sort((a, b) => a.start.localeCompare(b.start) || a.uid.localeCompare(b.uid));
  return { name: calendar.getFirstPropertyValue('x-wr-calname') || 'Calendar', timeZone, events };
}

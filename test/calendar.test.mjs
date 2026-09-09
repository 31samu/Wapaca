import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCalendar, localParts } from '../src/calendar.mjs';
import { buildGrid, renderWallpaper, wrapText } from '../src/layout.mjs';
const ics = (body) =>
  `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:test@example.com\r\n${body}\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n`;
test('unfolds and unescapes real ICS text; uses description title and flags room disagreement', () => {
  const {
    events: [event],
  } = parseCalendar(
    ics(
      'DTSTART:20260908T080000Z\r\nDTEND:20260908T100000Z\r\nSUMMARY:Workshop\\, 1DI300\r\nDESCRIPTION:Intro Day 2\\nWorkshop in M10\r\n 99B\\nID 123\r\nLOCATION:M1104V Food lab',
    ),
  );
  assert.equal(event.title, 'Intro Day 2');
  assert.equal(event.startTime, '10:00');
  assert.equal(event.endTime, '12:00');
  assert.equal(event.summary, 'Workshop, 1DI300');
  assert.equal(event.roomConflict, true);
  assert.equal(event.description, 'Intro Day 2\nWorkshop in M1099B');
});
test('Stockholm daylight-saving time is applied on both sides of the October transition', () => {
  assert.equal(localParts('2026-10-23T07:30:00Z', 'Europe/Stockholm').time, '09:30');
  assert.equal(localParts('2026-10-26T12:00:00Z', 'Europe/Stockholm').time, '13:00');
});
test('fallback labels omit course metadata and room codes handle TimeEdit suffixes', () => {
  const {
    events: [event],
  } = parseCalendar(
    ics(
      'DTSTART:20260922T110000Z\r\nDTEND:20260922T130000Z\r\nSUMMARY:Tutoring\\, 1DI300\\, DGVIC\r\nLOCATION:M1099B_V Ateljé 1',
    ),
  );
  assert.equal(event.title, 'Tutoring');
  assert.equal(event.room, 'M1099B');
  assert.equal(event.summary, 'Tutoring, 1DI300, DGVIC');
});
test('date-only end is exclusive and spans only visible weekdays', () => {
  const { events } = parseCalendar(
    ics('DTSTART;VALUE=DATE:20261030\r\nDTEND;VALUE=DATE:20261103\r\nSUMMARY:Holiday'),
  );
  const grid = buildGrid(events, {
    mode: 'module',
    start: '2026-10-26',
    end: '2026-11-08',
    course: '',
  });
  assert.equal(grid.columns, 5);
  assert.deepEqual(
    grid.rows
      .flat()
      .filter((day) => day.events.length)
      .map((day) => day.key),
    ['2026-10-30', '2026-11-02'],
  );
  assert.equal(grid.rows.flat().find((day) => day.key === '2026-11-03').events.length, 0);
});
test('both views fill existing weekday rows beyond the target range, without adding weeks or weekend events', () => {
  const dates = [
    '2026-08-28',
    '2026-08-31',
    '2026-09-01',
    '2026-09-05',
    '2026-09-06',
    '2026-09-30',
    '2026-10-02',
    '2026-10-05',
  ];
  const events = dates.map((date) => {
    const stamp = date.replaceAll('-', '');
    const event = parseCalendar(
      ics(`DTSTART:${stamp}T080000Z\r\nDTEND:${stamp}T100000Z\r\nSUMMARY:Lecture\\, 1DI300`),
    ).events[0];
    return { ...event, uid: date };
  });
  events.push({ ...events[1], uid: 'other-course', summary: 'Lecture, 1DI301' });
  for (const range of [
    { mode: 'month', month: '2026-09' },
    { mode: 'module', start: '2026-09-02', end: '2026-09-29' },
  ]) {
    const grid = buildGrid(events, { ...range, course: '1DI300' });
    assert.equal(grid.weeks, 5);
    assert.equal(grid.columns, 5);
    assert.equal(grid.rows[0][0].key, '2026-08-31');
    assert.equal(grid.rows.at(-1).at(-1).key, '2026-10-02');
    assert.deepEqual(
      grid.visible.map((event) => event.uid),
      ['2026-08-31', '2026-09-01', '2026-09-30', '2026-10-02'],
    );
    assert.deepEqual(
      grid.rows.flat().flatMap((day) => day.events.map((event) => event.uid)),
      grid.visible.map((event) => event.uid),
    );
  }
});
test('module aligns to five weeks, month can occupy six, and invalid ranges fail', () => {
  assert.equal(
    buildGrid([], { mode: 'module', start: '2026-10-05', end: '2026-11-08', course: '' }).weeks,
    5,
  );
  assert.equal(buildGrid([], { mode: 'month', month: '2026-08', course: '' }).weeks, 6);
  assert.throws(
    () => buildGrid([], { mode: 'module', start: '2026-02-30', end: '2026-03-01', course: '' }),
    /valid/,
  );
});
test('unsupported recurrence is reported instead of omitted', () => {
  assert.throws(
    () =>
      parseCalendar(
        ics(
          'DTSTART:20260908T080000Z\r\nDTEND:20260908T100000Z\r\nRRULE:FREQ=WEEKLY\r\nSUMMARY:Lecture',
        ),
      ),
    /Recurring/,
  );
});
test('cancellation notices without dates are omitted; ambiguous UIDs and recurrence exceptions reject the feed', () => {
  assert.deepEqual(parseCalendar(ics('STATUS:CANCELLED')).events, []);
  const event =
    'BEGIN:VEVENT\r\nUID:same\r\nDTSTART:20260908T080000Z\r\nDTEND:20260908T100000Z\r\nEND:VEVENT\r\n';
  assert.throws(
    () => parseCalendar(`BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${event}${event}END:VCALENDAR`),
    /duplicate/,
  );
  assert.throws(
    () => parseCalendar(ics('RECURRENCE-ID:20260908T080000Z\r\nSTATUS:CANCELLED')),
    /Recurring/,
  );
  assert.throws(
    () =>
      parseCalendar(
        ics('DTSTART:20260908T080000Z\r\nDTEND:20260908T100000Z').replace(
          'UID:test@example.com\r\n',
          '',
        ),
      ),
    /UID/,
  );
});
test('spring and autumn transitions keep UTC instants on the correct local date and time', () => {
  assert.deepEqual(localParts('2026-03-29T00:30:00Z', 'Europe/Stockholm'), {
    date: '2026-03-29',
    time: '01:30',
  });
  assert.deepEqual(localParts('2026-03-29T01:30:00Z', 'Europe/Stockholm'), {
    date: '2026-03-29',
    time: '03:30',
  });
  assert.deepEqual(localParts('2026-10-25T00:30:00Z', 'Europe/Stockholm'), {
    date: '2026-10-25',
    time: '02:30',
  });
  assert.deepEqual(localParts('2026-10-25T01:30:00Z', 'Europe/Stockholm'), {
    date: '2026-10-25',
    time: '02:30',
  });
});
test('dense dates disclose overflow and source text cannot become SVG markup', () => {
  const {
    events: [event],
  } = parseCalendar(
    ics('DTSTART:20261005T080000Z\r\nDTEND:20261005T100000Z\r\nSUMMARY:<script>alert(1)</script>'),
  );
  const events = Array.from({ length: 25 }, (_, i) => ({ ...event, uid: String(i) }));
  const result = renderWallpaper(events, {
    mode: 'module',
    start: '2026-10-05',
    end: '2026-11-08',
    name: '<Test>',
    course: '',
    theme: 'light',
  });
  assert.match(result.svg, /&lt;Test&gt;/);
  assert.doesNotMatch(result.svg, /<script>/);
  assert.ok(result.warnings.some((w) => w.includes('do not fit')));
  assert.equal(result.grid.visible.length, 25);
});
test('long unbroken titles are shortened explicitly', () => {
  const { lines, truncated } = wrapText('x'.repeat(200), 100, 14, 3);
  assert.equal(lines.length, 3);
  assert.equal(truncated, true);
  assert.ok(lines.at(-1).endsWith('…'));
});
test('every date includes its month and long titles use free row height', () => {
  const title =
    'A long event title with enough words to continue across several lines when the row has room available';
  const { events } = parseCalendar(
    ics(`DTSTART:20260908T080000Z\r\nDTEND:20260908T100000Z\r\nSUMMARY:${title}`),
  );
  const result = renderWallpaper(events, {
    mode: 'module',
    start: '2026-08-31',
    end: '2026-10-04',
    name: 'Test',
    showTitle: false,
    course: '',
    theme: 'light',
  });
  for (const label of ['31 Aug', '1 Sept', '7 Sept', '30 Sept', '1 Oct', '2 Oct'])
    assert.match(result.svg, new RegExp(`>${label}<`));
  assert.doesNotMatch(result.warnings.join(' '), /full session title/);
  assert.match(result.svg, />available<\/text>/);
});

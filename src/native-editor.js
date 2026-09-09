// Internal worker API. No interface, DOM event handlers, storage, or network access.
// AppKit owns presentation and persistence. These names also support legacy callers.
const nativeDefaults = (() => {
  const today = localParts(new Date(), config.timeZone).date;
  return {
    mode: 'module',
    theme: 'light',
    month: today.slice(0, 7),
    ...config.module,
    course: config.allCalendars ? '' : config.course,
    timeZone: config.timeZone,
    width: config.width,
    height: config.height,
    showTitle: false,
    rooms: true,
    iconSpace: true,
    today,
    snapshotDate: 'none',
    excludedEventIds: Array.isArray(config.excludedEventIds)
      ? config.excludedEventIds.filter((id) => typeof id === 'string')
      : [],
  };
})();
let state = { ...nativeDefaults };
let data = { name: 'Calendar', events: [] };
let courseCode = config.course || '';
let revision = 0;
function advancedDay(previous) {
  const today = localParts(new Date(), previous.timeZone).date;
  return {
    ...previous,
    today,
    month:
      previous.mode === 'month' && previous.month === previous.today.slice(0, 7)
        ? today.slice(0, 7)
        : previous.month,
  };
}
function commit(nextData, next) {
  // All replacements are transactional, including invalid date ranges and dimensions.
  renderWallpaper(nextData.events, next);
  data = nextData;
  state = next;
  revision++;
  return true;
}
window.nativeLoad = function (payload) {
  const next = advancedDay({ ...nativeDefaults, ...payload.editor });
  next.excludedEventIds = Array.isArray(next.excludedEventIds)
    ? next.excludedEventIds.filter((id) => typeof id === 'string')
    : [];
  const parsed = payload.subscriptions
    ? parseCalendars(payload.subscriptions, next.timeZone)
    : payload.ics
      ? parseCalendar(payload.ics, next.timeZone)
      : { name: 'Calendar', events: [] };
  const fetchedAt =
    payload.fetchedAt ||
    payload.subscriptions
      ?.map((s) => s.fetchedAt)
      .filter(Boolean)
      .sort()[0];
  if (fetchedAt) next.snapshotDate = localParts(fetchedAt, next.timeZone).date;
  commit(parsed, next);
  if (Object.hasOwn(payload, 'courseCode')) courseCode = payload.courseCode || '';
  return true;
};
window.nativeUpdate = function (patch) {
  const editable = [
    'mode',
    'theme',
    'month',
    'name',
    'start',
    'end',
    'proposed',
    'course',
    'width',
    'height',
    'showTitle',
    'rooms',
    'iconSpace',
  ];
  if (Object.keys(patch).some((key) => !editable.includes(key)))
    throw new Error('Unknown editor setting.');
  const next = { ...state, ...patch };
  if (!['module', 'month'].includes(next.mode) || !['light', 'dark'].includes(next.theme))
    throw new Error('Choose a valid view and appearance.');
  if (typeof next.name !== 'string' || !next.name.trim()) throw new Error('Enter a module name.');
  if (['name', 'start', 'end'].some((key) => Object.hasOwn(patch, key))) next.proposed = false;
  return commit(data, next);
};
window.nativeInclude = function (uid, included) {
  if (
    typeof uid !== 'string' ||
    typeof included !== 'boolean' ||
    !data.events.some((event) => event.uid === uid)
  )
    throw new Error('The event is no longer available.');
  const excluded = new Set(state.excludedEventIds);
  if (included) excluded.delete(uid);
  else excluded.add(uid);
  return commit(data, { ...state, excludedEventIds: [...excluded] });
};
window.nativeSources = function (subscriptions, clearCourse) {
  return commit(parseCalendars(subscriptions, state.timeZone), {
    ...state,
    ...(clearCourse ? { course: '' } : {}),
  });
};
window.nativeReset = function () {
  const today = localParts(new Date(), nativeDefaults.timeZone).date;
  commit(
    { name: 'Calendar', events: [] },
    {
      ...nativeDefaults,
      mode: 'month',
      month: today.slice(0, 7),
      name: 'New module',
      start: today,
      end: dayAdd(today, 34),
      proposed: false,
      course: '',
      excludedEventIds: [],
      today,
    },
  );
  courseCode = '';
  return true;
};
window.nativeFeed = (ics, fetchedAt) =>
  window.nativeCalendars([{ id: 'legacy', legacyIds: true, ics }], fetchedAt);
window.nativeCalendars = function (subscriptions, fetchedAt) {
  return commit(parseCalendars(subscriptions, state.timeZone), {
    ...advancedDay(state),
    snapshotDate: localParts(fetchedAt, state.timeZone).date,
  });
};
window.nativeDay = function () {
  const next = advancedDay(state);
  return next.today === state.today ? false : commit(data, next);
};
window.nativeSnapshot = function () {
  const result = renderWallpaper(data.events, state);
  const candidates = buildGrid(data.events, { ...state, excludedEventIds: [] }).visible;
  return {
    revision,
    editor: { ...state, excludedEventIds: [...state.excludedEventIds] },
    courseCode,
    events: candidates.map((event) => ({
      ...event,
      included: !state.excludedEventIds.includes(event.uid),
    })),
    suggestions: suggestModules(data.events, courseCode, state.excludedEventIds),
    warnings: result.warnings,
    includedCount: result.grid.visible.length,
    svg: result.svg,
  };
};
async function pngBase64(svg) {
  const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
  try {
    const image = new Image();
    await new Promise((resolve, reject) => {
      image.onload = resolve;
      image.onerror = () => reject(new Error('Could not render the wallpaper image.'));
      image.src = url;
    });
    const canvas = document.createElement('canvas');
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    canvas.getContext('2d').drawImage(image, 0, 0);
    return canvas.toDataURL('image/png').split(',')[1];
  } finally {
    URL.revokeObjectURL(url);
  }
}
window.nativePNG = async function () {
  const currentRevision = revision;
  const png = await pngBase64(renderWallpaper(data.events, state).svg);
  return { revision: currentRevision, png };
};
window.nativePair = async function () {
  // Capture both SVGs before yielding so edits cannot mix two different calendars.
  const lightSVG = renderWallpaper(data.events, { ...state, theme: 'light' }).svg;
  const darkSVG = renderWallpaper(data.events, { ...state, theme: 'dark' }).svg;
  const name = state.name;
  return { version: 1, name, light: await pngBase64(lightSVG), dark: await pngBase64(darkSVG) };
};

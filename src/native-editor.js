// Runs only in the bundled Mac editor. All calendar parsing stays local.
if (window.webkit?.messageHandlers?.timetable) {
  const send=(type,body={})=>window.webkit.messageHandlers.timetable.postMessage({type,...body});
  const originalRender=render;
  render=function(){originalRender();if(result)send('settings',{editor:{...state}});};
  document.querySelectorAll('.note').forEach(p=>{
    if(p.textContent.startsWith('This preview uses'))p.textContent='Settings and event choices are saved on this Mac. Refresh checks your subscription; a failed check keeps the last working calendar.';
  });
  const browserHeic=$('export-heic');
  const nativeHeic=browserHeic.cloneNode(true);
  browserHeic.replaceWith(nativeHeic);
  nativeHeic.addEventListener('click',async()=>{
    nativeHeic.disabled=true;nativeHeic.textContent='Preparing HEIC…';
    try{send('exportHeic',{pair:await window.nativePair()});}
    catch(error){$('error').textContent=error.message;}
    finally{nativeHeic.disabled=false;nativeHeic.textContent='Export HEIC';}
  });
  window.nativeLoad=function(payload){
    if(payload.editor)Object.assign(state,payload.editor);
    if(payload.editor?.showTitle===undefined)state.showTitle=false;
    const today=localParts(new Date(),state.timeZone).date;
    if(state.mode==='month'&&state.month===state.today.slice(0,7))state.month=today.slice(0,7);
    state.today=today;
    if(payload.ics){const parsed=parseCalendar(payload.ics,state.timeZone);Object.assign(data,parsed);}
    if(payload.fetchedAt)state.snapshotDate=localParts(payload.fetchedAt,state.timeZone).date;
    if(payload.courseCode)config.course=payload.courseCode;
    for(const [id,key] of binds)$(id).value=state[key];
    $('show-title').checked=state.showTitle;$('rooms').checked=state.rooms;$('icon-space').checked=state.iconSpace;
    $('course').value=state.course?'course':'all';
    const size=`${state.width}x${state.height}`;
    if(![...$('resolution').options].some(o=>o.value===size))$('resolution').add(new Option(size.replace('x',' × '),size));
    $('resolution').value=size;
    $('snapshot').textContent='Calendar snapshot · '+state.snapshotDate;
    $('selection-note').textContent='Event choices stay saved after refresh. If TimeEdit replaces an event with a new ID, it appears as a new event.';
    render();
  };
  window.nativeFeed=function(ics,fetchedAt){
    const parsed=parseCalendar(ics,state.timeZone);
    // Validate the selected layout before replacing the working calendar.
    renderWallpaper(parsed.events,state);
    Object.assign(data,parsed);
    state.snapshotDate=localParts(fetchedAt,state.timeZone).date;
    state.today=localParts(new Date(),state.timeZone).date;
    $('snapshot').textContent='Calendar snapshot · '+state.snapshotDate;
    render();return true;
  };
  window.nativeDay=function(){
    const today=localParts(new Date(),state.timeZone).date;
    if(state.today===today)return false;
    if(state.mode==='month'&&state.month===state.today.slice(0,7))state.month=today.slice(0,7);
    state.today=today;$('month').value=state.month;render();return true;
  };
  window.nativePair=async function(){
    if(!result)throw new Error('Fix the date range before applying.');
    const snapshot={...state,excludedEventIds:[...state.excludedEventIds]};
    const light=await base64Blob(await pngBlob(renderWallpaper(data.events,{...snapshot,theme:'light'}).svg));
    const dark=await base64Blob(await pngBlob(renderWallpaper(data.events,{...snapshot,theme:'dark'}).svg));
    return {version:1,name:snapshot.name,light,dark};
  };
  download=async function(blob,extension){
    if(extension==='timetable')send('apply',{pair:JSON.parse(await new Promise(resolve=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.readAsText(blob);} ))});
    else send('export',{extension,base64:await base64Blob(blob)});
  };
  send('ready');
}

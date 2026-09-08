// Runs only in the bundled Mac editor. All calendar parsing stays local.
if (window.webkit?.messageHandlers?.wapacal) {
  const send=(type,body={})=>window.webkit.messageHandlers.wapacal.postMessage({type,...body});
  const nativeDefaults={...state,excludedEventIds:[]};
  const originalRender=render;
  render=function(){originalRender();if(result)send('settings',{editor:{...state}});};
  document.querySelectorAll('.note').forEach(p=>{
    if(p.textContent.startsWith('This preview uses'))p.textContent='Settings and event choices are saved on this Mac. Refresh checks your subscriptions; a failed check keeps the last working calendar.';
  });
  const browserHeic=$('export-heic');
  const nativeHeic=browserHeic.cloneNode(true);
  browserHeic.replaceWith(nativeHeic);
  document.addEventListener('keydown',event=>{
    if(event.key!=='Escape')return;
    const suggestions=$('module-suggestions');
    if(suggestions&&!suggestions.hidden){
      suggestions.hidden=true;
      $('suggest-modules')?.focus();
      event.preventDefault();
      return;
    }
    const details=document.querySelector('details[open]');
    if(details){
      details.open=false;
      event.preventDefault();
    }
  });
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
    if(payload.subscriptions){Object.assign(data,parseCalendars(payload.subscriptions,state.timeZone));}
    else if(payload.ics){const parsed=parseCalendar(payload.ics,state.timeZone);Object.assign(data,parsed);}
    if(payload.fetchedAt)state.snapshotDate=localParts(payload.fetchedAt,state.timeZone).date;
    if(Object.hasOwn(payload,'courseCode'))config.course=payload.courseCode||'';
    for(const [id,key] of binds)$(id).value=state[key];
    $('show-title').checked=state.showTitle;$('rooms').checked=state.rooms;$('icon-space').checked=state.iconSpace;
    $('course').value=state.course?'course':'all';
    const size=`${state.width}x${state.height}`;
    if(![...$('resolution').options].some(o=>o.value===size))$('resolution').add(new Option(size.replace('x',' × '),size));
    $('resolution').value=size;
    $('snapshot').textContent='Calendar snapshot · '+state.snapshotDate;
    $('selection-note').textContent='Event choices stay saved after refresh. If a calendar replaces an event with a new ID, it appears as a new event.';
    render();
  };
  window.nativeReset=function(){
    const today=localParts(new Date(),state.timeZone).date;
    Object.assign(data,{name:'Calendar',events:[]});
    Object.assign(state,nativeDefaults,{mode:'month',month:today.slice(0,7),name:'New module',start:today,end:dayAdd(today,34),proposed:false,course:'',excludedEventIds:[],today,snapshotDate:'none'});
    config.course='';
    for(const [id,key] of binds)$(id).value=state[key];
    $('show-title').checked=state.showTitle;$('rooms').checked=state.rooms;$('icon-space').checked=state.iconSpace;$('course').value='all';
    $('snapshot').textContent='No saved calendar';
    render();return true;
  };
  window.nativeFeed=function(ics,fetchedAt){
    return window.nativeCalendars([{id:'legacy',legacyIds:true,ics}],fetchedAt);
  };
  window.nativeCalendars=function(subscriptions,fetchedAt){
    const parsed=parseCalendars(subscriptions,state.timeZone);
    const today=localParts(new Date(),state.timeZone).date;
    const next={...state,today,snapshotDate:localParts(fetchedAt,state.timeZone).date};
    if(state.mode==='month'&&state.month===state.today.slice(0,7))next.month=today.slice(0,7);
    // Validate the selected layout before replacing the working calendar.
    renderWallpaper(parsed.events,next);
    Object.assign(data,parsed);
    Object.assign(state,next);$('month').value=state.month;
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
    if(extension==='wapacal')send('apply',{pair:JSON.parse(await new Promise(resolve=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.readAsText(blob);} ))});
    else send('export',{extension,base64:await base64Blob(blob)});
  };
  send('ready');
}

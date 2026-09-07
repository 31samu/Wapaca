import test from 'node:test';
import assert from 'node:assert/strict';
import {suggestModules} from '../src/suggestions.mjs';
const event=(date,title,uid=title,summary='Lecture, COURSE')=>({date,start:date+'T08:00:00Z',title,uid,summary,allDay:false});
test('introductions and examinations separate modules without splitting draft presentations',()=>{
 const events=[event('2026-09-08','Intro Day 2'),event('2026-09-09','Worldbuilding'),event('2026-09-16','Tutoring'),event('2026-09-30','Presentation, examination'),event('2026-10-05','Introduction Intersectionality & Norms'),event('2026-10-14','Ideas presentation'),event('2026-10-23','Draft sketches'),event('2026-11-04','Final presentations')];
 const result=suggestModules(events,'COURSE');
 assert.deepEqual(result.map(({name,start,end})=>({name,start,end})),[{name:'Worldbuilding',start:'2026-09-08',end:'2026-09-30'},{name:'Intersectionality & Norms',start:'2026-10-05',end:'2026-11-04'}]);
 assert.match(result[0].reasons.join(' '),/examination/);
 assert.equal(suggestModules([...events,event('2026-10-01','Other introduction','other','OTHER')],'COURSE').length,2);
 assert.equal(suggestModules(events,'COURSE',['Intro Day 2'])[0].start,'2026-09-09');
});
test('gaps and new introductions propose boundaries, with no guesses for empty calendars',()=>{
 assert.deepEqual(suggestModules([]),[]);
 const result=suggestModules([event('2026-09-01','Practice'),event('2026-09-02','Practice','two'),event('2026-09-21','Introduction Painting'),event('2026-09-22','Painting')]);
 assert.equal(result.length,2);assert.equal(result[0].confidence,'Tentative range');
 assert.match(result[1].reasons.join(' '),/19 days/);
 const topics=suggestModules([event('2026-09-01','Introduction Drawing'),event('2026-09-02','Drawing'),event('2026-09-07','Introduction Painting'),event('2026-09-08','Painting')]);
 assert.equal(topics.length,2);
});

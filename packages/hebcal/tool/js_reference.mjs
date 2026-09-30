import {HDate, HebrewCalendar, Location, Zmanim, OmerEvent, Molad, DailyLearning} from '@hebcal/core';
import '@hebcal/learning';
const out = [];
const tz = (loc) => new Intl.DateTimeFormat('en-GB',{timeZone:loc.getTzid(),hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false});
// 1. calendar events
for (const [name, il] of [['New York', false], ['Jerusalem', true]]) {
  const loc = Location.lookup(name);
  const evs = HebrewCalendar.calendar({year: 5786, isHebrewYear: true, location: loc, candlelighting: true, sedrot: true, omer: true, molad: true, shabbatMevarchim: true, yomKippurKatan: true, behab: true, yizkor: true, il,
    dailyLearning: {dafYomi:true,mishnaYomi:true,nachYomi:true,yerushalmi:1,rambam1:true,rambam3:true,chofetzChaim:true,shemiratHaLashon:true,psalms:true,pirkeiAvotSummer:true,dafWeekly:true,kitzurShulchanAruch:true,arukhHaShulchanYomi:true,perekYomi:true,tanakhYomi:true,'929':true,dirshuAmudYomi:true,dirshuDafHalacha:true,seferHaMitzvot:true}});
  for (const ev of evs) out.push(`CAL ${name} ${ev.getDate().toString()} | ${ev.render('en')} | ${ev.render('he')}`);
}
// 2. zmanim for a range of days
for (const name of ['New York','Jerusalem','London','Hawaii','Sydney','Helsinki']) {
  const loc = Location.lookup(name); const f = tz(loc);
  for (let i=0;i<400;i+=7){ const d=new Date(2025,0,1+i); const z=new Zmanim(loc,d,false);
    const vals=['alotHaShachar','misheyakir','sunrise','sofZmanShma','sofZmanShmaMGA','sofZmanTfilla','chatzot','minchaGedola','minchaKetana','plagHaMincha','sunset','tzeit','beinHaShmashos','chatzotNight'].map(k=>{const t=z[k](); return isNaN(t)?'X':f.format(t)});
    out.push(`ZM ${name} ${d.getFullYear()}-${d.getMonth()+1}-${d.getDate()} ${vals.join(' ')}`);
  }
}
// 3. hdate conversions, tachanun, hallel, molad
for (let i=0;i<3000;i+=13){ const d=new Date(2020,0,1+i); const hd=new HDate(d);
  const t=HebrewCalendar.tachanun(hd,false);
  out.push(`HD ${d.getFullYear()}-${d.getMonth()+1}-${d.getDate()} ${hd.toString()} ${hd.renderGematriya()} T${+t.shacharit}${+t.mincha}${+t.allCongs} H${HebrewCalendar.hallel(hd,false)}`);
}
for (let y=5780;y<5800;y++) for (let m=1;m<=13;m++){ if(m==13&&!HDate.isLeapYear(y))continue; const mo=new Molad(y,m); out.push(`MOLAD ${y} ${m} ${mo.render('en')} ${mo.getInstant().epochMilliseconds}`);}
for (let o=1;o<=49;o++){ const e=new OmerEvent(new HDate(),o); out.push(`OMER ${o} ${e.getTodayIs('he')} | ${e.sefira('he')} | ${e.getTodayIs('en')}`);}
console.log(out.join('\n'));

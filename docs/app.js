'use strict';
const URL='https://rxpsezjtjqfksdxcxmuw.supabase.co';
const KEY='sb_publishable_raRn7YXbKCXuFt2j3i-EXQ_dNbMVXEP';
const $=id=>document.getElementById(id);
let session=null,archive={},timer=null,syncing=false,refreshing=false;
const today=()=>new Date(Date.now()-new Date().getTimezoneOffset()*60000).toISOString().slice(0,10);
$('day').value=today();
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num=v=>{const n=Number(v);return Number.isFinite(n)?n:null};
const fmt=(v,unit='KM')=>num(v)===null?'Veri yok':num(v).toFixed(2)+' '+unit;
function status(s){$('status').textContent=s}
function view(){const ok=!!session?.access_token;$('login').hidden=ok;$('app').hidden=!ok;if(ok)render()}
function dbOpen(){return new Promise((resolve,reject)=>{const r=indexedDB.open('ssoil-s2-pwa',1);r.onupgradeneeded=()=>r.result.createObjectStore('days');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)})}
async function putDay(day,value){const db=await dbOpen();await new Promise((resolve,reject)=>{const t=db.transaction('days','readwrite');t.objectStore('days').put(value,day);t.oncomplete=resolve;t.onerror=()=>reject(t.error)});db.close()}
async function getAllDays(){const db=await dbOpen();const result=await new Promise((resolve,reject)=>{const t=db.transaction('days','readonly'),s=t.objectStore('days'),r=s.getAllKeys(),v=s.getAll();t.oncomplete=()=>resolve([r.result,v.result]);t.onerror=()=>reject(t.error)});db.close();return Object.fromEntries(result[0].map((k,i)=>[k,result[1][i]]))}
async function authRefresh(){if(!session?.refresh_token)throw Error('Oturum yenileme bilgisi yok');const r=await fetch(URL+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:session.refresh_token})});if(!r.ok)throw Error('Oturum yenilenemedi');session=await r.json();session.expiry=Date.now()+(session.expires_in||3600)*1000;localStorage.setItem('ssoil_pwa_session',JSON.stringify(session))}
async function api(path,retry=true){if(session?.expiry&&Date.now()>session.expiry-120000)await authRefresh();const r=await fetch(URL+'/rest/v1/'+path,{headers:{apikey:KEY,Authorization:'Bearer '+session.access_token}});if(r.status===401&&retry){await authRefresh();return api(path,false)}if(!r.ok)throw Error('Sunucu yanıtı: '+r.status);return r.json()}
async function allRows(table,query){const result=[];for(let offset=0;offset<100000;offset+=500){const rows=await api(table+'?'+query+'&limit=500&offset='+offset);result.push(...rows);if(rows.length<500)break}return result}
function line(label,v,unit='KM'){return '<div class="line"><span>'+safe(label)+'</span><b>'+fmt(v,unit)+'</b></div>'}
function section(title,lines){return '<div class="card"><h2>'+title+'</h2>'+lines+'</div>'}
function val(o,k){return o&&o[k]!=null?o[k]:null}
function sum(a,b){return num(a)==null||num(b)==null?null:num(a)+num(b)}
function stockRow(id,name,cls,stocks){const stock=num(stocks?.[id]?.stock),max=Math.max(0,...['1','2','3'].map(k=>num(stocks?.[k]?.stock)||0));return '<div class="stockrow"><span class="fuelname '+cls+'">'+name+'</span><span class="track"><span class="fill '+cls+'" style="width:'+(stock===null||max===0?0:Math.min(100,100*stock/max))+'%"></span></span><b>'+(stock===null?'Veri yok':Math.round(stock).toLocaleString('tr-TR')+' L')+'</b></div>'}
function priceRow(name,p){return '<div class="pricerow"><strong>'+name+'</strong><span>'+(num(p?.purchase_price)===null?'Veri yok':num(p.purchase_price).toFixed(2).replace('.',','))+'</span><b>'+(num(p?.sale_price)===null?'Veri yok':num(p.sale_price).toFixed(2).replace('.',','))+'</b></div>'}
function render(){
const day=$('day').value,d=archive[day];
if(!d){$('details').innerHTML=section('Geçmiş','<p class="muted">Bu tarih henüz telefona kaydedilmedi. İnternet bağlantısıyla geçmişi indirin.</p>');return}
const k=d.kasa||{},p=d.prices||{},st=d.fuelProducts||{};
const total=sum(k.cash,k.card);
let out=section('▣ &nbsp; Günlük Satış',[
line('Nakit Yakıt Market',sum(k.cash_market,k.cash_fuel)),
line('Nakit Dopuna (MTEL + AERO)',sum(k.mtel_dopuna,k.aero_dopuna)),
line('Nakit (Dopuna dahil)',k.cash),
line('Kredi Kartı',k.card),
'<div class="total">'+line('Genel Toplam',total)+'</div>'
].join(''));
out+=section('▤ &nbsp; Satış Grupları',[
line('Yakıt',k.fuel_sales),line('Market',k.market_sales),
line('MTEL Dopuna',k.mtel_dopuna),line('AERO Dopuna',k.aero_dopuna)
].join(''));
out+=section('⛽ &nbsp; Yakıt Stokları',
stockRow('2','Dizel','diesel',st)+stockRow('3','Dizel+','plus',st)+stockRow('1','Benzin','petrol',st));
out+=section('↗ &nbsp; Güncel Yakıt Fiyatları',
'<div class="pricerow pricehead"><strong>Yakıt</strong><span>Alış Fiyatı (KM/L)</span><span>Güncel Satış Fiyatı (KM/L)</span></div>'+
priceRow('Dizel',p.dizel)+priceRow('Dizel+',p.dizel_plus)+priceRow('Benzin',p.benzin));
out+='<div class="bottomtotal"><span>◉ &nbsp; Günlük Satış</span><b>'+fmt(total)+'</b></div>';
$('details').innerHTML=out;
}
async function fetchCurrent(){
if(refreshing||!session||!navigator.onLine)return;
refreshing=true;
try{
const day=$('day').value;
const rows=await api('ssoil_snapshots?kind=eq.kasa%3A'+day+'&select=data&limit=1');
const prices=await api('ssoil_fuel_daily_prices?sale_date=lte.'+day+'&select=sale_date,fuel_type,purchase_price,sale_price&order=sale_date.desc&limit=3000');
const stocks=await api('ssoil_fuel_daily_stock?stock_date=eq.'+day+'&select=fuel_id,closing_liters');
const products=day===today()?await api('ssoil_snapshots?kind=eq.products&select=data&limit=1'):[];
const old=archive[day]||{},next={...old};
if(rows[0]?.data)next.kasa=rows[0].data;
const priceMap={};for(const x of prices){const type=x.fuel_type;priceMap[type]??={};if(priceMap[type].sale_price==null&&x.sale_price!=null)priceMap[type].sale_price=x.sale_price;if(priceMap[type].purchase_price==null&&x.purchase_price!=null)priceMap[type].purchase_price=x.purchase_price}next.prices=priceMap;
if(stocks.length)next.fuelProducts=Object.fromEntries(stocks.map(x=>[String(x.fuel_id),{stock:x.closing_liters}]));
if(day===today()&&products[0]?.data?.products){const items=products[0].data.products;next.fuelProducts=Object.fromEntries(items.filter(x=>['1','2','3'].includes(String(x.id))).map(x=>[String(x.id),x]));}
if(JSON.stringify(old)!==JSON.stringify(next)){archive[day]=next;await putDay(day,next);if($('day').value===day)render();}
}finally{refreshing=false}
}
async function syncAll(){
if(syncing||!session)return;syncing=true;status('Geçmiş veriler güncelleniyor…');
try{
const [snapshots,prices,stocks]=await Promise.all([
allRows('ssoil_snapshots','kind=like.kasa%3A%2A&select=kind,data'),
allRows('ssoil_fuel_daily_prices','select=sale_date,fuel_type,purchase_price,sale_price&order=sale_date.asc'),
allRows('ssoil_fuel_daily_stock','select=stock_date,fuel_id,closing_liters')
]);
const days=new Set(Object.keys(archive));const kasaByDay={};
for(const s of snapshots){const day=String(s.kind||'').slice(5);if(/^\d{4}-\d{2}-\d{2}$/.test(day)&&s.data){days.add(day);kasaByDay[day]=s.data}}
for(const p of prices)if(p.sale_date)days.add(p.sale_date);
const stocksByDay={};for(const s of stocks){if(!s.stock_date)continue;days.add(s.stock_date);(stocksByDay[s.stock_date]??={})[String(s.fuel_id)]={stock:s.closing_liters}}
prices.sort((a,b)=>String(a.sale_date).localeCompare(String(b.sale_date)));
const running={};let ix=0;
for(const day of [...days].sort()){
while(ix<prices.length&&prices[ix].sale_date<=day){const p=prices[ix++],v=running[p.fuel_type]??={};if(p.sale_price!=null)v.sale_price=p.sale_price;if(p.purchase_price!=null)v.purchase_price=p.purchase_price}
const prev=archive[day]||{};
const next={...prev,kasa:kasaByDay[day]??prev.kasa??{},prices:Object.fromEntries(['benzin','dizel','dizel_plus'].map(t=>[t,{...(running[t]||{})}])),fuelProducts:stocksByDay[day]??prev.fuelProducts??{}};
archive[day]=next;await putDay(day,next)
}
// Today's live tank stock comes from the products snapshot, as in Android S2.
try{const products=await api('ssoil_snapshots?kind=eq.products&select=data&limit=1');const items=products[0]?.data?.products;if(Array.isArray(items)){const day=today(),live=Object.fromEntries(items.filter(x=>['1','2','3'].includes(String(x.id))).map(x=>[String(x.id),x]));archive[day]={...(archive[day]||{}),fuelProducts:live};await putDay(day,archive[day]);}}catch(_){}
$('syncInfo').textContent='Son güncelleme: '+new Date().toLocaleString('tr-TR')+' · '+days.size+' tarih';
status('Geçmişler telefona kaydedildi.');render()
}catch(e){status('Çevrimdışı: telefona kaydedilmiş geçmişler kullanılabilir.')}finally{syncing=false}
}
$('signIn').onclick=async()=>{status('Giriş yapılıyor…');try{const r=await fetch(URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({email:$('email').value.trim(),password:$('password').value})});if(!r.ok)throw Error('Giriş başarısız');session=await r.json();session.expiry=Date.now()+(session.expires_in||3600)*1000;localStorage.setItem('ssoil_pwa_session',JSON.stringify(session));$('password').value='';view();await syncAll();clearInterval(timer);timer=setInterval(()=>{if(!document.hidden&&navigator.onLine)fetchCurrent().catch(()=>{});},3000)}catch(e){status('Giriş başarısız. Bilgileri ve bağlantıyı kontrol edin.')}};

$('day').onchange=render;
$('reload').onclick=async()=>{status('Güncelleniyor…');try{await fetchCurrent();status('Güncellendi')}catch(e){status('Çevrimdışı: kaydedilmiş veriler gösteriliyor.')}};
$('sync').onclick=syncAll;
(async()=>{try{archive=await getAllDays()}catch(e){status('Yerel kayıt alanı açılamadı.')}try{session=JSON.parse(localStorage.getItem('ssoil_pwa_session')||'null')}catch(e){}view();status(navigator.onLine?'Hazır.':'Çevrimdışı: kaydedilmiş veriler gösteriliyor.');if(session){syncAll();timer=setInterval(()=>{if(!document.hidden&&navigator.onLine)fetchCurrent().catch(()=>{});},3000)}if('serviceWorker'in navigator)navigator.serviceWorker.getRegistrations().then(rs=>Promise.all(rs.map(r=>r.unregister()))).catch(()=>{})})();

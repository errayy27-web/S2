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
async function api(path,retry=true){if(session?.expiry&&Date.now()>session.expiry-120000)await authRefresh();const r=await fetch(URL+'/rest/v1/'+path,{cache:'no-store',headers:{apikey:KEY,Authorization:'Bearer '+session.access_token}});if(r.status===401&&retry){await authRefresh();return api(path,false)}if(!r.ok)throw Error('Sunucu yanıtı: '+r.status);return r.json()}
async function allRows(table,query){const result=[];for(let offset=0;offset<100000;offset+=500){const rows=await api(table+'?'+query+'&limit=500&offset='+offset);result.push(...rows);if(rows.length<500)break}return result}
function line(label,v,unit='KM'){return '<div class="line"><span>'+safe(label)+'</span><b>'+fmt(v,unit)+'</b></div>'}
function section(title,lines){return '<div class="card"><h2>'+title+'</h2>'+lines+'</div>'}
function val(o,k){return o&&o[k]!=null?o[k]:null}
function sum(a,b){return num(a)==null||num(b)==null?null:num(a)+num(b)}
function stockRow(id,name,cls,stocks){const stock=num(stocks?.[id]?.stock),max=Math.max(0,...['1','2','3'].map(k=>num(stocks?.[k]?.stock)||0));return '<div class="stockrow"><span class="fuelname '+cls+'">'+name+'</span><span class="track"><span class="fill '+cls+'" style="width:'+(stock===null||max===0?0:Math.min(100,100*stock/max))+'%"></span></span><b>'+(stock===null?'Veri yok':Math.round(stock).toLocaleString('tr-TR')+' L')+'</b></div>'}
function priceRow(name,p){return '<div class="pricerow"><strong>'+name+'</strong><span>'+(num(p?.purchase_price)===null?'Veri yok':num(p.purchase_price).toFixed(2).replace('.',','))+'</span><b>'+(num(p?.sale_price)===null?'Veri yok':num(p.sale_price).toFixed(2).replace('.',','))+'</b></div>'}
function bankSection(d){
const banks=d.banks||[],tx=d.bankTransactions||[],open=d.bankOpenings||[];
return section('▣ &nbsp; Bankalar',banks.length?banks.map(b=>{
const id=b.id,opening=num(open.find(x=>x.bank_id===id)?.opening_balance)||0;
const deposits=tx.filter(t=>t.kind==='cash_expense'&&/HESABA YATIRILAN|BANKA PARA YATIRMA/i.test(String(t.first_value||'')+' '+String(t.description||''))&&(t.bank_id===id||String(t.second_value||'').toUpperCase().includes(String(b.name||'').toUpperCase()))).reduce((a,t)=>a+(num(t.amount)||0),0);
const collection=tx.filter(t=>t.kind==='bank_collection'&&t.bank_id===id).reduce((a,t)=>a+(num(t.amount)||0),0);
const expense=tx.filter(t=>t.kind==='bank_expense'&&t.bank_id===id).reduce((a,t)=>a+(num(t.amount)||0),0);
return '<div class="bankentry"><h3>'+safe(b.name)+'</h3>'+line('Sabah açılış',opening)+line('Hesaba yatırılan',deposits)+line('Banka tahsilatları',collection)+line('Banka ödemeleri',expense)+'<div class="total">'+line('Güncel hesap',opening+deposits+collection-expense)+'</div></div>';
}).join(''):'<p class="muted">Kayıtlı banka yok</p>');
}
let gasoilQuote=null,gasoilError='Bağlanıyor…',gasoilLastAttempt=0;
async function refreshGasoilQuote(){
 if(!navigator.onLine||Date.now()-gasoilLastAttempt<55000)return;
 gasoilLastAttempt=Date.now();
 try{
 const response=await fetch('https://rxpsezjtjqfksdxcxmuw.supabase.co/functions/v1/ssoil-gasoil-quote',{cache:'no-store'});
 const q=await response.json();
 if(!response.ok||!Number.isFinite(q.price)||!Number.isFinite(q.change))throw Error(q.error||'Veri okunamadı');
 gasoilQuote=q;gasoilError='';
 }catch(e){gasoilQuote=null;gasoilError='Güncel veri alınamadı';}
 if(session)render();
}
function tomorrowFuelEstimate(prices){
 const q=gasoilQuote;
 if(!q||!Number.isFinite(q.change))return '<p class="muted">Tahmin için güncel değişim bekleniyor.</p>';
 // User formula: quote change / 1000 * 7.5, then add 17%.
 const diff=(q.change/1000)*7.5*1.17;
 const values=[['Dizel','dizel'],['Dizel+','dizel_plus'],['Benzin','benzin']];
 const rows=values.map(([label,key])=>{
 const current=num(prices?.[key]?.purchase_price);
 const predicted=current===null?null:current+diff;
 return '<div class="pricerow"><strong>'+label+'</strong><span>'+(current===null?'Veri yok':current.toFixed(2).replace('.',','))+'</span><b>'+(predicted===null?'Veri yok':predicted.toFixed(2).replace('.',','))+'</b></div>';
 }).join('');
 return '<div style="margin-top:16px;padding-top:12px;border-top:1px solid #ddd"><h3>Yarınki Tahmini Fiyat</h3>'+
 '<div class="pricerow pricehead"><strong>Yakıt</strong><span>Şu an alış (KM/L)</span><span>Tahmini alış (KM/L)</span></div>'+rows+
 '<small>Güncel değişim '+(q.change>0?'+':'')+q.change.toLocaleString('tr-TR',{minimumFractionDigits:2,maximumFractionDigits:2})+
 ' · Tahmini fark: '+(diff>=0?'+':'')+diff.toFixed(3).replace('.',',')+' KM/L. Yaklaşık hesap; gerçek yarınki alış fiyatı değildir.</small></div>';
}
function gasoilPanel(prices){
 const q=gasoilQuote;
 const content=q?'<div style="font-size:30px;font-weight:750">'+q.price.toLocaleString('tr-TR',{minimumFractionDigits:2,maximumFractionDigits:2})+' <small>USD</small></div><div style="font-size:20px;font-weight:700;color:'+(q.change>=0?'#18a45b':'#d34b50')+'">'+(q.change>0?'+':'')+q.change.toLocaleString('tr-TR',{minimumFractionDigits:2,maximumFractionDigits:2})+'</div><small>Investing.com · gecikmeli veri · kontrol: '+new Date(q.checked_at).toLocaleTimeString('tr-TR')+'</small>':'<p class="muted">'+safe(gasoilError)+'</p>';
 return section('⛽ &nbsp; Yakıt Güncel',content+tomorrowFuelEstimate(prices));
}
function render(){
const day=$('day').value,d=archive[day];
if(!d){$('details').innerHTML=section('Geçmiş','<p class="muted">Bu tarih henüz telefona kaydedilmedi. İnternet bağlantısıyla geçmişi indirin.</p>')+bankSection({});return}
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
out+=bankSection(d);
out+=section('⛽ &nbsp; Yakıt Stokları',
stockRow('2','Dizel','diesel',st)+stockRow('3','Dizel+','plus',st)+stockRow('1','Benzin','petrol',st));
out+=section('↗ &nbsp; Güncel Yakıt Fiyatları',
'<div class="pricerow pricehead"><strong>Yakıt</strong><span>Alış Fiyatı (KM/L)</span><span>Güncel Satış Fiyatı (KM/L)</span></div>'+
priceRow('Dizel',p.dizel)+priceRow('Dizel+',p.dizel_plus)+priceRow('Benzin',p.benzin));
out+=gasoilPanel(p);
out+='<div class="bottomtotal"><span>◉ &nbsp; Günlük Satış</span><b>'+fmt(total)+'</b></div>';
$('details').innerHTML=out;

}
async function fetchCurrent(){
if(refreshing||!session||!navigator.onLine)return;
refreshing=true;
try{
const day=$('day').value;
const [rows,currentKasa]=await Promise.all([api('ssoil_snapshots?kind=eq.kasa%3A'+day+'&select=data&limit=1'),day===today()?api('ssoil_snapshots?kind=eq.kasa&select=data&limit=1'):Promise.resolve([])]);
const prices=await api('ssoil_fuel_daily_prices?sale_date=lte.'+day+'&select=sale_date,fuel_type,purchase_price,sale_price&order=sale_date.desc&limit=3000');
const stocks=await api('ssoil_fuel_daily_stock?stock_date=eq.'+day+'&select=fuel_id,closing_liters');
const products=day===today()?await api('ssoil_snapshots?kind=eq.products&select=data&limit=1'):[];
const [banks,bankTransactions,bankOpenings,purchasePrices]=await Promise.all([
api('ssoil_shift_banks?select=id,name,sort_order&deleted_at=is.null&order=sort_order.asc'),
api('ssoil_shift_transactions?select=kind,first_value,second_value,description,amount,bank_id&business_date=eq.'+day+'&deleted_at=is.null'),
api('ssoil_shift_bank_opening?select=bank_id,opening_balance&business_date=eq.'+day),
api('ssoil_fuel_purchase_prices?select=fuel_type,purchase_price,updated_at')
]);
const old=archive[day]||{},next={...old};
if(rows[0]?.data)next.kasa=rows[0].data;
if(day===today()&&currentKasa[0]?.data&&String(currentKasa[0].data.date)===day)next.kasa=currentKasa[0].data;
const priceMap={};for(const x of prices){const type=x.fuel_type;priceMap[type]??={};if(priceMap[type].sale_price==null&&x.sale_price!=null)priceMap[type].sale_price=x.sale_price;if(priceMap[type].purchase_price==null&&x.purchase_price!=null)priceMap[type].purchase_price=x.purchase_price}if(day===today()){for(const x of purchasePrices)(priceMap[x.fuel_type]??={}).purchase_price=x.purchase_price;if(products[0]?.data?.products)for(const p of products[0].data.products){const type=({'1':'benzin','2':'dizel','3':'dizel_plus'})[String(p.id)];if(type&&p.price!=null)(priceMap[type]??={}).sale_price=p.price;}}
next.prices=priceMap;next.banks=banks;next.bankTransactions=bankTransactions;next.bankOpenings=bankOpenings;
if(stocks.length)next.fuelProducts=Object.fromEntries(stocks.map(x=>[String(x.fuel_id),{stock:x.closing_liters}]));
if(day===today()&&products[0]?.data?.products){const items=products[0].data.products;next.fuelProducts=Object.fromEntries(items.filter(x=>['1','2','3'].includes(String(x.id))).map(x=>[String(x.id),x]));}
if(JSON.stringify(old)!==JSON.stringify(next)){archive[day]=next;await putDay(day,next);if($('day').value===day)render();}
}finally{refreshing=false}
}
async function syncAll(){
if(syncing||!session)return;syncing=true;status('Geçmiş veriler güncelleniyor…');
try{
const [snapshots,prices,stocks,banks]=await Promise.all([
allRows('ssoil_snapshots','kind=like.kasa%3A%2A&select=kind,data'),
allRows('ssoil_fuel_daily_prices','select=sale_date,fuel_type,purchase_price,sale_price&order=sale_date.asc'),
allRows('ssoil_fuel_daily_stock','select=stock_date,fuel_id,closing_liters'),
api('ssoil_shift_banks?select=id,name,sort_order&deleted_at=is.null&order=sort_order.asc')
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
try{const [tx,op]=await Promise.all([api('ssoil_shift_transactions?select=kind,first_value,second_value,description,amount,bank_id&business_date=eq.'+day+'&deleted_at=is.null'),api('ssoil_shift_bank_opening?select=bank_id,opening_balance&business_date=eq.'+day)]);next.banks=banks;next.bankTransactions=tx;next.bankOpenings=op;}catch(e){next.banks=banks;}
archive[day]=next;await putDay(day,next)
}
// Today's live tank stock comes from the products snapshot, as in Android S2.
try{const products=await api('ssoil_snapshots?kind=eq.products&select=data&limit=1');const items=products[0]?.data?.products;if(Array.isArray(items)){const day=today(),live=Object.fromEntries(items.filter(x=>['1','2','3'].includes(String(x.id))).map(x=>[String(x.id),x]));archive[day]={...(archive[day]||{}),fuelProducts:live};await putDay(day,archive[day]);}}catch(_){}
await fetchCurrent();
$('syncInfo').textContent='Son güncelleme: '+new Date().toLocaleString('tr-TR')+' · '+days.size+' tarih';
status('Geçmişler telefona kaydedildi.');render()
}catch(e){status('Çevrimdışı: telefona kaydedilmiş geçmişler kullanılabilir.')}finally{syncing=false}
}
$('signIn').onclick=async()=>{status('Giriş yapılıyor…');try{const r=await fetch(URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({email:$('email').value.trim(),password:$('password').value})});if(!r.ok)throw Error('Giriş başarısız');session=await r.json();session.expiry=Date.now()+(session.expires_in||3600)*1000;localStorage.setItem('ssoil_pwa_session',JSON.stringify(session));$('password').value='';view();refreshGasoilQuote();await syncAll();clearInterval(timer);timer=setInterval(()=>{if(!document.hidden&&navigator.onLine)fetchCurrent().catch(()=>{});},5000)}catch(e){status('Giriş başarısız. Bilgileri ve bağlantıyı kontrol edin.')}};

$('day').onchange=render;
$('reload').onclick=async()=>{status('Güncelleniyor…');try{await fetchCurrent();status('Güncellendi')}catch(e){status('Çevrimdışı: kaydedilmiş veriler gösteriliyor.')}};
$('sync').onclick=syncAll;
(async()=>{try{archive=await getAllDays()}catch(e){status('Yerel kayıt alanı açılamadı.')}try{session=JSON.parse(localStorage.getItem('ssoil_pwa_session')||'null')}catch(e){}view();status(navigator.onLine?'Hazır.':'Çevrimdışı: kaydedilmiş veriler gösteriliyor.');if(session){refreshGasoilQuote();setInterval(()=>{if(!document.hidden)refreshGasoilQuote()},60000);syncAll();timer=setInterval(()=>{if(!document.hidden&&navigator.onLine)fetchCurrent().catch(()=>{});},5000)}if('serviceWorker'in navigator)navigator.serviceWorker.getRegistrations().then(rs=>Promise.all(rs.map(r=>r.unregister()))).catch(()=>{})})();

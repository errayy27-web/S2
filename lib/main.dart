import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://rxpsezjtjqfksdxcxmuw.supabase.co');
const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_raRn7YXbKCXuFt2j3i-EXQ_dNbMVXEP');
void main() => runApp(const SsOilClient());

class SsOilClient extends StatelessWidget {
  const SsOilClient({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'SS OIL Client', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xfff5f5f5),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffbd2026)),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xffbd2026), foregroundColor: Colors.white)),
    home: const KasaClient());
}

class KasaClient extends StatefulWidget {
  const KasaClient({super.key});
  @override State<KasaClient> createState() => _KasaClientState();
}

class _KasaClientState extends State<KasaClient> {
  static const storage = FlutterSecureStorage();
  final email = TextEditingController();
  final password = TextEditingController();
  String? accessToken;
  String? refreshToken;
  DateTime? expiresAt;
  Timer? sessionTimer;
  Timer? historyTimer;
  bool historySyncing=false;
  String? lastHistorySync;
  Map<String,dynamic> localArchive={};
  bool offline=false;
  bool cacheReady=false;
  Future<void>? refreshSessionInFlight;
  DateTime selected = DateTime.now();
  Map<String, dynamic> kasa = {};
  Map<String, dynamic> prices = {};
  Map<String, dynamic> fuelProducts = {};
  String? error;
  bool busy = false;
  bool get signedIn => accessToken != null;
  String get date => '${selected.year.toString().padLeft(4,'0')}-${selected.month.toString().padLeft(2,'0')}-${selected.day.toString().padLeft(2,'0')}';

  @override void initState() { super.initState(); _restore(); }
  @override void dispose() {sessionTimer?.cancel();historyTimer?.cancel(); email.dispose(); password.dispose(); super.dispose(); }
  Future<void> _restore() async {
    final p=await SharedPreferences.getInstance();
    try{localArchive=Map<String,dynamic>.from(jsonDecode(p.getString('ssoil_s2_archive_v1')??'{}'));}catch(_){}
    cacheReady=true;
    _showCached();
    final token=await storage.read(key:'ssoil_client_access');
    refreshToken=await storage.read(key:'ssoil_client_refresh');
    final expiry=await storage.read(key:'ssoil_client_expiry');
    expiresAt=expiry==null?null:DateTime.tryParse(expiry);
    if(!mounted||token==null)return;
    setState(()=>accessToken=token);
    _startSessionTimer();
    if(refreshToken!=null&&(expiresAt==null||DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes:2))))){
      await _refreshSession();
    }
    await refresh();
    _startHistorySync();
  }
  void _showCached(){
    final entry=localArchive[date];
    if(entry is! Map||!mounted)return;
    setState((){
      kasa=Map<String,dynamic>.from((entry['kasa'] as Map?)??{});
      prices=Map<String,dynamic>.from((entry['prices'] as Map?)??{});
      fuelProducts=Map<String,dynamic>.from((entry['fuelProducts'] as Map?)??{});
    });
  }
  Future<void> _cacheDay()async{
    localArchive[date]={'kasa':kasa,'prices':prices,'fuelProducts':fuelProducts};
    final p=await SharedPreferences.getInstance();
    await p.setString('ssoil_s2_archive_v1',jsonEncode(localArchive));
  }
  void _startHistorySync(){
    historyTimer?.cancel();
    syncAllHistory();
    historyTimer=Timer.periodic(const Duration(minutes:1),(_)=>syncAllHistory());
  }
  Future<List<dynamic>> _allRows(String table,String query)async{
    final out=<dynamic>[];
    for(var offset=0;;offset+=500){
      final part=await _get('$table?$query&limit=500&offset=$offset');
      out.addAll(part);
      if(part.length<500)break;
    }
    return out;
  }
  Future<void> syncAllHistory()async{
    if(historySyncing||!signedIn)return;
    historySyncing=true;
    try{
      // Fetch the complete remote archive, not just the date currently on screen.
      final snapshots=await _allRows('ssoil_snapshots','kind=like.kasa%3A%2A&select=kind,data');
      final pricesRows=await _allRows('ssoil_fuel_daily_prices','select=sale_date,fuel_type,purchase_price,sale_price&order=sale_date.asc');
      final stockRows=await _allRows('ssoil_fuel_daily_stock','select=stock_date,fuel_id,closing_liters');
      final dates=<String>{};
      final snapshotsByDate=<String,Map<String,dynamic>>{};
      for(final raw in snapshots){
        if(raw is! Map)continue;
        final kind='${raw['kind']}';
        if(!kind.startsWith('kasa:'))continue;
        final d=kind.substring(5);
        if(!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d))continue;
        if(raw['data'] is Map){dates.add(d);snapshotsByDate[d]=Map<String,dynamic>.from(raw['data'] as Map);}
      }
      for(final raw in pricesRows){if(raw is Map&&raw['sale_date']!=null)dates.add('${raw['sale_date']}');}
      for(final raw in stockRows){if(raw is Map&&raw['stock_date']!=null)dates.add('${raw['stock_date']}');}
      // Preserve locally saved days if their remote record is temporarily absent.
      dates.addAll(localArchive.keys);
      final sortedDates=dates.toList()..sort();
      final latestPrice=<String,Map<String,dynamic>>{};
      final pricesByDay=<String,Map<String,dynamic>>{};
      final orderedPrices=pricesRows.whereType<Map>().toList()..sort((a,b)=>'${a['sale_date']}'.compareTo('${b['sale_date']}'));
      var priceIndex=0;
      for(final d in sortedDates){
        while(priceIndex<orderedPrices.length&&'${orderedPrices[priceIndex]['sale_date']}'.compareTo(d)<=0){
          final row=orderedPrices[priceIndex++];
          final type='${row['fuel_type']}';
          final prev=latestPrice[type]??<String,dynamic>{};
          if(row['sale_price']!=null)prev['sale_price']=row['sale_price'];
          if(row['purchase_price']!=null)prev['purchase_price']=row['purchase_price'];
          latestPrice[type]=prev;
        }
        pricesByDay[d]={for(final type in ['benzin','dizel','dizel_plus'])type:Map<String,dynamic>.from(latestPrice[type]??{})};
      }
      final stocksByDay=<String,Map<String,dynamic>>{};
      for(final raw in stockRows){
        if(raw is! Map||raw['closing_liters']==null)continue;
        final d='${raw['stock_date']}',id='${raw['fuel_id']}';
        if(!['1','2','3'].contains(id))continue;
        stocksByDay.putIfAbsent(d,()=>{})[id]={'stock':raw['closing_liters']};
      }
      final updated=<String,dynamic>{...localArchive};
      for(final d in sortedDates){
        final old=updated[d] is Map?Map<String,dynamic>.from(updated[d] as Map):<String,dynamic>{};
        if(snapshotsByDate.containsKey(d))old['kasa']=snapshotsByDate[d];
        if(pricesByDay.containsKey(d))old['prices']=pricesByDay[d];
        if(stocksByDay.containsKey(d))old['fuelProducts']=stocksByDay[d];
        updated[d]=old;
      }
      localArchive=updated;
      final p=await SharedPreferences.getInstance();
      await p.setString('ssoil_s2_archive_v1',jsonEncode(localArchive));
      lastHistorySync=DateTime.now().toIso8601String();
      if(mounted&&!busy)_showCached();
    }catch(_){
      // Keep all previously downloaded days unchanged on connection failures.
    }finally{historySyncing=false;}
  }
  Future<void> _saveSession(Map<String,dynamic> data)async{
    final token=data['access_token'] as String?;
    if(token==null||token.isEmpty)throw Exception('Oturum anahtarı alınamadı');
    accessToken=token;
    refreshToken=(data['refresh_token'] as String?)??refreshToken;
    expiresAt=DateTime.now().add(Duration(seconds:(data['expires_in'] as num?)?.toInt()??3600));
    await storage.write(key:'ssoil_client_access',value:accessToken);
    if(refreshToken!=null)await storage.write(key:'ssoil_client_refresh',value:refreshToken);
    await storage.write(key:'ssoil_client_expiry',value:expiresAt!.toIso8601String());
    _startSessionTimer();
    if(mounted)setState((){});
  }
  void _startSessionTimer(){
    sessionTimer?.cancel();
    sessionTimer=Timer.periodic(const Duration(minutes:1),(_){
      if(signedIn&&refreshToken!=null&&
       (expiresAt==null||DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes:5))))){
        _refreshSession();
      }
    });
  }
  Future<void> _refreshSession()async{
    if(refreshSessionInFlight!=null)return refreshSessionInFlight;
    final task=_doRefreshSession();
    refreshSessionInFlight=task;
    try{await task;}finally{refreshSessionInFlight=null;}
  }
  Future<void> _doRefreshSession()async{
    final token=refreshToken;
    if(token==null||token.isEmpty)throw Exception('Oturum yenileme anahtarı bulunamadı. Bir kez yeniden giriş gerekiyor.');
    final response=await http.post(Uri.parse('$_url/auth/v1/token?grant_type=refresh_token'),
      headers:{'apikey':_anonKey,'Content-Type':'application/json'},
      body:jsonEncode({'refresh_token':token})).timeout(const Duration(seconds:15));
    if(response.statusCode!=200)throw Exception('Oturum yenilenemedi (${response.statusCode})');
    await _saveSession(Map<String,dynamic>.from(jsonDecode(response.body) as Map));
  }
  Map<String,String> get headers => {
    'apikey': _anonKey, 'Authorization': 'Bearer ${accessToken ?? _anonKey}',
    'Accept': 'application/json', 'Content-Type': 'application/json'
  };
  Future<void> login() async {
    if (_anonKey.isEmpty) {setState(() => error = 'SUPABASE_ANON_KEY derleme ayarı eksik.');return;}
    setState(() {busy = true; error = null;});
    try {
      final response = await http.post(Uri.parse('$_url/auth/v1/token?grant_type=password'),
        headers: {'apikey': _anonKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.text.trim(), 'password': password.text})).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Giriş başarısız (${response.statusCode})');
      final data = jsonDecode(response.body) as Map<String,dynamic>;
      final token = data['access_token'] as String?;
      if (token == null) throw Exception('Oturum alınamadı');
      await _saveSession(data);
      await refresh();
      _startHistorySync();
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally {if (mounted) setState(() => busy = false);}
  }
  Future<List<dynamic>> _get(String path) async {
    if(refreshToken!=null&&expiresAt!=null&&DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes:2))))await _refreshSession();
    var response = await http.get(Uri.parse('$_url/rest/v1/$path'), headers: headers).timeout(const Duration(seconds: 15));
    if(response.statusCode==401&&refreshToken!=null){
      await _refreshSession();
      response=await http.get(Uri.parse('$_url/rest/v1/$path'),headers:headers).timeout(const Duration(seconds:15));
    }
    if (response.statusCode == 401 || response.statusCode == 403) throw Exception('Oturum doğrulanamadı veya erişim izni yok.');
    if (response.statusCode != 200) throw Exception('Veri alınamadı (${response.statusCode})');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw Exception('Beklenmeyen sunucu yanıtı');
    return decoded;
  }
  Future<void> refresh() async {
    if (!signedIn) return;
    _showCached();
    setState(() {busy = true; error = null;});
    try {
      // Prefer date-specific archive; the generic kasa snapshot is only for the matching date.
      final archived = await _get('ssoil_snapshots?kind=eq.kasa%3A$date&select=data&limit=1');
      Map<String,dynamic> value = {};
      if (archived.isNotEmpty && archived.first['data'] is Map) {
        value = Map<String,dynamic>.from(archived.first['data'] as Map);
      } else {
        final current = await _get('ssoil_snapshots?kind=eq.kasa&select=data&limit=1');
        if (current.isNotEmpty && current.first['data'] is Map) {
          final candidate = Map<String,dynamic>.from(current.first['data'] as Map);
          if ('${candidate['date']}' == date) value = candidate;
        }
      }
      // S2 fixed fuel mapping: Benzin=1, Dizel=2, Dizel+=3.
      final fuel = await _get('ssoil_fuel_daily_prices?sale_date=lte.$date&select=sale_date,fuel_type,purchase_price,sale_price&order=sale_date.desc&limit=3000');
      final nextPrices = <String,dynamic>{};
      for (final type in ['benzin','dizel','dizel_plus']) {nextPrices[type] = <String,dynamic>{};}
      for (final raw in fuel) {
        if (raw is! Map) continue;
        final type = '${raw['fuel_type']}';
        if (!nextPrices.containsKey(type)) continue;
        final target = nextPrices[type] as Map<String,dynamic>;
        if (target['sale_price'] == null && raw['sale_price'] != null) target['sale_price'] = raw['sale_price'];
        if (target['purchase_price'] == null && raw['purchase_price'] != null) target['purchase_price'] = raw['purchase_price'];
      }
      // Current purchase price is a fallback only for today; never use it for historical dates.
      if (date == _today()) {
        final currentPurchases = await _get('ssoil_fuel_purchase_prices?select=fuel_type,purchase_price');
        for (final raw in currentPurchases) {
          if (raw is! Map) continue;
          final type = '${raw['fuel_type']}';
          if (nextPrices[type] is Map && (nextPrices[type] as Map)['purchase_price'] == null) {
            (nextPrices[type] as Map)['purchase_price'] = raw['purchase_price'];
          }
        }
      }
      // Tank data are sourced from the existing products snapshot, never invented.
      final productsSnapshot = await _get('ssoil_snapshots?kind=eq.products&select=data&limit=1');
      final nextProducts = <String,dynamic>{};
      if (productsSnapshot.isNotEmpty && productsSnapshot.first['data'] is Map) {
        final items = (productsSnapshot.first['data'] as Map)['products'];
        if (items is List) {
          for (final raw in items) {
            if (raw is Map && ['1','2','3'].contains('${raw['id']}')) nextProducts['${raw['id']}'] = raw;
          }
        }
      }
      // Daily stock archive is populated by the PC importer once the SmP_S source is connected.
      // Until then, only the confirmed 30 Aug opening stocks and today's live ART stock exist.
      final stockRows = await _get('ssoil_fuel_daily_stock?stock_date=eq.$date&select=fuel_id,closing_liters');
      final archivedProducts = <String,dynamic>{};
      for (final raw in stockRows) {
        if (raw is! Map || raw['closing_liters'] == null) continue;
        final id = '${raw['fuel_id']}';
        if (['1','2','3'].contains(id)) archivedProducts[id] = {'stock': raw['closing_liters']};
      }
      if (!mounted) return;
      setState(() {kasa = value; prices = nextPrices; fuelProducts = date == _today() ? nextProducts : archivedProducts;offline=false;});
      await _cacheDay();
    } catch (e) {if (mounted) setState(() {error = null;offline=true;});}
    finally {if (mounted) setState(() => busy = false);}
  }
  String _today() {final d=DateTime.now();return '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';}
  Future<void> logout() async {
    sessionTimer?.cancel();historyTimer?.cancel();
    await storage.delete(key: 'ssoil_client_access');
    await storage.delete(key: 'ssoil_client_refresh');
    await storage.delete(key: 'ssoil_client_expiry');
    refreshToken=null;expiresAt=null;
    if (mounted) setState(() {accessToken = null; kasa = {}; prices = {}; error = null;});
  }
  double? n(dynamic value) => value == null ? null : (value is num ? value.toDouble() : double.tryParse('$value'));
  String money(dynamic value, {String unit = 'KM'}) {
    final v = n(value);
    return v == null ? 'Veri yok' : '${v.toStringAsFixed(2)} $unit';
  }
  Widget line(String label, dynamic value, {String unit = 'KM'}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
      Text(money(value, unit: unit), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xffbd2026))) ]));
  Widget group(String title, IconData icon, List<Widget> children) => Card(
    color: Colors.white, margin: const EdgeInsets.only(bottom: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21), side: const BorderSide(color: Color(0xffeeeeee), width: 1)),
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: const Color(0xffbd2026)), const SizedBox(width: 9), Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))]),
      const SizedBox(height: 12), ...children])));

  Widget stockBar(String id,String name,Color color){
    final product=fuelProducts[id];
    final stock=product is Map ? n(product['stock']) : null;
    final stocks=['1','2','3'].map((key) {final p=fuelProducts[key];return p is Map ? (n(p['stock'])??0.0) : 0.0;}).toList();
    final maxStock=stocks.reduce((a,b)=>a>b?a:b);
    final ratio=stock==null||maxStock<=0?0.0:(stock/maxStock).clamp(0.0,1.0);
    return Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Row(children:[
      Container(width:85,padding:const EdgeInsets.symmetric(vertical:8),decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(6)),child:Text(name,textAlign:TextAlign.center,style:TextStyle(color:name=='Dizel'?Colors.black:Colors.white,fontWeight:FontWeight.bold))),
      const SizedBox(width:12),
      Expanded(child:TweenAnimationBuilder<double>(tween:Tween(begin:0.0,end:ratio),duration:const Duration(milliseconds:800),builder:(context,v,_)=>ClipRRect(borderRadius:BorderRadius.circular(5),child:LinearProgressIndicator(value:v,minHeight:15,backgroundColor:const Color(0xffeeeeee),color:color)))),
      const SizedBox(width:12),
      SizedBox(width:73,child:Text(stock==null?'Veri yok':'${stock.toStringAsFixed(0)} L',textAlign:TextAlign.right,style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)))
    ]));
  }
  Widget priceTable()=>Column(children:[
    Container(padding:const EdgeInsets.symmetric(vertical:10),decoration:BoxDecoration(color:const Color(0xffeeeeee),borderRadius:BorderRadius.circular(6)),child:const Row(children:[
      Expanded(flex:2,child:Text('Yakıt',style:TextStyle(fontWeight:FontWeight.bold))),
      Expanded(flex:3,child:Text('Alış Fiyatı (KM/L)',textAlign:TextAlign.center,style:TextStyle(fontSize:12,fontWeight:FontWeight.bold))),
      Expanded(flex:3,child:Text('Güncel Satış Fiyatı (KM/L)',textAlign:TextAlign.center,style:TextStyle(fontSize:12,fontWeight:FontWeight.bold)))
    ])),
    for(final item in const [('dizel','Dizel'),('dizel_plus','Dizel+'),('benzin','Benzin')])...[
      Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Row(children:[
        Expanded(flex:2,child:Text(item.$2,style:const TextStyle(fontWeight:FontWeight.bold))),
        Expanded(flex:3,child:Text(money((prices[item.$1] as Map?)?['purchase_price'],unit:'KM/L'),textAlign:TextAlign.center)),
        Expanded(flex:3,child:Text(money((prices[item.$1] as Map?)?['sale_price'],unit:'KM/L'),textAlign:TextAlign.center,style:const TextStyle(color:Color(0xffd2081b),fontWeight:FontWeight.bold)))
      ])),
      if(item.$1!='benzin')const Divider(height:1)
    ]
  ]);
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(toolbarHeight: 70, backgroundColor: const Color(0xffd2081b), leading: IconButton(icon: const Icon(Icons.menu,size:30),onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SS OIL Client • Kasa')))),title: Row(children: [Container(width:48,height:48,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(10)),child:Image.asset('assets/ss_oil_logo.jpg',fit:BoxFit.contain,errorBuilder: (_,__,___)=>const Icon(Icons.local_gas_station,color:Color(0xffd2081b)))),const SizedBox(width:12),const Expanded(child:Text('SS OIL • Kasa',style:TextStyle(fontWeight:FontWeight.w800)))]),actions: [IconButton(tooltip:'Ayarlar',onPressed:signedIn?logout:null,icon:const Icon(Icons.settings_outlined,size:30))]),
    body: !signedIn ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(22), children: [
      Image.asset('assets/ss_oil_logo.jpg',height:90,width:90,fit:BoxFit.contain), const SizedBox(height: 12),
      const Text('SS OIL Client', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 24), TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta', border: OutlineInputBorder())),
      const SizedBox(height: 12), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre', border: OutlineInputBorder())),
      const SizedBox(height: 16), FilledButton(onPressed: busy ? null : login, child: const Text('Giriş Yap')),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red)))
    ]))) : RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [Expanded(child: Text('Tarih: $date', style: const TextStyle(fontWeight: FontWeight.bold))),
        IconButton(tooltip: 'Tarih seç', icon: const Icon(Icons.calendar_month), onPressed: () async {
          final chosen = await showDatePicker(context: context, initialDate: selected, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (chosen != null) {setState(() {selected = chosen;kasa={};prices={};fuelProducts={};});_showCached();await refresh();}
        }), FilledButton.icon(onPressed: busy ? null : refresh, icon: const Icon(Icons.refresh), label: const Text('Güncelle'))]),
      if (busy) const LinearProgressIndicator(),
      if(offline)const Padding(padding:EdgeInsets.all(8),child:Text('Çevrimdışı: telefonda saklanan kayıtlar gösteriliyor.',style:TextStyle(color:Colors.orange))),
      if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: const TextStyle(color: Colors.red))),
      if (kasa.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(offline ? 'Bu tarih telefona henüz kaydedilmemiş. İnternete bağlanınca bu tarihi bir kez açın.' : 'Seçilen tarih için Kasa kaydı bulunamadı.')),
      group('Günlük Satış', Icons.payments, [
        line('Nakit Yakıt Market', n(kasa['cash_market']) == null || n(kasa['cash_fuel']) == null ? null : n(kasa['cash_market'])! + n(kasa['cash_fuel'])!),
        line('Nakit Dopuna (MTEL + AERO)', n(kasa['mtel_dopuna']) == null || n(kasa['aero_dopuna']) == null ? null : n(kasa['mtel_dopuna'])! + n(kasa['aero_dopuna'])!),
        line('Nakit (Dopuna dahil)', kasa['cash']), line('Kredi Kartı', kasa['card']),
        const Divider(height: 22), line('Genel Toplam', n(kasa['cash']) == null || n(kasa['card']) == null ? null : n(kasa['cash'])! + n(kasa['card'])!),
      ]),
      group('Satış Grupları', Icons.storefront, [line('Yakıt', kasa['fuel_sales']), line('Market', kasa['market_sales']), line('MTEL Dopuna', kasa['mtel_dopuna']), line('AERO Dopuna', kasa['aero_dopuna'])]),
      group('Yakıt Stokları', Icons.local_gas_station, [
        stockBar('2','Dizel',const Color(0xffffd35d)),stockBar('3','Dizel+',const Color(0xffd2081b)),stockBar('1','Benzin',const Color(0xff20b75b)),if(fuelProducts.isEmpty) const Text('Bu tarih için yakıt stok kaydı yok.',style:TextStyle(color:Colors.black54,fontSize:12)),
      ]),
      group('Güncel Yakıt Fiyatları', Icons.trending_up, [priceTable()]),
      Container(margin:const EdgeInsets.only(bottom:24),padding:const EdgeInsets.symmetric(horizontal:17,vertical:12),decoration:BoxDecoration(color:const Color(0xffd2081b),borderRadius:BorderRadius.circular(20)),child:Row(children:[const Icon(Icons.monetization_on_outlined,color:Colors.white,size:28),const SizedBox(width:12),const Expanded(child:Text('Günlük Satış',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.bold))),Text(money(n(kasa['cash'])==null||n(kasa['card'])==null?null:n(kasa['cash'])!+n(kasa['card'])!),style:const TextStyle(color:Colors.white,fontSize:21,fontWeight:FontWeight.w900))])),

    ])));
}
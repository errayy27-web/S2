import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://rxpsezjtjqfksdxcxmuw.supabase.co');
const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
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
  DateTime selected = DateTime.now();
  Map<String, dynamic> kasa = {};
  Map<String, dynamic> prices = {};
  String? error;
  bool busy = false;
  bool get signedIn => accessToken != null;
  String get date => '${selected.year.toString().padLeft(4,'0')}-${selected.month.toString().padLeft(2,'0')}-${selected.day.toString().padLeft(2,'0')}';

  @override void initState() { super.initState(); _restore(); }
  @override void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  Future<void> _restore() async {
    final token = await storage.read(key: 'ssoil_client_access');
    if (!mounted || token == null) return;
    setState(() => accessToken = token);
    await refresh();
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
      await storage.write(key: 'ssoil_client_access', value: token);
      if (mounted) setState(() => accessToken = token);
      await refresh();
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally {if (mounted) setState(() => busy = false);}
  }
  Future<List<dynamic>> _get(String path) async {
    final response = await http.get(Uri.parse('$_url/rest/v1/$path'), headers: headers).timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 || response.statusCode == 403) throw Exception('Oturum süresi doldu veya erişim izni yok. Tekrar giriş yapın.');
    if (response.statusCode != 200) throw Exception('Veri alınamadı (${response.statusCode})');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw Exception('Beklenmeyen sunucu yanıtı');
    return decoded;
  }
  Future<void> refresh() async {
    if (!signedIn) return;
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
      final fuel = await _get('ssoil_fuel_daily_prices?sale_date=eq.$date&select=fuel_type,purchase_price,sale_price');
      final nextPrices = <String,dynamic>{};
      for (final item in fuel) {if (item is Map) nextPrices['${item['fuel_type']}'] = item;}
      if (!mounted) return;
      setState(() {kasa = value; prices = nextPrices;});
    } catch (e) {if (mounted) setState(() => error = '$e');}
    finally {if (mounted) setState(() => busy = false);}
  }
  Future<void> logout() async {
    await storage.delete(key: 'ssoil_client_access');
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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xffbd2026), width: 1.2)),
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: const Color(0xffbd2026)), const SizedBox(width: 9), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))]),
      const Divider(height: 20), ...children])));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SS OIL • Kasa'), actions: signedIn ? [IconButton(tooltip: 'Çıkış', onPressed: logout, icon: const Icon(Icons.logout))] : null),
    body: !signedIn ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(22), children: [
      const Icon(Icons.local_gas_station, size: 66, color: Color(0xffbd2026)), const SizedBox(height: 12),
      const Text('SS OIL Client', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 24), TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta', border: OutlineInputBorder())),
      const SizedBox(height: 12), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre', border: OutlineInputBorder())),
      const SizedBox(height: 16), FilledButton(onPressed: busy ? null : login, child: const Text('Giriş Yap')),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red)))
    ]))) : RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [Expanded(child: Text('Tarih: $date', style: const TextStyle(fontWeight: FontWeight.bold))),
        IconButton(tooltip: 'Tarih seç', icon: const Icon(Icons.calendar_month), onPressed: () async {
          final chosen = await showDatePicker(context: context, initialDate: selected, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (chosen != null) {setState(() => selected = chosen); await refresh();}
        }), FilledButton.icon(onPressed: busy ? null : refresh, icon: const Icon(Icons.refresh), label: const Text('Güncelle'))]),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: const TextStyle(color: Colors.red))),
      if (kasa.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Seçilen tarih için Kasa kaydı bulunamadı.')),
      group('Günlük Satış', Icons.payments, [
        line('Nakit Market', kasa['cash_market']), line('Nakit Yakıt', kasa['cash_fuel']),
        line('Nakit Dopuna (MTEL + AERO)', n(kasa['mtel_dopuna']) == null || n(kasa['aero_dopuna']) == null ? null : n(kasa['mtel_dopuna'])! + n(kasa['aero_dopuna'])!),
        line('Nakit (Dopuna dahil)', kasa['cash']), line('Kredi Kartı', kasa['card']),
        line('Genel Toplam', n(kasa['cash']) == null || n(kasa['card']) == null ? null : n(kasa['cash'])! + n(kasa['card'])!),
      ]),
      group('Satış Grupları', Icons.storefront, [line('Yakıt', kasa['fuel_sales']), line('Market', kasa['market_sales']), line('MTEL Dopuna', kasa['mtel_dopuna']), line('AERO Dopuna', kasa['aero_dopuna'])]),
      group('Yakıt Stokları', Icons.local_gas_station, [
        const Text('Stok verisi henüz Supabase Kasa arşivinde bulunmuyor. Mevcut olmayan değer gösterilmez.', style: TextStyle(color: Colors.black54)),
      ]),
      group('Güncel Yakıt Fiyatları', Icons.price_change, [
        for (final entry in const [('dizel','Dizel'),('dizel_plus','Dizel+'),('benzin','Benzin')]) ...[
          line('${entry.$2} Alış', (prices[entry.$1] as Map?)?['purchase_price'], unit: 'KM/L'),
          line('${entry.$2} Satış', (prices[entry.$1] as Map?)?['sale_price'], unit: 'KM/L'),
        ]
      ]),
    ])));
}
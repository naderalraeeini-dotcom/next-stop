import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() => runApp(const NextStopApp());
const blue = Color(0xFF1769AA);
const orange = Color(0xFFFF8A24);

class NextStopApp extends StatelessWidget {
  const NextStopApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Next Stop',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: blue), scaffoldBackgroundColor: const Color(0xFFFFFFFF), useMaterial3: true, appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Color(0xFF17212F)), cardTheme: CardThemeData(color: Colors.white, elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)))),
    home: const RoutesPage(),
  );
}

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});
  @override
  State<RoutesPage> createState() => _RoutesPageState();
}
class _RoutesPageState extends State<RoutesPage> {
  List<Map<String, dynamic>> routes = [];
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('next_stop_routes_v1');
    if (raw != null) {
      try { routes = (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e)).toList(); } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('next_stop_routes_v1', jsonEncode(routes));
  }
  Future<void> addRoute() async {
    final name = TextEditingController();
    final warehouse = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New route'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Route name', hintText: 'e.g. Route North')),
        const SizedBox(height: 12),
        TextField(controller: warehouse, decoration: const InputDecoration(labelText: 'Warehouse / start and return address')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create'))],
    ));
    if (ok == true && name.text.trim().isNotEmpty) {
      setState(() => routes.add({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'name': name.text.trim(), 'warehouse': warehouse.text.trim(), 'endAddress': warehouse.text.trim(), 'stops': <dynamic>[], 'dailyStopIds': <String>[], 'tripDay': DateTime.now().toIso8601String().substring(0,10), 'tripStarted': false, 'created': DateTime.now().toIso8601String()}));
      await save();
    }
  }
  Future<void> editRoute(Map<String,dynamic> r) async {
    final name = TextEditingController(text: r['name']?.toString() ?? '');
    final warehouse = TextEditingController(text: r['warehouse']?.toString() ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Edit route'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Route name')),
      TextField(controller: warehouse, decoration: const InputDecoration(labelText: 'Warehouse / return address')),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Save'))]));
    if (ok == true && mounted) { setState(() { r['name']=name.text.trim(); r['warehouse']=warehouse.text.trim(); }); await save(); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Next Stop', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.4, color: blue)), actions: [IconButton(tooltip: 'Scan route QR code', onPressed: scanRoute, icon: const Icon(Icons.qr_code_scanner)), IconButton(tooltip: 'Add route', onPressed: addRoute, icon: const Icon(Icons.add_circle_outline))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: addRoute, backgroundColor: orange, foregroundColor: Colors.white, icon: const Icon(Icons.add), label: const Text('New route')),
    body: loading ? const Center(child: CircularProgressIndicator()) : routes.isEmpty
      ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.route, size: 68, color: blue), const SizedBox(height: 16), const Text('Plan your delivery day', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('Create a route, add its stops, and keep your route data saved on this phone.', textAlign: TextAlign.center), const SizedBox(height: 18), FilledButton.icon(onPressed: addRoute, icon: const Icon(Icons.add), label: const Text('Create first route'))])))
      : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), itemCount: routes.length, itemBuilder: (ctx,i) {
        final r = routes[i]; final stops = (r['stops'] as List? ?? []);
        return Card(margin: const EdgeInsets.only(bottom: 12), child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: CircleAvatar(backgroundColor: blue.withOpacity(.1), foregroundColor: blue, child: const Icon(Icons.route)),
          title: Text(r['name']?.toString() ?? 'Route', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(stops.length.toString() + ' stops\n' + ((r['warehouse'] ?? '').toString().isEmpty ? 'Warehouse address not set' : r['warehouse'].toString())),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(onSelected: (v) { if(v=='edit') editRoute(r); if(v=='delete') deleteRoute(r); if(v=='share') shareRoute(r); }, itemBuilder: (_) => const [PopupMenuItem(value:'edit', child: Text('Edit route')), PopupMenuItem(value:'share', child: Text('Share route / QR code')), PopupMenuItem(value:'delete', child: Text('Delete route'))]),
          onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => StopsPage(route: r, onChanged: save))); if(mounted) setState(() {}); },
        ));
      }),
  );

  Future<void> shareRoute(Map<String,dynamic> route) async {
    final jsonPayload = jsonEncode({'app':'next-stop','version':1,'route':route});
    // Compress complete routes before encoding them for QR; large routes often shrink substantially.
    final payload = 'NSZ1:' + base64Url.encode(gzip.encode(utf8.encode(jsonPayload)));
    if (payload.length > 2500) {
      if (mounted) showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Route too large'),content:const Text('This route is still too large for a single QR code, even after compression. Use a smaller route for QR sharing; full-route file export/import is the reliable next step.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('OK'))]));
      return;
    }
    if (!mounted) return;
    showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text('Share route: ${route['name']}'),content:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Ask the other person to open Next Stop and scan this code.'),const SizedBox(height:12),QrImageView(data:payload,size:245),const SizedBox(height:8),const Text('The receiving phone will ask for confirmation.',textAlign:TextAlign.center)]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))]));
  }
  Future<void> scanRoute() async {
    final scanned = await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScanRoutePage()));
    if (scanned == null || !mounted) return;
    try {
      final decodedText = scanned.startsWith('NSZ1:') ? utf8.decode(gzip.decode(base64Url.decode(scanned.substring(5)))) : scanned;
      final data = jsonDecode(decodedText) as Map<String,dynamic>;
      if (data['app'] != 'next-stop' || data['route'] is! Map) throw const FormatException();
      final incoming = Map<String,dynamic>.from(data['route'] as Map);
      final incomingStops = (incoming['stops'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e)).toList();
      incoming['id'] = DateTime.now().microsecondsSinceEpoch.toString();
      incoming['name'] = '${incoming['name'] ?? 'Imported route'} (imported)';
      incoming['stops'] = incomingStops;
      incoming['created'] = DateTime.now().toIso8601String();
      incoming['dailyStopIds'] = <String>[];
      incoming['tripDay'] = DateTime.now().toIso8601String().substring(0,10);
      incoming['tripStarted'] = false;
      final yes = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Import route?'),content:Text('Add "${incoming['name']}" with ${incomingStops.length} stops? Existing routes will not change.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm import'))]));
      if (yes == true && mounted) { setState(()=>routes.add(incoming)); await save(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Route imported successfully'))); }
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('This is not a valid Next Stop route QR code.'))); }
  }

  Future<void> deleteRoute(Map<String,dynamic> r) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(title: const Text('Delete route?'), content: Text('Delete "' + r['name'].toString() + '" and its stops?'), actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('Cancel')), FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:const Text('Delete'))]));
    if (yes == true) { setState(()=>routes.remove(r)); await save(); }
  }
}


class ScanRoutePage extends StatefulWidget {
  const ScanRoutePage({super.key});
  @override
  State<ScanRoutePage> createState()=>_ScanRoutePageState();
}
class _ScanRoutePageState extends State<ScanRoutePage> {
  bool handled = false;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Scan route QR code')),
    body:Column(children:[
      const Padding(padding:EdgeInsets.all(18),child:Text('Point the camera at a Next Stop route QR code. Android will request camera permission if needed.',textAlign:TextAlign.center)),
      Expanded(child:Padding(padding:const EdgeInsets.all(16),child:ClipRRect(borderRadius:BorderRadius.circular(18),child:MobileScanner(onDetect:(capture){
        if(handled)return;
        final value=capture.barcodes.isEmpty?null:capture.barcodes.first.rawValue;
        if(value!=null&&value.isNotEmpty){handled=true;Navigator.pop(context,value);}
      })))),
    ]),
  );
}

class StopsPage extends StatefulWidget {
  final Map<String,dynamic> route;
  final Future<void> Function() onChanged;
  const StopsPage({super.key, required this.route, required this.onChanged});
  @override
  State<StopsPage> createState()=>_StopsPageState();
}
class _StopsPageState extends State<StopsPage> {
  List<Map<String,dynamic>> get stops => (widget.route['stops'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e)).toList();
  Future<void> persist(List<Map<String,dynamic>> items) async { widget.route['stops']=items; await widget.onChanged(); if(mounted)setState((){}); }
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>checkNewDay());}
  Future<void> checkNewDay() async {
    final now=DateTime.now().toIso8601String().substring(0,10);
    if(widget.route['tripDay']!=null && widget.route['tripDay'].toString()!=now){final list=stops;for(final s in list){s['done']=false;}widget.route['stops']=list;widget.route['tripDay']=now;widget.route['tripStarted']=false;widget.route['dailyStopIds']=list.where((s)=>s['enabled']!=false).map((s)=>s['id'].toString()).toList();await widget.onChanged();if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('New day: unfinished stops have been reset.')));}}
  }
  Future<void> addStop([Map<String,dynamic>? existing]) async {
    final isEdit = existing != null;
    final fields = <String,TextEditingController>{
      'shop': TextEditingController(text: existing?['shop']?.toString() ?? ''),
      'street': TextEditingController(text: existing?['street']?.toString() ?? ''),
      'number': TextEditingController(text: existing?['number']?.toString() ?? ''),
      'apartment': TextEditingController(text: existing?['apartment']?.toString() ?? ''),
      'postal': TextEditingController(text: existing?['postal']?.toString() ?? ''),
      'city': TextEditingController(text: existing?['city']?.toString() ?? ''),
      'country': TextEditingController(text: existing?['country']?.toString() ?? 'Netherlands'),
      'packages': TextEditingController(text: (existing?['packages'] ?? 1).toString()),
      'serial': TextEditingController(text: existing?['serial']?.toString() ?? ''),
      'notes': TextEditingController(text: existing?['notes']?.toString() ?? ''),
      'hours': TextEditingController(text: existing?['hours']?.toString() ?? ''),
      'closedDates': TextEditingController(text: existing?['closedDates']?.toString() ?? ''),
      'smartNote': TextEditingController(text: existing?['smartNote']?.toString() ?? ''),
      'holidays': TextEditingController(text: existing?['holidays']?.toString() ?? ''),
    };
    String type = existing?['type']?.toString() ?? 'Fixed';
    bool enabled = existing?['enabled'] != false;
    final ok = await showDialog<bool>(context: context, builder: (ctx)=> StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title: Text(isEdit?'Edit stop':'Add stop'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final entry in fields.entries.where((e)=>e.key!='holidays')) Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: entry.value, keyboardType: entry.key=='packages'?TextInputType.number:TextInputType.text, maxLines: ['notes','smartNote'].contains(entry.key)?2:1, decoration: InputDecoration(labelText: const {'shop':'Shop / customer name','street':'Street name','number':'House number','apartment':'Apartment (optional)','postal':'Postal code','city':'City','country':'Country','packages':'Package count','serial':'Stop / reference number','notes':'Notes / description','hours':'Shop opening hours (e.g. Mon-Fri 09:00-17:00)','closedDates':'Weekly closed days (optional)','smartNote':'Smart closure reminder'}[entry.key],helperText:entry.key=='closedDates'?'Example: Sunday, Monday':null))),
        const SizedBox(height:10),Align(alignment:Alignment.centerLeft,child:Text('Shop holidays',style:Theme.of(ctx).textTheme.titleMedium)),
        if(fields['holidays']!.text.trim().isNotEmpty) ...fields['holidays']!.text.split('\n').where((line)=>line.trim().isNotEmpty).map((line){final p=line.split('|');return ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.event_busy,color:Colors.red),title:Text(p.first),subtitle:p.length>1&&p[1].isNotEmpty?Text(p.sublist(1).join('|')):null,trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>setD(()=>fields['holidays']!.text=fields['holidays']!.text.split('\n').where((x)=>x!=line).join('\n'))));}),
        OutlinedButton.icon(onPressed:()async{DateTime selected=DateTime.now();final note=TextEditingController();final result=await showDialog<Map<String,String>>(context:ctx,builder:(hctx)=>StatefulBuilder(builder:(hctx,setH)=>AlertDialog(title:const Text('Add shop holiday'),content:Column(mainAxisSize:MainAxisSize.min,children:[CalendarDatePicker(initialDate:selected,firstDate:DateTime(2020),lastDate:DateTime(2100),onDateChanged:(d)=>setH(()=>selected=d)),TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Holiday note (optional)'))]),actions:[TextButton(onPressed:()=>Navigator.pop(hctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(hctx,{'date':selected.toIso8601String().substring(0,10),'note':note.text.trim()}),child:const Text('Add holiday'))])));if(result!=null){final line=result['date']!+'|'+result['note']!;setD(()=>fields['holidays']!.text=[fields['holidays']!.text.trim(),line].where((x)=>x.isNotEmpty).join('\n'));}},icon:const Icon(Icons.add),label:const Text('Add holiday date')),
                DropdownButtonFormField<String>(value:type, decoration: const InputDecoration(labelText:'Stop type'), items: const [DropdownMenuItem(value:'Fixed',child:Text('Fixed stop • Green')),DropdownMenuItem(value:'Guest',child:Text('Guest stop • Red'))], onChanged:(v)=>setD(()=>type=v??'Fixed')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Include in today’s route'), value:enabled, onChanged:(v)=>setD(()=>enabled=v)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(isEdit?'Save':'Add stop'))],
    )));
    if(ok==true && fields['street']!.text.trim().isNotEmpty && fields['city']!.text.trim().isNotEmpty) {
      final data=<String,dynamic>{for(final e in fields.entries)e.key:e.value.text.trim(), 'packages':int.tryParse(fields['packages']!.text)??1, 'type':type,'enabled':enabled,'done':existing?['done']??false,'created':existing?['created']??DateTime.now().toIso8601String(),'id':existing?['id']??DateTime.now().microsecondsSinceEpoch.toString()};
      final items=stops;
      if(isEdit){ final i=items.indexWhere((s)=>s['id']==existing['id']); if(i>=0)items[i]=data; } else {items.add(data);}
      await persist(items);
    }
  }
  String address(Map<String,dynamic> s)=>[s['number'],s['street'],s['apartment'],s['postal'],s['city'],s['country']].where((x)=>x!=null && x.toString().trim().isNotEmpty).join(' ');
  Future<void> navigate(Map<String,dynamic> s) async {
    final q=Uri.encodeComponent(address(s));
    final uri=Uri.parse('https://www.google.com/maps/dir/?api=1&destination='+q);
    if(!await launchUrl(uri, mode:LaunchMode.externalApplication) && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open maps')));
  }
  Future<void> finishStop(Map<String,dynamic> s) async {
    final items=stops; final i=items.indexWhere((x)=>x['id']==s['id']); if(i<0)return;
    items[i]['done']=true; await persist(items);
  }
  @override
  Widget build(BuildContext context) {
    final allItems=stops;
    if ((widget.route['dailyStopIds'] as List? ?? []).isEmpty && allItems.isNotEmpty) widget.route['dailyStopIds']=allItems.where((s)=>s['enabled']!=false).map((s)=>s['id'].toString()).toList();
    final ids=(widget.route['dailyStopIds'] as List? ?? []).map((e)=>e.toString()).toSet();
    final items=allItems.where((s)=>ids.contains(s['id'].toString())).toList(); final active=items.where((s)=>s['enabled']!=false && s['done']!=true).length;
    return Scaffold(
      appBar:AppBar(title:Text(widget.route['name']?.toString()??'Route'), actions:[IconButton(tooltip:'Edit route warehouse',icon:const Icon(Icons.edit_location_alt),onPressed:()=>editWarehouse())]),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>addStop(),backgroundColor:orange,foregroundColor:Colors.white,icon:const Icon(Icons.add_location_alt),label:const Text('Add stop')),
      body:Column(children:[
        Container(color:Colors.white,padding:const EdgeInsets.all(14),child:Column(children:[Row(children:[const Icon(Icons.flag_outlined,color:blue),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Return point',style:TextStyle(fontWeight:FontWeight.bold)),Text((widget.route['endAddress']??widget.route['warehouse']??'Not set').toString())])),Text(active.toString()+' left',style:const TextStyle(color:blue,fontWeight:FontWeight.bold))]),const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:chooseTodayStops,icon:const Icon(Icons.checklist),label:const Text('Select today’s stops'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:optimizeToday,icon:const Icon(Icons.alt_route),label:const Text('Suggest route')))]),const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>navigateAddress((widget.route['endAddress']??widget.route['warehouse']??'').toString()),icon:const Icon(Icons.navigation),label:const Text('Navigate to return'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:orange),onPressed:finishRoute,icon:const Icon(Icons.flag),label:const Text('Mark complete')))])])),
        Expanded(child:items.isEmpty?const Center(child:Text('No stops yet. Add your first stop.')):ReorderableListView.builder(padding:const EdgeInsets.all(12),itemCount:items.length,onReorder:(oldIndex,newIndex) async {final list=stops; if(newIndex>oldIndex)newIndex--; final item=list.removeAt(oldIndex); list.insert(newIndex,item); await persist(list);},itemBuilder:(ctx,i){
          final s=items[i]; final done=s['done']==true; final guest=s['type']=='Guest';
          final today=DateTime.now().toIso8601String().substring(0,10);
          final holidays=(s['holidays']?.toString()??'').split('\n').where((x)=>x.trim().isNotEmpty);
          final holidayToday=holidays.any((line)=>line.split('|').first.trim()==today);
          final closedDays=(s['closedDates']?.toString()??'').toLowerCase().split(RegExp(r'[,;\\n]+')).map((x)=>x.trim()).where((x)=>x.isNotEmpty).toSet();
          final weekday=const ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'][DateTime.now().weekday-1];
          final dutchWeekday=const ['maandag','dinsdag','woensdag','donderdag','vrijdag','zaterdag','zondag'][DateTime.now().weekday-1];
          final weekdayAliases=<String>{weekday,weekday.substring(0,3),dutchWeekday,dutchWeekday.substring(0,3)};
          final isClosed=holidayToday||closedDays.any((d)=>weekdayAliases.contains(d));
          return Card(key:ValueKey(s['id']),margin:const EdgeInsets.only(bottom:8),color:isClosed?Colors.red.withOpacity(.13):Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18),side:isClosed?BorderSide(color:Colors.red.withOpacity(.55),width:1.5):BorderSide.none),child:Opacity(opacity:done ? .38 : 1,child:Column(children:[if(isClosed)Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:4),decoration:BoxDecoration(color:Colors.red.withOpacity(.12),borderRadius:const BorderRadius.vertical(top:Radius.circular(18))),child:const Text('SHOP CLOSED TODAY',textAlign:TextAlign.center,style:TextStyle(color:Colors.red,fontWeight:FontWeight.w900,fontSize:12))),ListTile(
            leading:CircleAvatar(backgroundColor:done?Colors.grey.withOpacity(.15):(guest?Colors.red.withOpacity(.12):Colors.green.withOpacity(.12)),foregroundColor:done?Colors.grey:(guest?Colors.red:Colors.green),child:Icon(done?Icons.check:Icons.location_on)),
            title:Row(children:[Expanded(child:Text(((s['serial']?.toString().trim().isNotEmpty==true)?s['serial'].toString():(i+1).toString())+'. '+((s['shop']?.toString().isNotEmpty==true)?s['shop'].toString():'Stop'),style:const TextStyle(fontWeight:FontWeight.bold))),const SizedBox(width:6),Container(constraints:const BoxConstraints(maxWidth:115),padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:const Color(0xFFFF1010),borderRadius:BorderRadius.circular(6)),child:Text((s['serial']?.toString().trim().isNotEmpty==true)?s['serial'].toString():'NO REF',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w900)))]),
            subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(address(s)+'\n'+s['packages'].toString()+' packages • '+s['type'].toString()+' • '+(done?'Completed':'Pending')),if((s['notes']?.toString().trim().isNotEmpty??false))Padding(padding:const EdgeInsets.only(top:4),child:Text('Note: '+s['notes'].toString().trim().split(RegExp(r'\s+')).take(3).join(' '),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:orange,fontWeight:FontWeight.bold))),]),
            isThreeLine:true,
            trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='edit')await addStop(s);if(v=='restore')await restoreStop(s);if(v=='delete')await deleteStop(s);if(v=='details')showDetails(s,i);},itemBuilder:(_)=>[const PopupMenuItem(value:'details',child:Text('Details')),const PopupMenuItem(value:'edit',child:Text('Edit')),if(done)const PopupMenuItem(value:'restore',child:Text('Return to today’s route')),const PopupMenuItem(value:'delete',child:Text('Delete'))]),
            onTap:()=>showDetails(s,i),
          ),Padding(padding:const EdgeInsets.fromLTRB(12,0,12,12),child:Row(children:[Expanded(child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:blue),onPressed:()=>navigate(s),icon:const Icon(Icons.navigation),label:const Text('Navigate'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:done?Colors.grey:orange),onPressed:done?()=>restoreStop(s):()=>finishStop(s),icon:Icon(done?Icons.undo:Icons.check_circle_outline),label:Text(done?'Restore':'Mark complete')))]))])));
        })),
      ]),
    );
  }
  Future<void> editWarehouse() async {
    final c=TextEditingController(text:widget.route['warehouse']?.toString()??'');
    final end=TextEditingController(text:widget.route['endAddress']?.toString()??widget.route['warehouse']?.toString()??'');
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Route addresses'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:c,decoration:const InputDecoration(labelText:'Start / warehouse address')),TextField(controller:end,decoration:const InputDecoration(labelText:'Return point address'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))]));
    if(ok==true){widget.route['warehouse']=c.text.trim();widget.route['endAddress']=end.text.trim();await widget.onChanged();if(mounted)setState((){});}
  }
  Future<void> navigateAddress(String destination,{String origin='',List<String> waypoints=const []}) async {
    if(destination.trim().isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Set the destination address first.')));return;}
    final params=<String,String>{'api':'1','destination':destination,'travelmode':'driving'};
    if(origin.trim().isNotEmpty) params['origin']=origin.trim();
    if(waypoints.isNotEmpty) params['waypoints']='optimize:true|'+waypoints.join('|');
    final uri=Uri.https('www.google.com','/maps/dir/',params);
    if(!await launchUrl(uri,mode:LaunchMode.externalApplication)&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open maps')));
  }
  Future<void> chooseTodayStops() async {
    final all=stops.where((s)=>s['enabled']!=false).toList();
    final selected=(widget.route['dailyStopIds'] as List? ?? all.map((s)=>s['id'].toString()).toList()).map((e)=>e.toString()).toSet();
    final result=await showDialog<List<String>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('Select stops for today'),content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final s in all)CheckboxListTile(value:selected.contains(s['id'].toString()),title:Text((s['shop']??'Stop').toString()),subtitle:Text(address(s)),onChanged:(v)=>setD(()=>v==true?selected.add(s['id'].toString()):selected.remove(s['id'].toString())))]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,selected.toList()),child:const Text('Confirm'))])));
    if(result!=null){widget.route['dailyStopIds']=result;widget.route['tripDay']=DateTime.now().toIso8601String().substring(0,10);await widget.onChanged();if(mounted)setState((){});}
  }
  Future<void> optimizeToday() async {
    final ids=(widget.route['dailyStopIds'] as List? ?? []).map((e)=>e.toString()).toSet();
    final chosen=stops.where((s)=>ids.contains(s['id'].toString())&&s['enabled']!=false&&s['done']!=true).toList();
    if(chosen.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Select today’s stops first.')));return;}
    final start=(widget.route['warehouse']??'').toString().trim();
    final end=(widget.route['endAddress']??widget.route['warehouse']??'').toString().trim();
    // Only today's explicitly selected, enabled and unfinished stops are sent as waypoints.
    // The warehouse is the origin, never a waypoint, so Google Maps can optimize the stop order.
    final waypoints=chosen.map((s)=>address(s)).where((a)=>a.trim().isNotEmpty).toList();
    await navigateAddress(end.isEmpty?waypoints.last:end,origin:start,waypoints:waypoints.length>1?waypoints:const []);
  }
  Future<void> finishRoute() async {
    final end=(widget.route['endAddress']??widget.route['warehouse']??'').toString();
    if(end.trim().isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Set the return-point address in route settings first.')));return;}
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Finish this route?'),content:Text('Confirm arrival at the return point:\\n'+end+'\\n\\nThis resets completed stops for a new trip.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Mark complete'))]));
    if(yes!=true)return;final list=stops;for(final s in list){s['done']=false;}widget.route['stops']=list;widget.route['tripDay']=DateTime.now().toIso8601String().substring(0,10);widget.route['tripStarted']=false;widget.route['dailyStopIds']=list.where((s)=>s['enabled']!=false).map((s)=>s['id'].toString()).toList();await widget.onChanged();if(mounted)setState((){});
  }
  Future<void> restoreStop(Map<String,dynamic> s) async {final list=stops;final i=list.indexWhere((x)=>x['id']==s['id']);if(i<0)return;list[i]['done']=false;final ids=(widget.route['dailyStopIds'] as List? ?? []).map((e)=>e.toString()).toList();if(!ids.contains(s['id'].toString()))ids.add(s['id'].toString());widget.route['dailyStopIds']=ids;await persist(list);}

  Future<void> deleteStop(Map<String,dynamic> s) async {
    final first=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Delete stop?'),content:const Text('Are you sure you want to delete this stop?'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm'))]));
    if(first!=true||!mounted)return;
    final second=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Final confirmation'),content:const Text('This will remove the stop from this route.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete stop'))]));
    if(second==true){final list=stops..removeWhere((x)=>x['id']==s['id']);await persist(list);if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Stop deleted'),duration:Duration(seconds:5)));}
  }
  void showDetails(Map<String,dynamic> s,int i) {
    showModalBottomSheet(context:context,showDragHandle:true,isScrollControlled:true,builder:(ctx)=>Padding(padding:const EdgeInsets.all(20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text('Stop '+(i+1).toString()+': '+(s['shop']??'').toString(),style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),
      for(final pair in <String,String>{'Address':address(s),'Packages':s['packages'].toString(),'Type':s['type'].toString(),'Opening hours':(s['hours']??'').toString(),'Weekly closed days':(s['closedDates']??'').toString(),'Shop holidays':(s['holidays']??'').toString().replaceAll('\n','; '),'Smart reminder':(s['smartNote']??'').toString(),'Reference':(s['serial']??'').toString(),'Notes':(s['notes']??'').toString(),'Created':(s['created']??'').toString(),'Status':s['done']==true?'Completed':'Pending'}.entries) Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Text(pair.key+': '+(pair.value.isEmpty?'—':pair.value))),
      const SizedBox(height:16),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>navigate(s),icon:const Icon(Icons.navigation),label:const Text('Start Journey'))),const SizedBox(height:18)
    ]))));
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

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
    appBar: AppBar(title: const Text('Next Stop', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.4, color: blue)), actions: [IconButton(tooltip: 'Fuel stations', onPressed: openFuelStations, icon: const Icon(Icons.local_gas_station)), IconButton(tooltip: 'Import route file', onPressed: importRouteFile, icon: const Icon(Icons.file_open)), IconButton(tooltip: 'Scan route QR code', onPressed: scanRoute, icon: const Icon(Icons.qr_code_scanner)), IconButton(tooltip: 'Add route', onPressed: addRoute, icon: const Icon(Icons.add_circle_outline))]),
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

  Future<void> openFuelStations() async { final uri=Uri.https('www.google.com','/maps/search/',{'api':'1','query':'petrol stations near me'}); if(!await launchUrl(uri,mode:LaunchMode.externalApplication)&&mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open fuel stations map'))); }

  Future<Map<String,dynamic>> _routeWithPhotos(Map<String,dynamic> route) async {
    final copy=Map<String,dynamic>.from(jsonDecode(jsonEncode(route)) as Map);
    Future<String?> encodePhoto(dynamic path) async {
      if(path==null||path.toString().isEmpty)return null;
      try { final file=File(path.toString()); if(!await file.exists())return null; return base64Encode(await file.readAsBytes()); } catch (_) { return null; }
    }
    final stops=<Map<String,dynamic>>[];
    for(final raw in (copy['stops'] as List? ?? [])){
      final s=Map<String,dynamic>.from(raw as Map);
      final data=await encodePhoto(s['photoPath']);
      if(data!=null)s['photoDataBase64']=data;
      s.remove('photoPath');
      stops.add(s);
    }
    copy['stops']=stops;
    final reports=<Map<String,dynamic>>[];
    for(final raw in (copy['reports'] as List? ?? [])){
      final r=Map<String,dynamic>.from(raw as Map);
      final images=<Map<String,String>>[];
      for(final path in (r['photos'] as List? ?? [])){final data=await encodePhoto(path);if(data!=null)images.add({'base64':data,'name':'report_photo.jpg'});}
      r['photos']=images;
      reports.add(r);
    }
    if(copy.containsKey('reports'))copy['reports']=reports;
    return copy;
  }

  Future<Map<String,dynamic>> _restoreRoutePhotos(Map<String,dynamic> incoming) async {
    final copy=Map<String,dynamic>.from(incoming);
    final dir=await getApplicationDocumentsDirectory();
    Future<String?> savePhoto(dynamic data,String name) async {
      if(data==null||data.toString().isEmpty)return null;
      try {final bytes=base64Decode(data.toString());final safe=name.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'),'_');final file=File('${dir.path}/nextstop_${DateTime.now().microsecondsSinceEpoch}_$safe');await file.writeAsBytes(bytes,flush:true);return file.path;}catch(_){return null;}
    }
    final stops=<Map<String,dynamic>>[];
    for(final raw in (copy['stops'] as List? ?? [])){
      final s=Map<String,dynamic>.from(raw as Map);
      final path=await savePhoto(s.remove('photoDataBase64'),'shop.jpg');
      if(path!=null)s['photoPath']=path;
      stops.add(s);
    }
    copy['stops']=stops;
    if(copy['reports'] is List){
      final reports=<Map<String,dynamic>>[];
      for(final raw in (copy['reports'] as List)){
        final r=Map<String,dynamic>.from(raw as Map);
        final photos=<String>[];
        for(final rawPhoto in (r['photos'] as List? ?? [])){
          if(rawPhoto is Map){final path=await savePhoto(rawPhoto['base64'],rawPhoto['name']?.toString()??'report.jpg');if(path!=null)photos.add(path);}
          else if(rawPhoto is String)photos.add(rawPhoto);
        }
        r['photos']=photos;reports.add(r);
      }
      copy['reports']=reports;
    }
    return copy;
  }

  Future<void> shareRoute(Map<String,dynamic> route) async {
    try {
      final portable=await _routeWithPhotos(route);
      final payload=jsonEncode({'app':'next-stop','version':2,'route':portable});
      final safeName=(route['name']?.toString()??'route').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'),'_');
      final dir=await getTemporaryDirectory();
      final file=File('${dir.path}/NextStop_$safeName.json');
      await file.writeAsString(payload,flush:true);
      await Share.shareXFiles([XFile(file.path,mimeType:'application/json')],text:'Next Stop route: ${route['name']}. On the other phone, open Next Stop and choose Import route file.');
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not share route file: $e')));
    }
  }

  Future<void> importRouteFile() async {
    try {
      // WhatsApp and Android document providers may give exported files a
      // different extension or no extension at all. Let the user select the
      // received file, then validate its contents instead of filtering by name.
      final picked=await FilePicker.platform.pickFiles(type:FileType.any,withData:true);
      if(picked==null||picked.files.isEmpty)return;
      final file=picked.files.single;
      final bytes=file.bytes??(file.path!=null?await File(file.path!).readAsBytes():null);
      if(bytes==null)throw const FormatException('Android could not read this file. Save it to Downloads and try again.');
      var text= utf8.decode(bytes,allowMalformed:false);
      if(text.startsWith('\uFEFF')) text=text.substring(1);
      final decoded=jsonDecode(text);
      if(decoded is! Map)throw const FormatException('This file is not a valid JSON route export.');
      final data=Map<String,dynamic>.from(decoded);
      if(data['app']!='next-stop'||data['route'] is! Map) {
        throw const FormatException('This file is not a Next Stop route export. Choose the original NextStop_*.json file shared from the app.');
      }
      var incoming=await _restoreRoutePhotos(Map<String,dynamic>.from(data['route'] as Map));
      final incomingStops=(incoming['stops'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e)).toList();
      incoming['id']=DateTime.now().microsecondsSinceEpoch.toString();
      incoming['name']='${incoming['name']??'Imported route'} (imported)';
      incoming['stops']=incomingStops;
      incoming['created']=DateTime.now().toIso8601String();
      incoming['dailyStopIds']=<String>[];
      incoming['tripDay']=DateTime.now().toIso8601String().substring(0,10);
      incoming['tripStarted']=false;
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Import route file?'),content:Text('Add "${incoming['name']}" with ${incomingStops.length} stops? Existing routes will not change.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Import'))]));
      if(yes==true&&mounted){setState(()=>routes.add(incoming));await save();ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Route and available photos imported successfully.')));}
    } on FormatException catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Import failed: ${e.message}')));
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not import route file. Save the file to Downloads and retry. Details: $e')));
    }
  }

  Future<void> scanRoute() async {
    final scanned = await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScanRoutePage()));
    if (scanned == null || !mounted) return;
    try {
      final assembled = scanned.startsWith('NSC1|') ? scanned.substring(5) : scanned;
      final decodedText = assembled.startsWith('NSZ1:') ? utf8.decode(gzip.decode(base64Url.decode(assembled.substring(5)))) : assembled;
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
  final Map<String,String> _chunks={};
  int? _total;
  String? _session;
  bool _waitingForNext=false;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Scan route QR code')),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(18),child:Text(_total==null?'Point the camera at each QR page in order. The route imports after the final page.':'Scanned ${_chunks.length} of $_total QR pages. ${_waitingForNext?'Tap Continue, then scan the next page.':'Keep the camera on QR ${_chunks.length+1}.'}',textAlign:TextAlign.center)),
      if(_waitingForNext) Padding(padding:const EdgeInsets.only(bottom:8),child:FilledButton(onPressed:()=>setState(()=>_waitingForNext=false),child:const Text('Continue scanning'))),
      Expanded(child:Padding(padding:const EdgeInsets.all(16),child:ClipRRect(borderRadius:BorderRadius.circular(18),child:MobileScanner(onDetect:(capture){
        if(handled||_waitingForNext)return;
        final value=capture.barcodes.isEmpty?null:capture.barcodes.first.rawValue;
        if(value==null||value.isEmpty)return;
        if(value.startsWith('NSC1:')){final parts=value.split(':');if(parts.length<5)return;final session=parts[1];final index=int.tryParse(parts[2]);final total=int.tryParse(parts[3]);if(index==null||total==null||index<1||index>total)return;if(_session!=null&&_session!=session){_chunks.clear();} _session=session;_total=total;_chunks[index.toString()]=parts.sublist(4).join(':');if(_chunks.length==total&&List.generate(total,(i)=>(i+1).toString()).every(_chunks.containsKey)){handled=true;Navigator.pop(context,'NSC1|'+List.generate(total,(i)=>_chunks[(i+1).toString()]!).join());}else setState(()=>_waitingForNext=true);
        }else{handled=true;Navigator.pop(context,value);}
      })))),
    ]),
  );
}


class RouteMapPage extends StatefulWidget {
  final String startAddress;
  final String endAddress;
  final List<Map<String,dynamic>> stops;
  final String Function(Map<String,dynamic>) addressOf;
  const RouteMapPage({super.key,required this.startAddress,required this.endAddress,required this.stops,required this.addressOf});
  @override State<RouteMapPage> createState()=>_RouteMapPageState();
}
class _RouteMapPageState extends State<RouteMapPage> {
  bool loading=true;
  String? error;
  List<Map<String,dynamic>> points=[];
  List<LatLng> line=[];
  List<Map<String,dynamic>> orderedStops=[];
  double? totalKm;
  int? totalMinutes;
  @override void initState(){super.initState();loadRoute();}
  Future<LatLng?> geocode(String address) async {
    // Try the original address first, then common Dutch address variants.
    // A single failed Nominatim lookup should not immediately break the route.
    final original = address.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'(\d{4})\s*([A-Z]{2})(?=[A-Za-z])', caseSensitive:false), r'$1 $2 ');
    if (original.isEmpty) return null;
    final queries = <String>[
      original,
      original.replaceAll(RegExp(r'\b(\d{4})\s+([A-Z]{2})\b', caseSensitive:false), r'$1$2'),
      if (!original.toLowerCase().contains('netherlands') && !original.toLowerCase().contains('nederland'))
        '$original, Netherlands',
    ].toSet();
    for (final query in queries) {
      try {
        final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
          'q': query,
          'format': 'jsonv2',
          'limit': '1',
          'countrycodes': 'nl',
          'addressdetails': '1',
        });
        final res = await http.get(uri, headers: {
          'User-Agent': 'NextStopDeliveryPlanner/1.0 (Android delivery route planner)',
          'Accept-Language': 'nl,en',
        }).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final decoded = jsonDecode(res.body);
        if (decoded is! List || decoded.isEmpty || decoded.first is! Map) continue;
        final first = decoded.first as Map;
        final lat = double.tryParse(first['lat']?.toString() ?? '');
        final lon = double.tryParse(first['lon']?.toString() ?? '');
        if (lat != null && lon != null) return LatLng(lat, lon);
      } catch (_) {
        // Continue to the next query variant.
      }
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    return null;
  }
  Future<void> loadRoute() async {
    setState(() {loading=true;error=null;});
    try {
      final input=<Map<String,dynamic>>[{'id':'warehouse','label':'W','title':'Start / warehouse','address':widget.startAddress,'kind':'warehouse'}];
      for(var i=0;i<widget.stops.length;i++){
        final s=widget.stops[i];
        input.add({'id':s['id']?.toString()??'$i','label':(s['shop']?.toString().trim().isNotEmpty==true)?s['shop'].toString().trim():'Stop ${i+1}','title':(s['shop']?.toString().trim().isNotEmpty==true)?s['shop'].toString().trim():'Stop ${i+1}','address':widget.addressOf(s),'kind':'stop','stop':s});
      }
      if(widget.endAddress.trim()!=widget.startAddress.trim())input.add({'id':'return','label':'R','title':'Return point','address':widget.endAddress,'kind':'return'});
      for(var i=0;i<input.length;i++){
        final p=input[i];
        final ll=await geocode(p['address'].toString());
        if(ll==null)throw Exception('Could not locate: ${p['title']} — ${p['address']}');
        p['latLng']=ll;
        if(i<input.length-1)await Future<void>.delayed(const Duration(milliseconds:1050));
      }
      final coords=input.map((p){final ll=p['latLng'] as LatLng;return '${ll.longitude},${ll.latitude}';}).join(';');
      final closedLoop=widget.endAddress.trim()==widget.startAddress.trim();
      final uri=Uri.https('router.project-osrm.org','/trip/v1/driving/$coords',{'roundtrip':closedLoop?'true':'false','source':'first',if(!closedLoop)'destination':'last','overview':'full','geometries':'geojson','steps':'false'});
      final response=await http.get(uri);
      if(response.statusCode!=200)throw Exception('The routing service is unavailable (HTTP ${response.statusCode}).');
      final data=jsonDecode(response.body) as Map<String,dynamic>;
      if(data['code']!='Ok'||(data['trips'] as List? ?? []).isEmpty)throw Exception('No drivable route could be calculated for these addresses.');
      final trip=(data['trips'] as List).first as Map<String,dynamic>;
      final coordinates=(trip['geometry']['coordinates'] as List).map((p)=>LatLng((p[1] as num).toDouble(),(p[0] as num).toDouble())).toList();
      final waypoints=(data['waypoints'] as List).cast<Map<String,dynamic>>();
      final ordered=[...input]..sort((a,b){
        final ai=input.indexOf(a),bi=input.indexOf(b);
        final aw=(waypoints[ai]['waypoint_index'] as num).toInt(),bw=(waypoints[bi]['waypoint_index'] as num).toInt();
        return aw.compareTo(bw);
      });
      final sortedStops=ordered.where((p)=>p['kind']=='stop').map((p)=>Map<String,dynamic>.from(p['stop'] as Map)).toList();
      if(!mounted)return;
      setState(() {points=input;line=coordinates;orderedStops=sortedStops;totalKm=(trip['distance'] as num).toDouble()/1000;totalMinutes=((trip['duration'] as num).toDouble()/60).round();loading=false;});
    }catch(e){if(mounted)setState(() {error=e.toString().replaceFirst('Exception: ','');loading=false;});}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Optimized route')),
    body:loading?const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[CircularProgressIndicator(),SizedBox(height:16),Text('Locating stops and calculating route…'),SizedBox(height:8),Text('For many stops, this can take a little while.',textAlign:TextAlign.center)]))
    :error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.map_outlined,size:54,color:Colors.red),const SizedBox(height:12),Text(error!,textAlign:TextAlign.center),const SizedBox(height:16),FilledButton.icon(onPressed:loadRoute,icon:const Icon(Icons.refresh),label:const Text('Try again'))])))
    :Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:Text('${totalKm!.toStringAsFixed(1)} km estimated • $totalMinutes min driving',style:const TextStyle(fontWeight:FontWeight.bold))),const Icon(Icons.route,color:Colors.green)])),
      Expanded(child:FlutterMap(options:MapOptions(initialCenter:points.first['latLng'] as LatLng,initialZoom:11,initialCameraFit:CameraFit.coordinates(coordinates:points.map((p)=>p['latLng'] as LatLng).toList(),padding:const EdgeInsets.all(40))),children:[
        TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.nextstop.app'),
        if(line.isNotEmpty)PolylineLayer(polylines:[Polyline(points:line,strokeWidth:5,color:Colors.blue)]),
        MarkerLayer(markers:[for(final p in points)Marker(point:p['latLng'] as LatLng,width:66,height:56,child:Column(children:[Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),decoration:BoxDecoration(color:p['kind']=='warehouse'?Colors.black:(p['kind']=='return'?Colors.orange:Colors.blue),borderRadius:BorderRadius.circular(8),border:Border.all(color:Colors.white,width:1.5)),child:Text(p['label'].toString(),maxLines:1,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:12))),const Icon(Icons.location_on,color:Colors.red,size:22)]))]),
        const RichAttributionWidget(attributions:[TextSourceAttribution('© OpenStreetMap contributors')])
      ])),
      SizedBox(height:200,child:ListView(padding:const EdgeInsets.all(12),children:[
        const Text('Suggested stop order',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        for(var i=0;i<orderedStops.length;i++)ListTile(dense:true,leading:CircleAvatar(child:Text('${i+1}')),title:Text((orderedStops[i]['shop']?.toString().trim().isNotEmpty==true)?orderedStops[i]['shop'].toString():'Stop ${i+1}'),subtitle:Text('${(orderedStops[i]['serial']?.toString().trim().isNotEmpty==true)?'Ref: ${orderedStops[i]['serial']} • ':''}${widget.addressOf(orderedStops[i])}'),trailing:Text((orderedStops[i]['hours']??'').toString(),style:const TextStyle(fontSize:11))),
        const Text('Route order is optimized by road distance/time. Opening hours are shown for review but are not yet used as hard scheduling constraints.',style:TextStyle(fontSize:12,color:Colors.grey))
      ]))
    ])
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
  Future<void> addStop([Map<String,dynamic>? existing, bool asNew = false]) async {
    final isEdit = existing != null && !asNew;
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
    String? photoPath=existing?['photoPath']?.toString();
    Future<void> pickStopPhoto(void Function(void Function()) setD) async { final x=await ImagePicker().pickImage(source:ImageSource.gallery,imageQuality:78,maxWidth:1600); if(x!=null)setD(()=>photoPath=x.path); }
    String type = existing?['type']?.toString() ?? 'Fixed';
    bool enabled = existing?['enabled'] != false;
    final ok = await showDialog<bool>(context: context, builder: (ctx)=> StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title: Text(isEdit?'Edit stop':'Add stop'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing:8,runSpacing:4,children:[OutlinedButton.icon(onPressed:()=>pickStopPhoto(setD),icon:const Icon(Icons.add_a_photo),label:Text(photoPath==null?'Add shop photo':'Change shop photo')),if(photoPath!=null)TextButton.icon(onPressed:()=>setD(()=>photoPath=null),icon:const Icon(Icons.delete_outline,color:Colors.red),label:const Text('Remove photo',style:TextStyle(color:Colors.red)))]),
        if(photoPath!=null&&File(photoPath!).existsSync()) Padding(padding:const EdgeInsets.only(bottom:12),child:Image.file(File(photoPath!),height:120,fit:BoxFit.cover)),
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
      final data=<String,dynamic>{for(final e in fields.entries)e.key:e.value.text.trim(), 'photoPath':photoPath, 'packages':int.tryParse(fields['packages']!.text)??1, 'type':type,'enabled':enabled,'done':isEdit?(existing?['done']??false):false,'created':isEdit?(existing?['created']??DateTime.now().toIso8601String()):DateTime.now().toIso8601String(),'id':isEdit?(existing?['id']??DateTime.now().microsecondsSinceEpoch.toString()):DateTime.now().microsecondsSinceEpoch.toString()};
      final items=stops;
      if(isEdit){ final i=items.indexWhere((s)=>s['id']==existing['id']); if(i>=0)items[i]=data; } else {items.add(data);}
      await persist(items);
    }
  }
  Map<String,dynamic> _portableStop(Map<String,dynamic> stop) {
    final copy=Map<String,dynamic>.from(stop);
    // A phone-local photo path is not valid on another device. QR carries
    // all text/structured fields; use route-file Quick Share for photo transfer.
    copy.remove('photoPath');
    copy.remove('photoDataBase64');
    copy.remove('done');
    copy.remove('id');
    copy.remove('created');
    return copy;
  }

  String _stopCode(Map<String,dynamic> stop)=>jsonEncode({'app':'next-stop','kind':'stop','version':1,'stop':_portableStop(stop)});

  Future<void> showStopCode(Map<String,dynamic> stop) async {
    final code=_stopCode(stop);
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('Stop code • ${stop['shop']??'Stop'}'),
      content:SizedBox(width:300,child:Column(mainAxisSize:MainAxisSize.min,children:[
        QrImageView(data:code,size:250,errorCorrectionLevel:QrErrorCorrectLevel.M),
        const SizedBox(height:8),
        const Text('Scan this code on the other phone to add this stop. Photos are transferred with route-file sharing.',textAlign:TextAlign.center),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close')),
        FilledButton.icon(onPressed:(){Clipboard.setData(ClipboardData(text:code));ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Stop code copied. You can paste it into a message.')));},icon:const Icon(Icons.copy),label:const Text('Copy code')),
      ],
    ));
  }

  Future<void> scanStopCode() async {
    final scanned=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScanRoutePage()));
    if(scanned==null||!mounted)return;
    try {
      final raw=scanned.startsWith('NSC1|')?scanned.substring(5):scanned;
      final decoded=raw.startsWith('NSZ1:')?utf8.decode(gzip.decode(base64Url.decode(raw.substring(5)))):raw;
      final value=jsonDecode(decoded);
      if(value is! Map||value['app']!='next-stop'||value['kind']!='stop'||value['stop'] is! Map) {
        throw const FormatException('This QR code is not a single Next Stop stop code.');
      }
      final incoming=Map<String,dynamic>.from(value['stop'] as Map);
      incoming.remove('photoPath');
      await addStop(incoming,true);
    } on FormatException catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not read stop code: ${e.message}')));
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not import stop code: $e')));
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
      floatingActionButton:null,
      body:SafeArea(child:Column(children:[
        Container(color:Colors.white,padding:const EdgeInsets.all(14),child:Column(children:[Row(children:[const Icon(Icons.flag_outlined,color:blue),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Return point',style:TextStyle(fontWeight:FontWeight.bold)),Text((widget.route['endAddress']??widget.route['warehouse']??'Not set').toString())])),Text(active.toString()+' left',style:const TextStyle(color:blue,fontWeight:FontWeight.bold))]),const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:chooseTodayStops,icon:const Icon(Icons.checklist),label:const Text('Select today’s stops'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:optimizeToday,icon:const Icon(Icons.alt_route),label:const Text('Suggest route')))]),const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>addStop(),icon:const Icon(Icons.add_location_alt),label:const Text('Add stop'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:scanStopCode,icon:const Icon(Icons.qr_code_scanner),label:const Text('Scan stop code')))]),const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:openProblemReport,icon:const Icon(Icons.report_problem_outlined),label:const Text('Report issue'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:manageProblemReports,icon:const Icon(Icons.receipt_long),label:Text('Reports ('+(widget.route['reports'] as List? ?? []).length.toString()+')')))]),const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>navigateAddress((widget.route['endAddress']??widget.route['warehouse']??'').toString()),icon:const Icon(Icons.navigation),label:const Text('Navigate to return'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:orange),onPressed:finishRoute,icon:const Icon(Icons.flag),label:const Text('Mark complete')))])])),
        Expanded(child:items.isEmpty?const Center(child:Text('No stops yet. Add your first stop.')):ReorderableListView.builder(padding:const EdgeInsets.all(12),itemCount:items.length,onReorder:(oldIndex,newIndex) async {final list=stops; if(newIndex>oldIndex)newIndex--; final visibleIds=items.map((s)=>s['id'].toString()).toList(); if(oldIndex<0||oldIndex>=visibleIds.length||newIndex<0||newIndex>=visibleIds.length)return; final movingId=visibleIds[oldIndex]; final targetId=visibleIds[newIndex]; final from=list.indexWhere((s)=>s['id'].toString()==movingId); final to=list.indexWhere((s)=>s['id'].toString()==targetId); if(from<0||to<0)return; final item=list.removeAt(from); list.insert(to,item); await persist(list);},itemBuilder:(ctx,i){
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
            title:Row(children:[Expanded(child:Text((i+1).toString()+'. '+((s['shop']?.toString().isNotEmpty==true)?s['shop'].toString():'Stop'),style:const TextStyle(fontWeight:FontWeight.bold))),const SizedBox(width:6),Container(constraints:const BoxConstraints(maxWidth:115),padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:const Color(0xFFFF1010),borderRadius:BorderRadius.circular(6)),child:Text((s['serial']?.toString().trim().isNotEmpty==true)?s['serial'].toString():'NO REF',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w900)))]),
            subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(address(s)+'\n'+s['packages'].toString()+' packages • '+s['type'].toString()+' • '+(done?'Completed':'Pending')),if((s['notes']?.toString().trim().isNotEmpty??false))Padding(padding:const EdgeInsets.only(top:4),child:Text('Note: '+s['notes'].toString().trim().split(RegExp(r'\s+')).take(3).join(' '),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:orange,fontWeight:FontWeight.bold))),]),
            isThreeLine:true,
            trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='edit')await addStop(s);if(v=='restore')await restoreStop(s);if(v=='delete')await deleteStop(s);if(v=='details')showDetails(s,i);},itemBuilder:(_)=>[const PopupMenuItem(value:'details',child:Text('Details')),const PopupMenuItem(value:'edit',child:Text('Edit')),if(done)const PopupMenuItem(value:'restore',child:Text('Return to today’s route')),const PopupMenuItem(value:'delete',child:Text('Delete'))]),
            onTap:()=>showDetails(s,i),
          ),Padding(padding:const EdgeInsets.fromLTRB(12,0,12,12),child:Row(children:[Expanded(child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:blue),onPressed:()=>navigate(s),icon:const Icon(Icons.navigation),label:const Text('Navigate'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:done?Colors.grey:orange),onPressed:done?()=>restoreStop(s):()=>finishStop(s),icon:Icon(done?Icons.undo:Icons.check_circle_outline),label:Text(done?'Restore':'Mark complete')))]))])));
        })),
      ])),
    );
  }
  Future<void> openProblemReport() async {
    final kinds=['Vehicle: Oil change','Vehicle: Brakes','Vehicle: Tires','Vehicle: Lights','Vehicle: Engine coolant / water','Vehicle: Engine fault','Accident','Route problem','Other'];
    String kind=kinds.first;final notes=TextEditingController();final photos=<String>[];
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('Report a problem'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(value:kind,items:[for(final k in kinds)DropdownMenuItem(value:k,child:Text(k))],onChanged:(v)=>setD(()=>kind=v??kinds.first),decoration:const InputDecoration(labelText:'Problem type')),const SizedBox(height:8),TextField(controller:notes,maxLines:4,decoration:const InputDecoration(labelText:'Details / vehicle or route issue')),const SizedBox(height:8),OutlinedButton.icon(onPressed:()async{final xs=await ImagePicker().pickMultiImage(imageQuality:75,maxWidth:1600);setD(()=>photos.addAll(xs.map((x)=>x.path)));},icon:const Icon(Icons.photo_library),label:Text('Add photos (${photos.length})')),for(final p in photos)if(File(p).existsSync())Padding(padding:const EdgeInsets.only(top:6),child:Image.file(File(p),height:70,fit:BoxFit.cover)),if(kind=='Accident')const Text('For emergencies, contact emergency services first.',style:TextStyle(color:Colors.red))]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save report'))])));
    if(yes==true){final reports=List<Map<String,dynamic>>.from((widget.route['reports'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e)));reports.add({'id':DateTime.now().microsecondsSinceEpoch.toString(),'type':kind,'notes':notes.text.trim(),'photos':photos,'created':DateTime.now().toIso8601String(),'status':'Open'});widget.route['reports']=reports;await widget.onChanged();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Problem report saved on this phone.')));}
  }

  Future<void> manageProblemReports() async {
    final reports = List<Map<String,dynamic>>.from(
      (widget.route['reports'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e)),
    );
    if (reports.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('No saved problem reports yet.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context:context, isScrollControlled:true, showDragHandle:true,
      builder:(sheetContext)=>SafeArea(child:StatefulBuilder(
        builder:(sheetContext,setSheetState)=>SizedBox(
          height:MediaQuery.of(sheetContext).size.height*0.82,
          child:Column(children:[
            Padding(padding:const EdgeInsets.fromLTRB(16,4,16,8),child:Row(children:[
              Expanded(child:Text('Problem reports ('+reports.length.toString()+')',style:Theme.of(sheetContext).textTheme.titleLarge)),
              IconButton(tooltip:'Share all reports',icon:const Icon(Icons.share),onPressed:() async {
                final paths=<String>[];
                final lines=<String>['Next Stop — vehicle and route problem reports','Route: '+(widget.route['name']??'Route').toString(),''];
                for(var i=0;i<reports.length;i++){
                  final r=reports[i];
                  lines.add((i+1).toString()+'. '+(r['type']??'Problem').toString());
                  lines.add('Date: '+(r['created']??'Unknown').toString());
                  lines.add('Status: '+(r['status']??'Open').toString());
                  lines.add('Details: '+(r['notes']??'—').toString());
                  lines.add('');
                  for(final raw in (r['photos'] as List? ?? [])){
                    final p=raw.toString(); if(p.isNotEmpty && await File(p).exists()) paths.add(p);
                  }
                }
                await Share.shareXFiles(paths.map((p)=>XFile(p)).toList(),text:lines.join('\n'),subject:'Next Stop problem reports');
              }),
            ])),
            const Divider(height:1),
            Expanded(child:ListView.builder(
              padding:const EdgeInsets.all(12), itemCount:reports.length,
              itemBuilder:(ctx,i){
                final report=reports[i];
                final photos=(report['photos'] as List? ?? []).map((e)=>e.toString()).toList();
                return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
                  crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Row(children:[
                      Expanded(child:Text((report['type']??'Problem').toString(),style:const TextStyle(fontWeight:FontWeight.bold))),
                      IconButton(tooltip:'Edit report',icon:const Icon(Icons.edit_outlined),onPressed:() async {
                        final note=TextEditingController(text:(report['notes']??'').toString());
                        final status=TextEditingController(text:(report['status']??'Open').toString());
                        final changed=await showDialog<bool>(context:context,builder:(dctx)=>AlertDialog(
                          title:const Text('Edit problem report'),
                          content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
                            Text((report['type']??'Problem').toString()),
                            TextField(controller:note,maxLines:4,decoration:const InputDecoration(labelText:'Details')),
                            TextField(controller:status,decoration:const InputDecoration(labelText:'Status')),
                          ])),
                          actions:[TextButton(onPressed:()=>Navigator.pop(dctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dctx,true),child:const Text('Save'))],
                        ));
                        if(changed==true){
                          report['notes']=note.text.trim();
                          report['status']=status.text.trim().isEmpty?'Open':status.text.trim();
                          report['photos']=photos;
                          widget.route['reports']=reports;
                          await widget.onChanged();
                          setSheetState((){});
                          if(mounted)setState((){});
                        }
                      }),
                      IconButton(tooltip:'Delete report',icon:const Icon(Icons.delete_outline,color:Colors.red),onPressed:() async {
                        final yes=await showDialog<bool>(context:context,builder:(dctx)=>AlertDialog(
                          title:const Text('Delete report?'),
                          content:const Text('This removes the selected report from this route.'),
                          actions:[TextButton(onPressed:()=>Navigator.pop(dctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dctx,true),child:const Text('Delete'))],
                        ));
                        if(yes==true){
                          reports.removeAt(i); widget.route['reports']=reports;
                          await widget.onChanged(); setSheetState((){});
                          if(mounted)setState((){});
                        }
                      }),
                    ]),
                    Text('Date: '+(report['created']??'').toString()),
                    Text('Status: '+(report['status']??'Open').toString()),
                    if((report['notes']??'').toString().trim().isNotEmpty) Padding(padding:const EdgeInsets.only(top:6),child:Text(report['notes'].toString())),
                    if(photos.isNotEmpty) Padding(padding:const EdgeInsets.only(top:8),child:Wrap(spacing:8,runSpacing:8,children:[
                      for(var pi=0;pi<photos.length;pi++)
                        if(File(photos[pi]).existsSync()) SizedBox(width:92,child:Column(children:[
                          Image.file(File(photos[pi]),width:92,height:76,fit:BoxFit.cover),
                          TextButton(onPressed:(){
                            setSheetState(()=>photos.removeAt(pi));
                            report['photos']=photos; widget.route['reports']=reports; widget.onChanged();
                          },child:const Text('Remove photo',style:TextStyle(fontSize:11))),
                        ])),
                    ])),
                    OutlinedButton.icon(onPressed:() async {
                      final picked=await ImagePicker().pickMultiImage(imageQuality:75,maxWidth:1600);
                      if(picked.isNotEmpty){setSheetState(()=>photos.addAll(picked.map((x)=>x.path)));report['photos']=photos;widget.route['reports']=reports;await widget.onChanged();}
                    },icon:const Icon(Icons.add_photo_alternate),label:const Text('Add photos')),
                  ],
                )));
              },
            )),
            Padding(padding:const EdgeInsets.all(12),child:SizedBox(width:double.infinity,child:FilledButton.icon(
              onPressed:() async {
                final paths=<String>[];
                final lines=<String>['Next Stop — vehicle and route problem reports','Route: '+(widget.route['name']??'Route').toString(),''];
                for(var i=0;i<reports.length;i++){
                  final r=reports[i];
                  lines.add((i+1).toString()+'. '+(r['type']??'Problem').toString());
                  lines.add('Date: '+(r['created']??'Unknown').toString());
                  lines.add('Status: '+(r['status']??'Open').toString());
                  lines.add('Details: '+(r['notes']??'—').toString()); lines.add('');
                  for(final raw in (r['photos'] as List? ?? [])){final p=raw.toString();if(p.isNotEmpty&&await File(p).exists())paths.add(p);}
                }
                await Share.shareXFiles(paths.map((p)=>XFile(p)).toList(),text:lines.join('\n'),subject:'Next Stop problem reports');
              },
              icon:const Icon(Icons.share),label:const Text('Share all reports and photos'),
            ))),
          ]),
        ),
      )),
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
    if(start.isEmpty||end.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Set both the warehouse and return address first.')));return;}
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>RouteMapPage(startAddress:start,endAddress:end,stops:chosen.map((s)=>Map<String,dynamic>.from(s)).toList(),addressOf:address)));
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
      if((s['photoPath']?.toString().isNotEmpty??false)&&File(s['photoPath'].toString()).existsSync())ClipRRect(borderRadius:BorderRadius.circular(14),child:Image.file(File(s['photoPath'].toString()),width:double.infinity,fit:BoxFit.contain)),
      for(final pair in <String,String>{'Address':address(s),'Packages':s['packages'].toString(),'Type':s['type'].toString(),'Opening hours':(s['hours']??'').toString(),'Weekly closed days':(s['closedDates']??'').toString(),'Shop holidays':(s['holidays']??'').toString().replaceAll('\n','; '),'Smart reminder':(s['smartNote']??'').toString(),'Reference':(s['serial']??'').toString(),'Notes':(s['notes']??'').toString(),'Created':(s['created']??'').toString(),'Status':s['done']==true?'Completed':'Pending'}.entries) Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Text(pair.key+': '+(pair.value.isEmpty?'—':pair.value))),
      const SizedBox(height:16),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>showStopCode(s),icon:const Icon(Icons.qr_code_2),label:const Text('Show / copy code'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:(){Navigator.pop(ctx);addStop(s);},icon:const Icon(Icons.edit),label:const Text('Edit stop')))]),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>navigate(s),icon:const Icon(Icons.navigation),label:const Text('Start Journey'))),const SizedBox(height:18)
    ]))));
  }
}

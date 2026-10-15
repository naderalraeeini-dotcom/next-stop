import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

const vehicleBlue = Color(0xFF1769AA);
const vehicleOrange = Color(0xFFFF8A24);

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});
  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  List<Map<String, dynamic>> vehicles = [];
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString('next_stop_vehicles_v1');
      if (raw != null) vehicles = (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e)).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('next_stop_vehicles_v1', jsonEncode(vehicles));
  }

  String dateLabel(dynamic value) {
    if (value == null || value.toString().isEmpty) return 'غير محدد';
    final d = DateTime.tryParse(value.toString());
    if (d == null) return value.toString();
    return '${d.day.toString().padLeft(2,'0')}-${d.month.toString().padLeft(2,'0')}-${d.year}';
  }
  int remainingDays(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    if (d == null) return 99999;
    return DateTime(d.year,d.month,d.day).difference(DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day)).inDays;
  }

  Future<String?> storeFile(String path, String prefix) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '';
      final target = File('${dir.path}/${prefix}_${DateTime.now().microsecondsSinceEpoch}$ext');
      await target.writeAsBytes(await File(path).readAsBytes(), flush: true);
      return target.path;
    } catch (_) { return path; }
  }

  Future<void> addVehicle([Map<String,dynamic>? existing]) async {
    final isEdit = existing != null;
    final formKey = GlobalKey<FormState>();
    final fields = <String,TextEditingController>{};
    final labels = <String,String>{
      'plate':'لوحة المركبة الهولندية','name':'اسم المركبة / الشركة المصنعة','type':'النوع (فان / شاحنة / باص)','model':'الموديل والسنة','color':'اللون','vin':'رقم الشاصي VIN','purchaseOdometer':'عداد الكيلومترات عند الشراء','cardNumber':'رقم كرت المركبة','status':'ملاحظات الحالة','purchasePrice':'قيمة الشراء (€)','monthlyInstallment':'القسط الشهري (€)','installmentDay':'يوم سداد القسط (1–31)','apkDate':'تاريخ انتهاء APK','oilAt':'آخر تغيير زيت عند كم','oilEvery':'تغيير الزيت كل كم','brakesAt':'آخر تغيير فحمات عند كم','brakesEvery':'تغيير الفحمات كل كم','plugsAt':'آخر تغيير بواجي عند كم','plugsEvery':'تغيير البواجي كل كم','tyreDate':'تاريخ آخر تغيير إطارات','tyreDue':'موعد تغيير الإطارات المتوقع'
    };
    for(final entry in labels.entries) fields[entry.key] = TextEditingController(text: existing?[entry.key]?.toString() ?? '');
    bool financed = existing?['financed'] == true;
    bool paid = existing?['paid'] == true;
    List<String> photos = List<String>.from(existing?['photos'] ?? []);
    List<Map<String,dynamic>> documents = (existing?['documents'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e)).toList();
    final pickedPhoto = ImagePicker();
    final result = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx,setModal) => Padding(
        padding: EdgeInsets.fromLTRB(18,8,18,MediaQuery.of(ctx).viewInsets.bottom+18),
        child: Form(key: formKey, child: ListView(shrinkWrap: true, children: [
          Text(isEdit ? 'تعديل بيانات المركبة' : 'إضافة مركبة جديدة', style: const TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
          const SizedBox(height:12),
          for(final entry in labels.entries)
            if (!['purchasePrice','monthlyInstallment','installmentDay'].contains(entry.key) || financed)
              Padding(padding: const EdgeInsets.only(bottom:8), child: TextFormField(
                controller: fields[entry.key],
                keyboardType: ['purchaseOdometer','purchasePrice','monthlyInstallment','installmentDay','oilAt','oilEvery','brakesAt','brakesEvery','plugsAt','plugsEvery'].contains(entry.key) ? const TextInputType.numberWithOptions(decimal:true) : TextInputType.text,
                decoration: InputDecoration(labelText: entry.value, border: const OutlineInputBorder(), prefixIcon: entry.key=='plate' ? const Icon(Icons.directions_car_filled) : null),
                validator: entry.key=='plate' ? (v)=>v==null||v.trim().isEmpty?'رقم اللوحة مطلوب':null : null,
              )),
          SwitchListTile(value: financed, onChanged:(v)=>setModal(()=>financed=v), title: const Text('المركبة مشتراة بالتقسيط')),
          if(financed) SwitchListTile(value: paid, onChanged:(v)=>setModal(()=>paid=v), title: const Text('تم سداد كامل قيمة المركبة')),
          const SizedBox(height:8),
          Text('صور المركبة',style:Theme.of(ctx).textTheme.titleMedium),
          Wrap(spacing:8,runSpacing:8,children:[
            for(int i=0;i<photos.length;i++) Stack(children:[
              if(File(photos[i]).existsSync()) ClipRRect(borderRadius:BorderRadius.circular(10),child:Image.file(File(photos[i]),width:90,height:80,fit:BoxFit.cover)) else const SizedBox(width:90,height:80,child:Icon(Icons.image_not_supported)),
              Positioned(right:0,top:0,child:IconButton(onPressed:()=>setModal(()=>photos.removeAt(i)),icon:const Icon(Icons.cancel,color:Colors.red)))
            ]),
            OutlinedButton.icon(onPressed:() async {final x=await pickedPhoto.pickMultiImage();for(final f in x){final p=await storeFile(f.path,'vehicle');if(p!=null)photos.add(p);}setModal((){});},icon:const Icon(Icons.add_a_photo),label:const Text('إضافة صور'))
          ]),
          const SizedBox(height:14),
          Row(children:[Expanded(child:Text('وثائق المركبة',style:Theme.of(ctx).textTheme.titleMedium)),TextButton.icon(onPressed:() async {final x=await FilePicker.platform.pickFiles(type:FileType.any);if(x!=null&&x.files.isNotEmpty){final f=x.files.single;String? p=f.path;if(p!=null)p=await storeFile(p,'vehicle_doc');documents.add({'name':f.name,'path':p??'', 'added':DateTime.now().toIso8601String()});setModal((){});}},icon:const Icon(Icons.attach_file),label:const Text('إرفاق'))]),
          for(int i=0;i<documents.length;i++) ListTile(dense:true,leading:const Icon(Icons.description),title:Text(documents[i]['name']?.toString()??'وثيقة'),subtitle:Text(documents[i]['path']?.toString()??''),trailing:IconButton(onPressed:()=>setModal(()=>documents.removeAt(i)),icon:const Icon(Icons.delete_outline,color:Colors.red))),
          const SizedBox(height:16),
          FilledButton.icon(onPressed:(){if(!formKey.currentState!.validate())return;Navigator.pop(ctx,true);},icon:const Icon(Icons.save),label:const Text('حفظ المركبة')),
        ])),
      )),
    );
    if(result != true) return;
    final data = <String,dynamic>{for(final e in fields.entries)e.key:e.value.text.trim(), 'financed':financed,'paid':paid,'photos':photos,'documents':documents};
    data['id'] = existing?['id'] ?? DateTime.now().microsecondsSinceEpoch.toString();
    data['created'] = existing?['created'] ?? DateTime.now().toIso8601String();
    if(existing==null) vehicles.add(data); else {final i=vehicles.indexWhere((v)=>v['id']==existing['id']);if(i>=0)vehicles[i]=data;}
    setState((){}); await save();
  }

  Future<void> deleteVehicle(Map<String,dynamic> v) async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('حذف المركبة؟'),content:Text('سيتم حذف سجل ${v['plate']} من هذا الهاتف.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف'))]));
    if(ok==true){setState(()=>vehicles.removeWhere((x)=>x['id']==v['id']));await save();}
  }

  Future<void> addRecord(Map<String,dynamic> vehicle,String kind) async {
    final title=TextEditingController(), amount=TextEditingController(), odo=TextEditingController(), notes=TextEditingController(), date=TextEditingController(text:DateTime.now().toIso8601String().substring(0,10));
    String? attachment;
    final labels={'fuel':'تعبئة وقود / AdBlue','maintenance':'صيانة / تغيير زيت أو قطع','repair':'إصلاح جديد','accident':'حادث','fine':'مخالفة','installment':'دفعة قسط'};
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setModal)=>AlertDialog(
      title:Text(labels[kind]??'سجل جديد'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:title,decoration:const InputDecoration(labelText:'النوع / العنوان')),
        TextField(controller:date,decoration:const InputDecoration(labelText:'التاريخ (YYYY-MM-DD)')),
        TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'التكلفة (€)')),
        if(kind=='fuel') TextField(controller:odo,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'قراءة العداد (كم)')),
        if(kind=='installment') TextField(controller:odo,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'رقم/شهر القسط أو قراءة العداد')),
        TextField(controller:notes,maxLines:3,decoration:const InputDecoration(labelText:'الوصف / تفاصيل العطل / المكان والوقت')),
        const SizedBox(height:8),
        OutlinedButton.icon(onPressed:()async{final f=await FilePicker.platform.pickFiles(type:FileType.any);if(f!=null&&f.files.isNotEmpty){attachment=f.files.single.path;setModal((){});}},icon:const Icon(Icons.attach_file),label:Text(attachment==null?'إرفاق فاتورة أو صورة':'تم إرفاق ملف'))
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ'))],
    )));
    if(ok!=true)return;
    final record=<String,dynamic>{'id':DateTime.now().microsecondsSinceEpoch.toString(),'kind':kind,'title':title.text.trim(),'date':date.text.trim(),'amount':double.tryParse(amount.text.replaceAll(',','.'))??0,'odometer':int.tryParse(odo.text),'notes':notes.text.trim(),'attachment':attachment,'paid':false,'created':DateTime.now().toIso8601String()};
    final records=List<Map<String,dynamic>>.from((vehicle['records'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e)));
    records.add(record);vehicle['records']=records;setState((){});await save();
  }

  Future<void> showRecords(Map<String,dynamic> v,String kind) async {
    final records=(v['records'] as List? ?? []).where((e)=>e is Map && e['kind']==kind).map((e)=>Map<String,dynamic>.from(e)).toList();
    final labels={'fuel':'الوقود و AdBlue','maintenance':'الصيانة وتغيير الزيت','repair':'الإصلاحات','accident':'الحوادث','fine':'المخالفات','installment':'أقساط المركبة'};
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,setModal)=>SafeArea(child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Row(children:[Expanded(child:Text(labels[kind]??kind,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))]),
      if(kind=='fuel') Text('تُحسب المسافة من قراءات العداد المسجلة.'),
      Flexible(child:ListView(shrinkWrap:true,children:[
        for(final r in records) Card(child:ListTile(leading:Icon(kind=='fuel'?Icons.local_gas_station:kind=='fine'?Icons.gavel:kind=='accident'?Icons.car_crash:Icons.build_circle),title:Text('${r['title']?.toString().isNotEmpty==true?r['title']:'سجل'} • €${(r['amount'] as num? ?? 0).toStringAsFixed(2)}'),subtitle:Text('${dateLabel(r['date'])} • عداد: ${r['odometer']??'—'} كم\n${r['notes']??''}'),isThreeLine:true,trailing:kind=='installment'?Checkbox(value:r['paid']==true,onChanged:(value)async{r['paid']=value==true;vehicle['records']=records;await save();setModal((){});setState((){});}):null,onLongPress:()async{final yes=await showDialog<bool>(context:ctx,builder:(c)=>AlertDialog(title:const Text('حذف السجل؟'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('حذف'))]));if(yes==true){final all=List<Map<String,dynamic>>.from((vehicle['records'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e)));all.removeWhere((x)=>x['id']==r['id']);vehicle['records']=all;await save();setModal((){});setState((){});}})),
      ])),
      const SizedBox(height:8),FilledButton.icon(onPressed:()=>addRecord(v,kind).then((_) {setModal((){});}),icon:const Icon(Icons.add),label:const Text('إضافة سجل')),
    ])))));
  }

  @override
  Widget build(BuildContext context) {
    final total = vehicles.length;
    return Scaffold(
      appBar:AppBar(title:const Text('المركبات',style:TextStyle(fontWeight:FontWeight.w800,color:vehicleBlue)),actions:[IconButton(onPressed:()=>addVehicle(),tooltip:'إضافة مركبة',icon:const Icon(Icons.add_circle_outline))]),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>addVehicle(),backgroundColor:vehicleOrange,foregroundColor:Colors.white,icon:const Icon(Icons.add),label:const Text('مركبة جديدة')),
      body:loading?const Center(child:CircularProgressIndicator()):vehicles.isEmpty?Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.directions_car_filled,size:68,color:vehicleBlue),const SizedBox(height:12),const Text('إدارة أسطول مركبات التوصيل',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('أضف المركبات ووثائقها ومواعيد الفحص والصيانة والأقساط والمصاريف.',textAlign:TextAlign.center),const SizedBox(height:16),FilledButton.icon(onPressed:null,icon:Icon(Icons.add),label:Text('ابدأ بإضافة مركبة'))]))):ListView(padding:const EdgeInsets.fromLTRB(12,8,12,100),children:[
        Card(color:vehicleBlue.withOpacity(.06),child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[const Icon(Icons.directions_car,color:vehicleBlue,size:30),const SizedBox(width:10),Expanded(child:Text('عدد المركبات: $total',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)))]))),
        for(final v in vehicles) Card(margin:const EdgeInsets.only(bottom:12),child:ExpansionTile(
          leading:CircleAvatar(backgroundColor:vehicleBlue.withOpacity(.1),child:const Icon(Icons.directions_car,color:vehicleBlue)),
          title:Text('${v['plate']??'لوحة غير محددة'}',style:const TextStyle(fontWeight:FontWeight.bold)),
          subtitle:Text('${v['name']??''} ${v['model']??''}\nAPK: ${dateLabel(v['apkDate'])}',maxLines:2),
          childrenPadding:const EdgeInsets.fromLTRB(14,0,14,14),
          children:[
            if((v['photos'] as List? ?? []).isNotEmpty) SizedBox(height:110,child:ListView(scrollDirection:Axis.horizontal,children:[for(final p in (v['photos'] as List)) Padding(padding:const EdgeInsets.only(right:8),child:File(p.toString()).existsSync()?ClipRRect(borderRadius:BorderRadius.circular(10),child:Image.file(File(p.toString()),width:140,height:100,fit:BoxFit.cover)):const SizedBox.shrink())])),
            Wrap(spacing:8,runSpacing:8,children:[
              _action('تعديل',Icons.edit,()=>addVehicle(v)),_action('حذف',Icons.delete_outline,()=>deleteVehicle(v)),
              _action('الوقود',Icons.local_gas_station,()=>showRecords(v,'fuel')),_action('الأقساط',Icons.payments,()=>showRecords(v,'installment')),
              _action('الصيانة',Icons.oil_barrel,()=>showRecords(v,'maintenance')),_action('الإصلاحات',Icons.build,()=>showRecords(v,'repair')),
              _action('الحوادث',Icons.car_crash,()=>showRecords(v,'accident')),_action('المخالفات',Icons.gavel,()=>showRecords(v,'fine')),
            ]),
            const Divider(),
            for(final pair in <String,String>{'النوع':'type','اللون':'color','VIN':'vin','رقم كرت المركبة':'cardNumber','عداد الشراء':'purchaseOdometer','حالة المركبة':'status'}.entries) if((v[pair.value]?.toString()??'').isNotEmpty) Align(alignment:Alignment.centerRight,child:Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Text('${pair.key}: ${v[pair.value]}'))),
            if(remainingDays(v['apkDate'])<=30) Container(margin:const EdgeInsets.only(top:8),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.orange.withOpacity(.12),borderRadius:BorderRadius.circular(10)),child:Row(children:[const Icon(Icons.notifications_active,color:Colors.deepOrange),const SizedBox(width:8),Expanded(child:Text(remainingDays(v['apkDate'])<0?'انتهى موعد APK — يرجى تجديده':remainingDays(v['apkDate'])==0?'موعد APK اليوم':'تبقى ${remainingDays(v['apkDate'])} يومًا على انتهاء APK'))])),
            if(v['financed']==true) Builder(builder:(ctx){final rec=(v['records'] as List? ?? []).where((e)=>e is Map&&e['kind']=='installment'&&e['paid']==true).fold<double>(0,(s,e)=>s+((e['amount'] as num?)?.toDouble()??0));final price=double.tryParse(v['purchasePrice']?.toString()??'')??0;return Column(children:[const SizedBox(height:8),LinearProgressIndicator(value:price>0?(rec/price).clamp(0,1):0),Text('المسدّد €${rec.toStringAsFixed(2)} من €${price.toStringAsFixed(2)} • المتبقي €${(price-rec).clamp(0,double.infinity).toStringAsFixed(2)}')]);}),
          ],
        ))
      ]),
    );
  }
  Widget _action(String label,IconData icon,VoidCallback onTap)=>ActionChip(avatar:Icon(icon,size:18),label:Text(label),onPressed:onTap);
}

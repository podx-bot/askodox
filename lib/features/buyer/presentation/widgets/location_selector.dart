import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/buyer_providers.dart';
import '../../domain/entities/buyer_models.dart';

class LocationSelector extends ConsumerWidget {
  const LocationSelector({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final location=ref.watch(buyerLocationProvider), radius=ref.watch(radiusKmProvider);
    return Card(child: ListTile(leading: const Icon(Icons.my_location), title: Text(location.label), subtitle: Text('${location.address} · ${_label(radius)}'), trailing: const Icon(Icons.tune), onTap: ()=>_show(context,ref)));
  }
  String _label(double km)=>km<1?'${(km*1000).round()} m':'${km.toStringAsFixed(km%1==0?0:1)} km';
  Future<void> _show(BuildContext context, WidgetRef ref) async {
    var custom=ref.read(radiusKmProvider);
    await showModalBottomSheet<void>(context: context,isScrollControlled:true,builder:(context)=>Consumer(builder:(context,ref,_) {
      final selected=ref.watch(buyerLocationProvider), radius=ref.watch(radiusKmProvider);
      return SafeArea(child: Padding(padding: const EdgeInsets.all(20),child: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Location & search radius',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
        const SizedBox(height:12),...ref.watch(buyerLocationsProvider).valueOrNull?.map((l)=>RadioListTile<BuyerLocation>(value:l,groupValue:selected,title:Text(l.label),subtitle:Text(l.address),onChanged:(v){if(v!=null) ref.read(buyerLocationProvider.notifier).state=v;}))??[],
        const Divider(),const Text('Search radius',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:6,children:SearchRadius.values.map((r)=>ChoiceChip(label:Text(r.label),selected:r==SearchRadius.custom ? !SearchRadius.values.where((e)=>e!=SearchRadius.custom).any((e)=>e.kilometres==radius) : r.kilometres==radius,onSelected:(_){if(r==SearchRadius.custom){ref.read(radiusKmProvider.notifier).state=custom;}else{ref.read(radiusKmProvider.notifier).state=r.kilometres;}})).toList()),
        const SizedBox(height:8),Row(children:[const Text('Adjust'),Expanded(child:Slider(min:.1,max:50,divisions:499,value:radius.clamp(.1,50).toDouble(),label:_label(radius),onChanged:(v){custom=v;ref.read(radiusKmProvider.notifier).state=v;}))]),
        SizedBox(width:double.infinity,child:FilledButton(onPressed:(){ref.read(buyerRepositoryProvider).saveDefaultRadius(ref.read(radiusKmProvider));Navigator.pop(context);},child:const Text('Save as default'))),
      ]))));
    }));
  }
}

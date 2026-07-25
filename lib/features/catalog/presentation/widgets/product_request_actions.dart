import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../buyer/application/buyer_providers.dart';
import '../../../buyer/domain/entities/buyer_models.dart';

class ProductRequestActions extends ConsumerWidget {
  const ProductRequestActions({this.compact=false,super.key}); final bool compact;
  @override Widget build(BuildContext context,WidgetRef ref){
    void show(String message)=>ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content:Text(message)));
    final request=FilledButton.icon(onPressed:(){ref.read(buyerRepositoryProvider).saveRequest(BuyerProductRequest(id:DateTime.now().microsecondsSinceEpoch.toString(),productName:'Requested product',createdAt:DateTime.now()));show('Product request saved locally.');},icon:const Icon(Icons.add_shopping_cart),label:const Text('Request Product'));
    final upload=OutlinedButton.icon(onPressed:()=>show('Product image upload is a placeholder.'),icon:const Icon(Icons.add_a_photo_outlined),label:const Text('Upload Product Image'));
    final watch=OutlinedButton.icon(onPressed:()=>show('Added to watchlist'),icon:const Icon(Icons.favorite_border),label:const Text('Add to Watchlist'));
    final notify=OutlinedButton.icon(onPressed:()=>show('Notifications enabled'),icon:const Icon(Icons.notifications_active_outlined),label:const Text('Notify Me'));
    final children=[request,upload,watch,notify]; return compact?Wrap(spacing:10,runSpacing:10,alignment:WrapAlignment.center,children:children):Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:children.expand((e)=>[e,const SizedBox(height:10)]).toList());
  }
}

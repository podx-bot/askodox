import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../buyer/application/buyer_providers.dart';
import '../../../buyer/domain/entities/buyer_models.dart';
import '../../domain/entities/product.dart';

class ProductCard extends ConsumerWidget {
  const ProductCard({required this.product,super.key}); final Product product;
  @override Widget build(BuildContext context,WidgetRef ref){
    final data=ref.watch(priceListingsProvider(product.id)); final location=ref.watch(buyerLocationProvider),radius=ref.watch(radiusKmProvider);
    final nearby=data.valueOrNull==null?<NearbySellerResult>[]:matchNearby(listings:data.valueOrNull!,location:location,radiusKm:radius,filter:const SearchFilter(),sort:SearchSortOption.nearestShop);
    final start=nearby.isEmpty?null:nearby.map((e)=>e.listing.effectivePrice).reduce((a,b)=>a<b?a:b);
    return Card(clipBehavior:Clip.antiAlias,child:InkWell(onTap:(){ref.read(recentSearchesProvider.notifier).state=[product.name,...ref.read(recentSearchesProvider).where((e)=>e!=product.name)].take(5).toList();context.push('/product/${product.id}');},child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(child:Container(width:double.infinity,color:Theme.of(context).colorScheme.primaryContainer.withOpacity(.65),child:Stack(children:[Center(child:Hero(tag:'product-${product.id}',child:Text(product.icon,style:const TextStyle(fontSize:54)))),Positioned(right:4,top:4,child:IconButton(tooltip:'Watchlist',onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Added to watchlist'))),icon:const Icon(Icons.favorite_border)))]))),
      Padding(padding:const EdgeInsets.all(10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(product.brand.name.toUpperCase(),style:Theme.of(context).textTheme.labelSmall?.copyWith(color:Theme.of(context).colorScheme.primary)),Text(product.name,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold)),Text(product.tags.take(2).join(' · '),maxLines:1,style:Theme.of(context).textTheme.bodySmall),const SizedBox(height:5),Text(nearby.isEmpty?'No shops in radius':'${nearby.length} shops · nearest ${nearby.first.distanceKm.toStringAsFixed(1)} km',style:Theme.of(context).textTheme.bodySmall),Text(start==null?'Price unavailable':'From ₹${start.toStringAsFixed(0)}',style:const TextStyle(fontWeight:FontWeight.w900)),SizedBox(width:double.infinity,child:TextButton(onPressed:()=>context.push('/product/${product.id}'),child:const Text('Compare prices')))]))
    ])));
  }
}

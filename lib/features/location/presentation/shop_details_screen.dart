import 'package:flutter/material.dart';

const _ink = Color(0xFF10204A);
const _blue = Color(0xFF1769FF);
const _muted = Color(0xFF6B7280);

class ShopDetailsScreen extends StatelessWidget {
  const ShopDetailsScreen({required this.shopId, super.key});
  final String shopId;

  String get name => switch (shopId) {
        'lakshmi-demo' => 'Sri Lakshmi Chicken Shop',
        'srinivas-demo' => 'Srinivas Chicken',
        _ => 'Prana Chicken Shop',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(title: const Text('ASKODOX'), actions: const [Icon(Icons.more_vert_rounded)]),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          Container(
            height: 180,
            color: const Color(0xFFFFECEC),
            child: const Center(child: Icon(Icons.set_meal_rounded, size: 110, color: Color(0xFFE97A7A))),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _ink))),
                    const Chip(label: Text('Open')),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('★ 4.6 (98)   •   1.2 km   •   Vuyyuru, AP', style: TextStyle(color: _muted)),
                const SizedBox(height: 8),
                const Text('Fresh & Hygienic Chicken', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
                const SizedBox(height: 10),
                const Wrap(spacing: 7, children: [Chip(label: Text('Fresh')), Chip(label: Text('Hygienic')), Chip(label: Text('Best Price'))]),
                const SizedBox(height: 18),
                const Text('Products', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
                const SizedBox(height: 10),
                const _ProductTile(name: 'Chicken (With Skin)', price: '₹220 / kg'),
                const _ProductTile(name: 'Chicken (Skinless)', price: '₹260 / kg'),
                const _ProductTile(name: 'Chicken Curry Cut', price: '₹200 / kg'),
                const _ProductTile(name: 'Chicken Liver', price: '₹180 / kg'),
                const _ProductTile(name: 'Chicken Boneless', price: '₹300 / kg'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SellerChatScreen(shopName: name))),
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('Discuss with Seller'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.bookmark_border_rounded), label: const Text('Save')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.name, required this.price});
  final String name;
  final String price;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFFFFECEC), child: Icon(Icons.set_meal_rounded, color: Color(0xFFE97A7A))),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(price, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      );
}

class SellerChatScreen extends StatefulWidget {
  const SellerChatScreen({required this.shopName, super.key});
  final String shopName;

  @override
  State<SellerChatScreen> createState() => _SellerChatScreenState();
}

class _SellerChatScreenState extends State<SellerChatScreen> {
  final controller = TextEditingController();
  final messages = <(bool, String)>[
    (false, 'Hello! Welcome. How can I help you today?'),
    (true, 'Skinless chicken 2 kg available?'),
    (false, 'Yes, available. Skinless chicken is ₹260/kg. 2 kg = ₹520.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.shopName), const Text('Online', style: TextStyle(fontSize: 11, color: Colors.green))])),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _ShopMiniCard(name: widget.shopName),
                const SizedBox(height: 12),
                for (final message in messages)
                  Align(
                    alignment: message.$1 ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: message.$1 ? _blue : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: message.$1 ? null : Border.all(color: const Color(0xFFE1E8F2)),
                      ),
                      child: Text(message.$2, style: TextStyle(color: message.$1 ? Colors.white : _ink)),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(label: const Text('Product details'), onPressed: () {}),
                    ActionChip(label: const Text('Available today?'), onPressed: () {}),
                    ActionChip(label: const Text('Shop location'), onPressed: () {}),
                    ActionChip(
                      label: const Text('Place request'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderRequestScreen(shopName: widget.shopName))),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  IconButton.filled(onPressed: () {}, style: IconButton.styleFrom(backgroundColor: const Color(0xFFFFC928)), icon: const Icon(Icons.mic_rounded, color: _ink)),
                  const SizedBox(width: 6),
                  Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Type a message…', border: OutlineInputBorder()))),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.image_outlined)),
                  IconButton.filled(
                    onPressed: () {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      setState(() => messages.add((true, text)));
                      controller.clear();
                    },
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopMiniCard extends StatelessWidget {
  const _ShopMiniCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFFFFECEC), child: Icon(Icons.storefront_rounded, color: Color(0xFFE97A7A))),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('★ 4.6 (98) • 1.2 km\nFresh & Hygienic Chicken'),
        ),
      );
}

class OrderRequestScreen extends StatefulWidget {
  const OrderRequestScreen({required this.shopName, super.key});
  final String shopName;

  @override
  State<OrderRequestScreen> createState() => _OrderRequestScreenState();
}

class _OrderRequestScreenState extends State<OrderRequestScreen> {
  int quantity = 2;
  bool selfPickup = false;

  @override
  Widget build(BuildContext context) {
    final total = quantity * 260;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(title: const Text('ASKODOX')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ShopMiniCard(name: widget.shopName),
          const SizedBox(height: 14),
          const Text('What do you need?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 10),
          const _ProductTile(name: 'Chicken (Skinless)', price: '₹260 / kg'),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton.outlined(onPressed: quantity > 1 ? () => setState(() => quantity--) : null, icon: const Icon(Icons.remove)),
              Text('$quantity kg', style: const TextStyle(fontWeight: FontWeight.w900)),
              IconButton.outlined(onPressed: () => setState(() => quantity++), icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Self pickup'),
            subtitle: const Text('Turn on only if you want to collect the order yourself.'),
            value: selfPickup,
            onChanged: (value) => setState(() => selfPickup = value),
          ),
          const SizedBox(height: 6),
          Text('Order total: ₹$total', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => DeliveryFlowScreen(shopName: widget.shopName, amount: total, selfPickup: selfPickup)),
            ),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Place Order')),
          ),
        ],
      ),
    );
  }
}

class DeliveryFlowScreen extends StatefulWidget {
  const DeliveryFlowScreen({required this.shopName, required this.amount, required this.selfPickup, super.key});
  final String shopName;
  final int amount;
  final bool selfPickup;

  @override
  State<DeliveryFlowScreen> createState() => _DeliveryFlowScreenState();
}

class _DeliveryFlowScreenState extends State<DeliveryFlowScreen> {
  int step = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.selfPickup) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted && step == 0) setState(() => step = 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(title: const Text('ASKODOX')),
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _body()),
    );
  }

  Widget _body() {
    if (widget.selfPickup) return _selfPickup();
    return switch (step) {
      0 => _checking(),
      1 => _accepted(),
      2 => _payment(),
      3 => _paid(),
      4 => _ready(),
      5 => _tracking(),
      _ => _delivered(),
    };
  }

  Widget _frame({required IconData icon, required Color color, required String title, required String subtitle, required List<Widget> children}) => ListView(
        key: ValueKey(title),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 35),
          CircleAvatar(radius: 42, backgroundColor: color.withOpacity(.12), child: Icon(icon, size: 48, color: color)),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: _muted, height: 1.4)),
          const SizedBox(height: 24),
          ...children,
        ],
      );

  Widget _checking() => _frame(
        icon: Icons.hourglass_top_rounded,
        color: _blue,
        title: 'Order placed',
        subtitle: 'Please wait. We are checking who can deliver your order nearby. No payment is taken yet.',
        children: const [
          _StatusRow(done: true, text: 'Order placed'),
          _StatusRow(active: true, text: 'Checking delivery availability…'),
          _StatusRow(text: 'Waiting for someone to accept'),
          _StatusRow(text: 'Payment will open only after delivery is accepted'),
        ],
      );

  Widget _accepted() => _frame(
        icon: Icons.check_circle_rounded,
        color: Colors.green,
        title: 'Delivery accepted!',
        subtitle: 'A delivery person has accepted the job. You can now pay the seller directly.',
        children: [
          Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.delivery_dining_rounded)), title: const Text('Nearby delivery person'), subtitle: const Text('Accepted • Expected 30–45 min'))),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => setState(() => step = 2), child: const Text('Proceed to Seller QR Payment')),
        ],
      );

  Widget _payment() => _frame(
        icon: Icons.qr_code_2_rounded,
        color: _blue,
        title: 'Pay Seller Directly',
        subtitle: 'Scan the seller QR and pay directly. ASKODOX does not hold your money.',
        children: [
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F2))),
              child: const Icon(Icons.qr_code_2_rounded, size: 180, color: Colors.black),
            ),
          ),
          const SizedBox(height: 14),
          Text('${widget.shopName}\nAmount ₹${widget.amount}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => setState(() => step = 3), child: const Text('I Have Paid • Confirm Payment')),
        ],
      );

  Widget _paid() => _frame(
        icon: Icons.verified_rounded,
        color: Colors.green,
        title: 'Payment confirmed',
        subtitle: 'The seller can now prepare your order.',
        children: [
          _StatusRow(done: true, text: 'Delivery accepted'),
          _StatusRow(done: true, text: 'Seller payment confirmed'),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => setState(() => step = 4), child: const Text('Continue')),
        ],
      );

  Widget _ready() => _frame(
        icon: Icons.storefront_rounded,
        color: Colors.orange,
        title: 'Order ready',
        subtitle: 'Your order is ready and the delivery person is picking it up.',
        children: [
          const _StatusRow(done: true, text: 'Payment confirmed'),
          const _StatusRow(done: true, text: 'Order prepared'),
          const _StatusRow(active: true, text: 'Picked up for delivery'),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => setState(() => step = 5), child: const Text('Track Delivery')),
        ],
      );

  Widget _tracking() => _frame(
        icon: Icons.map_rounded,
        color: _blue,
        title: 'Your order is on the way',
        subtitle: 'Arriving in about 12 minutes.',
        children: [
          Container(height: 240, decoration: BoxDecoration(color: const Color(0xFFE8F2E8), borderRadius: BorderRadius.circular(20)), child: const Center(child: Icon(Icons.delivery_dining_rounded, size: 74, color: _blue))),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => setState(() => step = 6), child: const Text('Mark Demo Delivered')),
        ],
      );

  Widget _delivered() => _frame(
        icon: Icons.check_circle_rounded,
        color: Colors.green,
        title: 'Order delivered!',
        subtitle: 'Hope you are satisfied.',
        children: [
          FilledButton(onPressed: () {}, child: const Text('Rate & Review')),
          OutlinedButton(onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst), child: const Text('Done')),
        ],
      );

  Widget _selfPickup() => _frame(
        icon: Icons.storefront_rounded,
        color: _blue,
        title: 'Self Pickup',
        subtitle: 'You chose to collect the order yourself. No delivery person is required.',
        children: [
          Card(child: ListTile(leading: const Icon(Icons.location_on_rounded), title: Text(widget.shopName), subtitle: const Text('Vuyyuru, AP • Open in Maps'))),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => setState(() => step = 2), child: const Text('Pay Seller QR')),
        ],
      );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.text, this.done = false, this.active = false});
  final String text;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(done ? Icons.check_circle_rounded : active ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: done ? Colors.green : active ? _blue : _muted),
        title: Text(text, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
      );
}

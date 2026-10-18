import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The ASKODOX mascot team (owner's character sheet, assets/mascots/):
/// ASKO is the assistant (with expressions); each role has its teammate.
enum AskodoxMascotRole { asko, onbo, progo, acti, suppo, rido, delo, listo, bizzo, studio, growo, entro }

/// ASKO's expressions -- chosen by the situation, never at random.
enum AskodoxMascotMood { happy, thinking, typing, listening, excited, confused, success, love, sleepy }

/// A small, friendly mascot. When it appears or its mood changes it pops in,
/// floats gently for a few seconds and blinks (a quick squash), then rests --
/// it never animates forever (battery, and screens stay calm).
class AskodoxMascot extends StatefulWidget {
  const AskodoxMascot({
    super.key,
    this.role = AskodoxMascotRole.asko,
    this.mood = AskodoxMascotMood.happy,
    this.size = 40,
    this.circle = true,
  });

  final AskodoxMascotRole role;
  final AskodoxMascotMood mood;
  final double size;
  final bool circle;

  static String assetFor(AskodoxMascotRole role, AskodoxMascotMood mood) => role == AskodoxMascotRole.asko
      ? (mood == AskodoxMascotMood.happy ? 'assets/mascots/asko.png' : 'assets/mascots/${mood.name}.png')
      : 'assets/mascots/${role.name}.png';

  @override
  State<AskodoxMascot> createState() => _AskodoxMascotState();
}

class _AskodoxMascotState extends State<AskodoxMascot> with SingleTickerProviderStateMixin {
  // One "performance": pop in, three gentle floats with two blinks, rest.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didUpdateWidget(AskodoxMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood || old.role != widget.role) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = AskodoxMascot.assetFor(widget.role, widget.mood);
    final image = Image.asset(asset,
        key: ValueKey('askodoxMascot-${asset.split('/').last.split('.').first}'),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.smart_toy_rounded, size: widget.size * .8, color: const Color(0xFF1769FF)));
    final clipped = widget.circle
        ? ClipOval(child: image)
        : ClipRRect(borderRadius: BorderRadius.circular(widget.size * .22), child: image);
    return AnimatedBuilder(
      animation: _c,
      child: clipped,
      builder: (context, child) {
        final t = _c.value;
        // Pop in (first 15 %), then float, with blinks at 45 % and 80 %.
        final pop = t < .15 ? Curves.easeOutBack.transform(t / .15) : 1.0;
        final float = t < .15 ? 0.0 : math.sin((t - .15) / .85 * math.pi * 6) * (1 - t) * widget.size * .05;
        double blink(double at) => (t - at).abs() < .02 ? .9 : 1.0;
        final squash = blink(.45) * blink(.8);
        return Transform.translate(
          offset: Offset(0, -float),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(pop * (2 - squash), pop * squash, 1),
            child: child,
          ),
        );
      },
    );
  }
}

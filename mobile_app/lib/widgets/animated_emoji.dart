import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Utility to detect if a text contains solely emojis
class EmojiUtils {
  static final RegExp _emojiRegex = RegExp(
    r'^(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]|\ufe0f|\u200d)+$',
  );

  /// Check if the trimmed text consists entirely of emojis (and no regular letters or numbers)
  static bool isOnlyEmojis(String text) {
    final trimmed = text.trim().replaceAll(' ', '');
    if (trimmed.isEmpty) return false;
    if (RegExp(r'[a-zA-Z0-9]').hasMatch(trimmed)) return false;
    return _emojiRegex.hasMatch(trimmed);
  }

  /// Count the number of emojis in an emoji-only string
  static int emojiCount(String text) {
    final trimmed = text.trim().replaceAll(' ', '');
    return trimmed.characters.length;
  }
}

/// WhatsApp-style Animated Emoji with smooth 60fps GPU Skia transforms
class AnimatedEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  final bool animateLoop;
  final VoidCallback? onTap;

  const AnimatedEmoji({
    super.key,
    required this.emoji,
    this.size = 38.0,
    this.animateLoop = true,
    this.onTap,
  });

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<AnimatedEmoji> with TickerProviderStateMixin {
  late AnimationController _loopController;
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _translationAnimation;
  late _EmojiAnimType _animType;

  @override
  void initState() {
    super.initState();
    _animType = _getAnimationType(widget.emoji);
    final duration = _getDuration(_animType);

    _loopController = AnimationController(
      vsync: this,
      duration: duration,
    );

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _setupAnimations(_animType);

    if (widget.animateLoop) {
      _startLoopAnimation(_animType);
    }
  }

  _EmojiAnimType _getAnimationType(String emoji) {
    if (emoji.contains('❤️') || emoji.contains('💖') || emoji.contains('💕') || emoji.contains('💓') || emoji.contains('💗') || emoji.contains('💘') || emoji.contains('💞')) {
      return _EmojiAnimType.heartbeat;
    } else if (emoji.contains('😂') || emoji.contains('🤣') || emoji.contains('😆') || emoji.contains('😜') || emoji.contains('😝') || emoji.contains('🤪')) {
      return _EmojiAnimType.bounceWiggle;
    } else if (emoji.contains('🔥') || emoji.contains('⚡') || emoji.contains('💥')) {
      return _EmojiAnimType.pulseGlow;
    } else if (emoji.contains('🚀') || emoji.contains('🎈') || emoji.contains('🛸') || emoji.contains('👻')) {
      return _EmojiAnimType.floating;
    } else if (emoji.contains('👍') || emoji.contains('👏') || emoji.contains('🙌') || emoji.contains('🎉') || emoji.contains('🥳')) {
      return _EmojiAnimType.popScale;
    }
    return _EmojiAnimType.subtleBreath;
  }

  Duration _getDuration(_EmojiAnimType type) {
    switch (type) {
      case _EmojiAnimType.heartbeat:
        return const Duration(milliseconds: 950); // Exact WhatsApp heartbeat cadence
      case _EmojiAnimType.bounceWiggle:
        return const Duration(milliseconds: 1100);
      case _EmojiAnimType.pulseGlow:
        return const Duration(milliseconds: 900);
      case _EmojiAnimType.floating:
        return const Duration(milliseconds: 1800);
      case _EmojiAnimType.popScale:
        return const Duration(milliseconds: 1200);
      case _EmojiAnimType.subtleBreath:
        return const Duration(milliseconds: 1500);
    }
  }

  void _setupAnimations(_EmojiAnimType type) {
    switch (type) {
      case _EmojiAnimType.heartbeat:
        // Realistic "lub-dub ... pause" physiological heartbeat rhythm
        _scaleAnimation = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.16).chain(CurveTween(curve: Curves.easeOutQuad)), weight: 12),
          TweenSequenceItem(tween: Tween(begin: 1.16, end: 1.04).chain(CurveTween(curve: Curves.easeInQuad)), weight: 8),
          TweenSequenceItem(tween: Tween(begin: 1.04, end: 1.18).chain(CurveTween(curve: Curves.easeOutQuad)), weight: 13),
          TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 22),
          TweenSequenceItem(tween: ConstantTween(1.0), weight: 45), // Resting pause
        ]).animate(_loopController);
        _rotationAnimation = const AlwaysStoppedAnimation(0.0);
        _translationAnimation = const AlwaysStoppedAnimation(0.0);
        break;

      case _EmojiAnimType.bounceWiggle:
        // Subtle, realistic giggle bounce
        _scaleAnimation = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
          TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 70),
        ]).animate(_loopController);
        _rotationAnimation = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.015).chain(CurveTween(curve: Curves.easeInOut)), weight: 25),
          TweenSequenceItem(tween: Tween(begin: -0.015, end: 0.015).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
          TweenSequenceItem(tween: Tween(begin: 0.015, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 25),
        ]).animate(_loopController);
        _translationAnimation = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: -3.5).chain(CurveTween(curve: Curves.easeOutQuad)), weight: 35),
          TweenSequenceItem(tween: Tween(begin: -3.5, end: 0.0).chain(CurveTween(curve: Curves.bounceOut)), weight: 65),
        ]).animate(_loopController);
        break;

      case _EmojiAnimType.pulseGlow:
        // Natural thermal flame breathing
        _scaleAnimation = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.98, end: 1.08).chain(CurveTween(curve: Curves.easeInOutSine)), weight: 50),
          TweenSequenceItem(tween: Tween(begin: 1.08, end: 0.98).chain(CurveTween(curve: Curves.easeInOutSine)), weight: 50),
        ]).animate(_loopController);
        _rotationAnimation = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: -0.01, end: 0.01).chain(CurveTween(curve: Curves.easeInOutSine)), weight: 50),
          TweenSequenceItem(tween: Tween(begin: 0.01, end: -0.01).chain(CurveTween(curve: Curves.easeInOutSine)), weight: 50),
        ]).animate(_loopController);
        _translationAnimation = Tween<double>(begin: 0.0, end: -1.5).animate(
          CurvedAnimation(parent: _loopController, curve: Curves.easeInOut),
        );
        break;

      case _EmojiAnimType.floating:
        // Gentle atmospheric float
        _scaleAnimation = const AlwaysStoppedAnimation(1.0);
        _rotationAnimation = Tween<double>(begin: -0.02, end: 0.02).animate(
          CurvedAnimation(parent: _loopController, curve: Curves.easeInOut),
        );
        _translationAnimation = Tween<double>(begin: 0.0, end: -4.0).animate(
          CurvedAnimation(parent: _loopController, curve: Curves.easeInOut),
        );
        break;

      case _EmojiAnimType.popScale:
        _scaleAnimation = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.10).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
          TweenSequenceItem(tween: Tween(begin: 1.10, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 70),
        ]).animate(_loopController);
        _rotationAnimation = const AlwaysStoppedAnimation(0.0);
        _translationAnimation = const AlwaysStoppedAnimation(0.0);
        break;

      case _EmojiAnimType.subtleBreath:
        _scaleAnimation = Tween<double>(begin: 0.98, end: 1.03).animate(
          CurvedAnimation(parent: _loopController, curve: Curves.easeInOutSine),
        );
        _rotationAnimation = const AlwaysStoppedAnimation(0.0);
        _translationAnimation = const AlwaysStoppedAnimation(0.0);
        break;
    }
  }

  void _startLoopAnimation(_EmojiAnimType type) {
    if (type == _EmojiAnimType.floating || type == _EmojiAnimType.subtleBreath || type == _EmojiAnimType.pulseGlow) {
      _loopController.repeat(reverse: true);
    } else {
      _loopController.repeat();
    }
  }

  void _handleTap() {
    _tapController.forward(from: 0.0).then((_) {
      _tapController.reverse();
    });
    if (widget.onTap != null) {
      widget.onTap!();
    }
  }

  @override
  void dispose() {
    _loopController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge([_loopController, _tapController]),
        builder: (context, child) {
          final tapScale = 1.0 + (_tapController.value * 0.25);
          final loopScale = _scaleAnimation.value;
          final totalScale = loopScale * tapScale;

          return Transform.translate(
            offset: Offset(0, _translationAnimation.value),
            child: Transform.rotate(
              angle: _rotationAnimation.value * math.pi,
              child: Transform.scale(
                scale: totalScale,
                child: child,
              ),
            ),
          );
        },
        child: Text(
          widget.emoji,
          style: TextStyle(
            fontSize: widget.size,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}

enum _EmojiAnimType {
  heartbeat,
  bounceWiggle,
  pulseGlow,
  floating,
  popScale,
  subtleBreath,
}

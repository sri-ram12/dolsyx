import 'package:flutter/material.dart';

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

/// WhatsApp-style Animated Emoji with expressive pop/pulse motion and no tilting
class AnimatedEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  final bool animateLoop;
  final VoidCallback? onTap;

  const AnimatedEmoji({
    super.key,
    required this.emoji,
    this.size = 38.0,
    this.animateLoop = false,
    this.onTap,
  });

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<AnimatedEmoji> with TickerProviderStateMixin {
  late AnimationController _loopController;
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _tapScaleAnimation;

  bool _isHeart = false;
  bool _isLaughing = false;
  bool _isCrying = false;

  @override
  void initState() {
    super.initState();

    _isHeart = widget.emoji.contains('❤️') ||
        widget.emoji.contains('💖') ||
        widget.emoji.contains('💕') ||
        widget.emoji.contains('💓') ||
        widget.emoji.contains('💗') ||
        widget.emoji.contains('💘') ||
        widget.emoji.contains('💞');

    _isLaughing = widget.emoji.contains('😂') ||
        widget.emoji.contains('🤣') ||
        widget.emoji.contains('😅') ||
        widget.emoji.contains('😆') ||
        widget.emoji.contains('😄');

    _isCrying = widget.emoji.contains('😭') ||
        widget.emoji.contains('😢') ||
        widget.emoji.contains('🥺') ||
        widget.emoji.contains('😿');

    _loopController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _isHeart ? 950 : (_isLaughing ? 700 : 900)),
    );

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    if (_isHeart) {
      _scaleAnimation = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18).chain(CurveTween(curve: Curves.easeOutQuad)), weight: 15),
        TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.05).chain(CurveTween(curve: Curves.easeInQuad)), weight: 10),
        TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.22).chain(CurveTween(curve: Curves.easeOutQuad)), weight: 15),
        TweenSequenceItem(tween: Tween(begin: 1.22, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 25),
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 35),
      ]).animate(_loopController);
    } else if (_isLaughing) {
      _scaleAnimation = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeOutBack)), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.95).chain(CurveTween(curve: Curves.easeInOutQuad)), weight: 25),
        TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.15).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 25),
        TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 20),
      ]).animate(_loopController);
    } else if (_isCrying) {
      _scaleAnimation = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12).chain(CurveTween(curve: Curves.easeInQuad)), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 1.12, end: 0.96).chain(CurveTween(curve: Curves.easeOutQuad)), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 40),
      ]).animate(_loopController);
    } else {
      _scaleAnimation = const AlwaysStoppedAnimation(1.0);
    }

    _tapScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.45).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.45, end: 0.92).chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.92, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 35,
      ),
    ]).animate(_tapController);

    if (widget.animateLoop && (_isHeart || _isLaughing || _isCrying)) {
      _loopController.repeat();
    }
  }

  void _handleTap() {
    _tapController.forward(from: 0.0);
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
          final loopScale = _scaleAnimation.value;
          final tapScale = _tapController.isAnimating ? _tapScaleAnimation.value : 1.0;
          final totalScale = loopScale * tapScale;

          return Transform.scale(
            scale: totalScale,
            child: child,
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


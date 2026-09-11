import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Emotion categories for the emoji interaction engine
enum EmojiEmotionCategory {
  heart,
  laugh,
  loveEyes,
  angry,
  cry,
  celebrate,
  fire,
  thumbs,
  clap,
  animal,
  food,
  generic,
}

/// Registry mapping emojis to high-definition animated WebP assets (Google Noto / WhatsApp style)
class EmojiAnimationRegistry {
  static final Map<String, String> _urlMap = {
    // Hearts & Love
    '❤️': 'https://fonts.gstatic.com/s/e/notoemoji/latest/2764_fe0f/512.webp',
    '🧡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f9e1/512.webp',
    '💛': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49b/512.webp',
    '💚': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49a/512.webp',
    '💙': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f499/512.webp',
    '💜': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49c/512.webp',
    '🖤': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f5a4/512.webp',
    '🤍': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f90d/512.webp',
    '🤎': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f90e/512.webp',
    '💔': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f494/512.webp',
    '💖': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f496/512.webp',
    '💗': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f497/512.webp',
    '💓': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f493/512.webp',
    '💞': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49e/512.webp',
    '💕': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f495/512.webp',
    '💘': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f498/512.webp',
    '💝': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f49d/512.webp',

    // Laughing / Joy
    '😂': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f602/512.webp',
    '🤣': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f923/512.webp',
    '😆': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f606/512.webp',
    '😅': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f605/512.webp',
    '😄': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f604/512.webp',
    '😃': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f603/512.webp',
    '😀': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f600/512.webp',
    '😁': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f601/512.webp',

    // Love-Struck / Affection
    '😍': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60d/512.webp',
    '🥰': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f970/512.webp',
    '😘': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f618/512.webp',
    '😗': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f617/512.webp',
    '😙': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f619/512.webp',
    '😚': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f61a/512.webp',

    // Anger / Rage
    '😡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f621/512.webp',
    '🤬': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92c/512.webp',
    '😠': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f620/512.webp',
    '😤': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f624/512.webp',

    // Cry / Sadness
    '😭': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f62d/512.webp',
    '😢': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f622/512.webp',
    '🥺': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f97a/512.webp',
    '😥': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f625/512.webp',
    '😓': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f613/512.webp',

    // Celebration / Party
    '🎉': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f389/512.webp',
    '🥳': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f973/512.webp',
    '🎊': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f38a/512.webp',
    '🏆': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f3c6/512.webp',

    // Fire / Energy
    '🔥': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f525/512.webp',
    '⚡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/26a1/512.webp',
    '💥': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a5/512.webp',
    '✨': 'https://fonts.gstatic.com/s/e/notoemoji/latest/2728/512.webp',
    '⭐': 'https://fonts.gstatic.com/s/e/notoemoji/latest/2b50/512.webp',
    '🌟': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f31f/512.webp',
    '💯': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f4af/512.webp',

    // Hands / Gestures
    '👍': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f44d/512.webp',
    '👎': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f44e/512.webp',
    '👏': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f44f/512.webp',
    '🙌': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f64c/512.webp',
    '🙏': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f64f/512.webp',
    '🤝': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f91d/512.webp',
    '👌': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f44c/512.webp',
    '✌️': 'https://fonts.gstatic.com/s/e/notoemoji/latest/270c_fe0f/512.webp',

    // Expressive Faces from WhatsApp/demovideo
    '🥵': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f975/512.webp',
    '🥶': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f976/512.webp',
    '😳': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f633/512.webp',
    '🤢': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f922/512.webp',
    '🤮': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92e/512.webp',
    '😫': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f62b/512.webp',
    '😩': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f629/512.webp',
    '🤤': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f924/512.webp',
    '🤐': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f910/512.webp',
    '😮‍💨': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f62e_200d_1f4a8/512.webp',
    '😴': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f634/512.webp',
    '🥱': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f971/512.webp',
    '🤯': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92f/512.webp',
    '😱': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f631/512.webp',
    '🤔': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f914/512.webp',
    '🫡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1fae1/512.webp',
    '🫠': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1fae0/512.webp',
    '🤫': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92b/512.webp',
    '🤭': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92d/512.webp',
    '🙄': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f644/512.webp',
    '😎': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60e/512.webp',
    '🤓': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f913/512.webp',
    '🧐': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f9d0/512.webp',
    '😉': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f609/512.webp',
    '😊': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60a/512.webp',
    '😇': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f607/512.webp',
    '🙂': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f642/512.webp',
    '🙃': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f643/512.webp',
    '😋': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60b/512.webp',
    '😜': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f61c/512.webp',
    '🤪': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f92a/512.webp',
    '😝': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f61d/512.webp',
    '😛': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f61b/512.webp',
    '🤑': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f911/512.webp',
    '🤗': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f917/512.webp',
    '🤡': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f921/512.webp',
    '💩': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a9/512.webp',
    '👻': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f47b/512.webp',
    '💀': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f480/512.webp',
    '👽': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f47d/512.webp',
    '🤖': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f916/512.webp',
    '🐶': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f436/512.webp',
    '🐱': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f431/512.webp',
    '🍕': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f355/512.webp',
    '🍔': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f354/512.webp',
  };

  /// Returns the animated WebP URL for an emoji or generates one from its unicode codepoints
  static String? getAnimatedEmojiUrl(String emoji) {
    final clean = emoji.trim();
    if (_urlMap.containsKey(clean)) {
      return _urlMap[clean];
    }

    final runes = clean.runes.toList();
    if (runes.isNotEmpty) {
      // Exclude 0xfe0f if not heart
      final hexList = clean == '❤️'
          ? ['2764', 'fe0f']
          : runes.where((r) => r != 0xfe0f).map((r) => r.toRadixString(16)).toList();
      return 'https://fonts.gstatic.com/s/e/notoemoji/latest/${hexList.join('_')}/512.webp';
    }
    return null;
  }

  /// Returns the static PNG URL for an emoji for stable, crystal-clear idle rendering
  static String? getStaticEmojiUrl(String emoji) {
    final animUrl = getAnimatedEmojiUrl(emoji);
    if (animUrl != null) {
      return animUrl.replaceAll('/512.webp', '/512.png');
    }
    return null;
  }
}

/// Utility to detect if a text contains solely emojis
class EmojiUtils {
  static final RegExp _emojiRegex = RegExp(
    r'^(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]|\ufe0f|\u200d)+$',
  );

  /// Check if the trimmed text consists entirely of emojis
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

  /// Detect the emotional category of an emoji
  static EmojiEmotionCategory detectCategory(String emoji) {
    if (RegExp(r'❤️|🧡|💛|💚|💙|💜|🖤|🤍|🤎|💖|💗|💓|💞|💕|💘|💝|💟|💌').hasMatch(emoji)) {
      return EmojiEmotionCategory.heart;
    }
    if (RegExp(r'😂|🤣|😹|😆|😸').hasMatch(emoji)) {
      return EmojiEmotionCategory.laugh;
    }
    if (RegExp(r'😍|🥰|😘|😻|😚|😙').hasMatch(emoji)) {
      return EmojiEmotionCategory.loveEyes;
    }
    if (RegExp(r'😡|🤬|👿|💢|😠|😤|👺').hasMatch(emoji)) {
      return EmojiEmotionCategory.angry;
    }
    if (RegExp(r'😭|😢|🥺|😿|😥|😓').hasMatch(emoji)) {
      return EmojiEmotionCategory.cry;
    }
    if (RegExp(r'🎉|🥳|🎊|🏆|🍾|🎆|🎇|✨').hasMatch(emoji)) {
      return EmojiEmotionCategory.celebrate;
    }
    if (RegExp(r'🔥|⚡|💥|⭐|🌟|💫').hasMatch(emoji)) {
      return EmojiEmotionCategory.fire;
    }
    if (RegExp(r'👍|🤝|👌|🤙|✌️|🤞').hasMatch(emoji)) {
      return EmojiEmotionCategory.thumbs;
    }
    if (RegExp(r'👏|🙌|👐').hasMatch(emoji)) {
      return EmojiEmotionCategory.clap;
    }
    if (RegExp(r'🐶|🐱|🦊|🐻|🐼|🐨|🐯|🦁|🐰|🐹|🐭|🐵|🐺').hasMatch(emoji)) {
      return EmojiEmotionCategory.animal;
    }
    if (RegExp(r'🍕|🍔|🍩|🍎|🍟|🌮|🍣|🍰|🍦|🥞|🍿|🍉|🍓|🍫').hasMatch(emoji)) {
      return EmojiEmotionCategory.food;
    }
    return EmojiEmotionCategory.generic;
  }
}

/// WhatsApp/Telegram-style Animated Emoji with real animated vector/WebP rendering and responsive physics
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

class _AnimatedEmojiState extends State<AnimatedEmoji> with SingleTickerProviderStateMixin {
  late AnimationController _tapController;

  late EmojiEmotionCategory _category;
  String? _animatedUrl;
  String? _staticUrl;
  bool _isTappedActive = false;

  @override
  void initState() {
    super.initState();
    _category = EmojiUtils.detectCategory(widget.emoji);
    _animatedUrl = EmojiAnimationRegistry.getAnimatedEmojiUrl(widget.emoji);
    _staticUrl = EmojiAnimationRegistry.getStaticEmojiUrl(widget.emoji);

    final duration = _getEmotionDuration(_category);
    _tapController = AnimationController(
      vsync: this,
      duration: duration,
    );

    _tapController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _isTappedActive = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji != widget.emoji) {
      _category = EmojiUtils.detectCategory(widget.emoji);
      _animatedUrl = EmojiAnimationRegistry.getAnimatedEmojiUrl(widget.emoji);
      _staticUrl = EmojiAnimationRegistry.getStaticEmojiUrl(widget.emoji);
      _tapController.duration = _getEmotionDuration(_category);
    }
  }

  Duration _getEmotionDuration(EmojiEmotionCategory category) {
    switch (category) {
      case EmojiEmotionCategory.heart:
        return const Duration(milliseconds: 1400);
      case EmojiEmotionCategory.laugh:
        return const Duration(milliseconds: 1600);
      case EmojiEmotionCategory.loveEyes:
        return const Duration(milliseconds: 1500);
      case EmojiEmotionCategory.angry:
        return const Duration(milliseconds: 1200);
      case EmojiEmotionCategory.cry:
        return const Duration(milliseconds: 1600);
      case EmojiEmotionCategory.celebrate:
        return const Duration(milliseconds: 1800);
      case EmojiEmotionCategory.fire:
        return const Duration(milliseconds: 1400);
      default:
        return const Duration(milliseconds: 1200);
    }
  }

  void _triggerHaptic() {
    switch (_category) {
      case EmojiEmotionCategory.heart:
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 140), () {
          HapticFeedback.lightImpact();
        });
        break;
      case EmojiEmotionCategory.angry:
        HapticFeedback.heavyImpact();
        break;
      case EmojiEmotionCategory.celebrate:
      case EmojiEmotionCategory.fire:
        HapticFeedback.mediumImpact();
        break;
      case EmojiEmotionCategory.clap:
      case EmojiEmotionCategory.laugh:
      default:
        HapticFeedback.lightImpact();
        break;
    }
  }

  void _handleTap() {
    _triggerHaptic();

    if (mounted) {
      setState(() {
        _isTappedActive = true;
      });
    }

    _tapController.forward(from: 0.0);

    if (widget.onTap != null) {
      widget.onTap!();
    }
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  Widget _buildEmojiVisual() {
    if (_animatedUrl != null && _staticUrl != null) {
      final isPlaying = widget.animateLoop || _isTappedActive;

      return Stack(
        alignment: Alignment.center,
        children: [
          // 1. Rock-solid static high-res graphic (stable in one place, zero layout shift)
          CachedNetworkImage(
            imageUrl: _staticUrl!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            fadeInDuration: const Duration(milliseconds: 60),
            placeholder: (context, url) => Text(
              widget.emoji,
              style: TextStyle(
                fontSize: widget.size * 0.88,
                height: 1.15,
              ),
            ),
            errorWidget: (context, url, error) => Text(
              widget.emoji,
              style: TextStyle(
                fontSize: widget.size * 0.88,
                height: 1.15,
              ),
            ),
          ),

          // 2. Animated WebP character behavior (active when tapped or looping, no zooming)
          if (isPlaying)
            CachedNetworkImage(
              imageUrl: _animatedUrl!,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              fadeInDuration: const Duration(milliseconds: 60),
              placeholder: (context, url) => const SizedBox.shrink(),
              errorWidget: (context, url, error) => const SizedBox.shrink(),
            ),
        ],
      );
    }

    return Text(
      widget.emoji,
      style: TextStyle(
        fontSize: widget.size * 0.88,
        height: 1.15,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _buildEmojiVisual(),
      ),
    );
  }
}

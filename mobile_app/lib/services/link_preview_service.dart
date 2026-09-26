import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/link_preview_data.dart';

/// WhatsApp-grade Client-Side OpenGraph & Rich Link Preview Scraper Engine (Phase 10)
/// Extracts real og:title, og:description, og:image, and domain with 0ms local caching.
class LinkPreviewService {
  static final LinkPreviewService _instance = LinkPreviewService._internal();
  factory LinkPreviewService() => _instance;
  LinkPreviewService._internal();

  static final Map<String, LinkPreviewData> _memoryCache = {};
  static final Map<String, Future<LinkPreviewData?>> _inFlight = {};

  static final RegExp _urlRegex = RegExp(
    r'(https?://[^\s]+)',
    caseSensitive: false,
  );

  /// Extracts the first valid HTTP/HTTPS URL from user input text
  String? extractFirstUrl(String text) {
    final match = _urlRegex.firstMatch(text);
    if (match != null) {
      String url = match.group(0)!;
      // Strip trailing punctuation like comma, dot, or parenthesis
      url = url.replaceAll(RegExp(r'[,\.\)\s]+$'), '');
      return url;
    }
    return null;
  }

  /// Fetches and scrapes OpenGraph metadata for the given URL
  Future<LinkPreviewData?> fetchPreview(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;

    // 1. Fast L1 Memory Cache
    if (_memoryCache.containsKey(cleanUrl)) {
      return _memoryCache[cleanUrl];
    }

    // 2. Coalesce in-flight scraping requests
    if (_inFlight.containsKey(cleanUrl)) {
      return await _inFlight[cleanUrl];
    }

    final future = _scrapeUrl(cleanUrl);
    _inFlight[cleanUrl] = future;
    return await future;
  }

  Future<LinkPreviewData?> _scrapeUrl(String cleanUrl) async {
    try {
      // 3. Fast L2 Disk / SharedPreferences Cache
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'lp_${cleanUrl.hashCode.abs()}';
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final cachedData = LinkPreviewData.fromJsonString(cachedJson);
        if (cachedData != null) {
          _memoryCache[cleanUrl] = cachedData;
          return cachedData;
        }
      }

      final uri = Uri.tryParse(cleanUrl);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return null;
      }

      final host = uri.host.replaceAll('www.', '');

      // Quick fallback for well-known media hosts before network request
      String? fallbackTitle;
      if (host.contains('youtube.com') || host.contains('youtu.be')) {
        fallbackTitle = 'YouTube Video';
      } else if (host.contains('github.com')) {
        fallbackTitle = 'GitHub Repository';
      } else if (host.contains('instagram.com')) {
        fallbackTitle = 'Instagram Post';
      }

      // 4. HTTP Fetch with streaming limit (first 64KB max) to save bandwidth
      final client = http.Client();
      try {
        final request = http.Request('GET', uri);
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 DOLSYXBot/1.0';
        request.headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';

        final streamedResponse = await client.send(request).timeout(const Duration(seconds: 4));
        if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
          // Read up to 64 KB of HTML
          final bytes = <int>[];
          await for (final chunk in streamedResponse.stream) {
            bytes.addAll(chunk);
            if (bytes.length > 65536) break;
          }

          final html = utf8.decode(bytes, allowMalformed: true);
          final parsed = _parseOpenGraphHtml(html, cleanUrl, host);

          if (parsed != null) {
            _memoryCache[cleanUrl] = parsed;
            await prefs.setString(cacheKey, parsed.toJsonString());
            return parsed;
          }
        }
      } finally {
        client.close();
      }

      // If scraping failed but URL is valid, create basic host card
      final fallbackData = LinkPreviewData(
        url: cleanUrl,
        title: fallbackTitle ?? host,
        domain: host,
      );
      _memoryCache[cleanUrl] = fallbackData;
      return fallbackData;
    } catch (e) {
      debugPrint('[LinkPreview] Scraper error for $cleanUrl: $e');
      final host = Uri.tryParse(cleanUrl)?.host.replaceAll('www.', '') ?? 'Link';
      return LinkPreviewData(url: cleanUrl, domain: host);
    } finally {
      _inFlight.remove(cleanUrl);
    }
  }

  /// Parses OpenGraph tags from HTML chunk using fast regular expressions
  LinkPreviewData? _parseOpenGraphHtml(String html, String url, String defaultHost) {
    try {
      // 1. Title: og:title -> twitter:title -> <title>
      String? title = _extractMeta(html, 'og:title') ??
          _extractMeta(html, 'twitter:title') ??
          _extractTagContent(html, 'title');

      // 2. Description: og:description -> twitter:description -> meta description
      String? description = _extractMeta(html, 'og:description') ??
          _extractMeta(html, 'twitter:description') ??
          _extractMeta(html, 'description');

      // 3. Image: og:image -> twitter:image
      String? imageUrl = _extractMeta(html, 'og:image') ?? _extractMeta(html, 'twitter:image');

      if (imageUrl != null && imageUrl.isNotEmpty) {
        // Resolve relative image URLs
        if (imageUrl.startsWith('//')) {
          imageUrl = 'https:$imageUrl';
        } else if (imageUrl.startsWith('/')) {
          final uri = Uri.parse(url);
          imageUrl = '${uri.scheme}://${uri.host}$imageUrl';
        }
      }

      // 4. Clean entities (e.g. &amp;, &quot;, &#39;)
      title = _cleanHtmlEntities(title);
      description = _cleanHtmlEntities(description);

      return LinkPreviewData(
        url: url,
        title: (title != null && title.isNotEmpty) ? title : defaultHost,
        description: description,
        imageUrl: imageUrl,
        domain: defaultHost,
      );
    } catch (e) {
      debugPrint('[LinkPreview] Parsing error: $e');
      return null;
    }
  }

  String? _extractMeta(String html, String propertyName) {
    final pattern1 = RegExp(
      '<meta\\s+[^>]*?(?:property|name)=["\']$propertyName["\'][^>]*?content=["\']([^"\']*)["\']',
      caseSensitive: false,
    );
    var match = pattern1.firstMatch(html);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }

    final pattern2 = RegExp(
      '<meta\\s+[^>]*?content=["\']([^"\']*)["\'][^>]*?(?:property|name)=["\']$propertyName["\']',
      caseSensitive: false,
    );
    match = pattern2.firstMatch(html);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }

    return null;
  }

  String? _extractTagContent(String html, String tagName) {
    final pattern = RegExp('<$tagName[^>]*>([^<]*)</$tagName>', caseSensitive: false);
    final match = pattern.firstMatch(html);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    return null;
  }

  String? _cleanHtmlEntities(String? text) {
    if (text == null) return null;
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}

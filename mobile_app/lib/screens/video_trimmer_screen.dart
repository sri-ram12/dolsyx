import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';
import '../theme/app_theme.dart';

class VideoTrimmerScreen extends StatefulWidget {
  final File file;

  const VideoTrimmerScreen({super.key, required this.file});

  @override
  State<VideoTrimmerScreen> createState() => _VideoTrimmerScreenState();
}

class _VideoTrimmerScreenState extends State<VideoTrimmerScreen> {
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _progressVisibility = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  void _loadVideo() async {
    await _trimmer.loadVideo(videoFile: widget.file);
    setState(() {});
  }

  Future<String?> _saveVideo() async {
    setState(() {
      _progressVisibility = true;
    });

    String? value;
    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      onSave: (outputPath) {
        setState(() {
          _progressVisibility = false;
        });
        value = outputPath;
      },
    );
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Trim Video', style: TextStyle(color: Colors.white)),
        backgroundColor: AppTheme.surfaceColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _progressVisibility
                ? null
                : () async {
                    String? outputPath = await _saveVideo();
                    if (outputPath != null && mounted) {
                      Navigator.of(context).pop(outputPath);
                    }
                  },
          )
        ],
      ),
      body: Builder(
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.only(bottom: 30.0),
            color: Colors.black,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                Visibility(
                  visible: _progressVisibility,
                  child: const LinearProgressIndicator(
                    backgroundColor: Colors.red,
                  ),
                ),
                Expanded(
                  child: VideoViewer(trimmer: _trimmer),
                ),
                Center(
                  child: TrimViewer(
                    trimmer: _trimmer,
                    viewerHeight: 50.0,
                    viewerWidth: MediaQuery.of(context).size.width,
                    maxVideoLength: const Duration(seconds: 90),
                    onChangeStart: (value) => _startValue = value,
                    onChangeEnd: (value) => _endValue = value,
                    onChangePlaybackState: (value) {
                      setState(() {
                        _isPlaying = value;
                      });
                    },
                  ),
                ),
                TextButton(
                  child: _isPlaying
                      ? const Icon(
                          Icons.pause,
                          size: 80.0,
                          color: Colors.white,
                        )
                      : const Icon(
                          Icons.play_arrow,
                          size: 80.0,
                          color: Colors.white,
                        ),
                  onPressed: () async {
                    bool playbackState = await _trimmer.videoPlaybackControl(
                      startValue: _startValue,
                      endValue: _endValue,
                    );
                    setState(() {
                      _isPlaying = playbackState;
                    });
                  },
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

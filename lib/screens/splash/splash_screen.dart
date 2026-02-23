import 'package:flutter/material.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:video_player/video_player.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static bool _hasPlayedOnce = false;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();

    if (_hasPlayedOnce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/app');
        }
      });
      return;
    }
    _hasPlayedOnce = true;
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset(
        'assets/splash/splash_video.mp4',
      );
      await _videoController!.initialize();

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });

        await _videoController!.play();

        bool hasNavigated = false;
        _videoController!.addListener(() {
          if (!hasNavigated &&
              _videoController!.value.position >=
                  _videoController!.value.duration) {
            hasNavigated = true;
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/app');
            }
          }
        });

        Future.delayed(const Duration(seconds: 4), () {
          if (!hasNavigated && mounted) {
            hasNavigated = true;
            Navigator.of(context).pushReplacementNamed('/app');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/app');
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor,

      body: Stack(
        children: [
          Positioned.fill(child: Container(color: AppTheme.primaryColor)),

          if (_isVideoInitialized && _videoController != null)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

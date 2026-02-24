import 'dart:io';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen> {
  String _getImagePath(String baseName) {
    if (Platform.isIOS) {
      return 'assets/${baseName}_ios.jpg';
    }
    return 'assets/$baseName.jpg';
  }

  late final List<Map<String, String>> onboardingData = [
    {
      'image': _getImagePath('onboarding_1'),
      'title': 'All Your Sales Data\nin One Place',
      'description':
          'View dashboard metrics, manage customers, create quotations, and track invoices seamlessly',
    },
    {
      'image': _getImagePath('onboarding_2'),
      'title': 'Connected to Odoo',
      'description':
          'Real-time sync with your Odoo system keeps all customer data, products, and sales records up-to-date',
    },
    {
      'image': _getImagePath('onboarding_3'),
      'title': 'Mobile Sales\nManagement',
      'description':
          'Create quotes, manage products, track deliveries, and handle invoices from anywhere',
    },
  ];

  int currentIndex = 0;

  Future<void> _markGetStartedSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenGetStarted', true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    final isSmallMobile = width < 400;
    final isTablet = width >= 600 && width < 1024;
    final isDesktop = width >= 1024;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (isDesktop) {
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _buildCarousel(
                    theme,
                    isDark,
                    constraints.maxHeight,
                    constraints.maxWidth * 0.55,
                    isDesktop: true,
                  ),
                ),

                Expanded(
                  flex: 4,
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth > 1400 ? 80 : 60,
                          vertical: 40,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: _buildContent(theme, isDark, isDesktop: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else if (isTablet) {
            return Column(
              children: [
                Expanded(
                  flex: 55,
                  child: _buildCarousel(
                    theme,
                    isDark,
                    constraints.maxHeight * 0.55,
                    constraints.maxWidth,
                    isDesktop: false,
                  ),
                ),

                Expanded(
                  flex: 45,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 32,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: _buildContent(theme, isDark, isDesktop: false),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Stack(
              children: [
                _buildCarousel(theme, isDark, height, width, isDesktop: false),

                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallMobile ? 24 : 40,
                      vertical: isSmallMobile ? 20 : 40,
                    ),
                    child: Column(
                      children: [
                        const Spacer(),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildContent(theme, isDark, isDesktop: false),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildCarousel(
    ThemeData theme,
    bool isDark,
    double height,
    double width, {
    required bool isDesktop,
  }) {
    return SizedBox(
      height: height,
      width: width,
      child: CarouselSlider(
        options: CarouselOptions(
          height: height,
          autoPlay: true,
          autoPlayInterval: const Duration(seconds: 4),
          enlargeCenterPage: false,
          viewportFraction: 1.0,
          onPageChanged: (index, reason) {
            setState(() {
              currentIndex = index;
            });
          },
        ),
        items: onboardingData.map((data) {
          return Container(
            width: width,
            height: height,
            color: theme.primaryColor,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Image.asset(
                    data['image']!,
                    width: width,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                  ),
                ),

                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    bool isDark, {
    required bool isDesktop,
  }) {
    final fontSize = isDesktop ? 24.0 : 28.0;
    final descSize = isDesktop ? 14.0 : 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          onboardingData[currentIndex]['title']!,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.3,
            letterSpacing: -0.5,
            shadows: const [
              Shadow(
                offset: Offset(0, 2),
                blurRadius: 4,
                color: Colors.black54,
              ),
            ],
          ),
        ),

        SizedBox(height: isDesktop ? 10 : 15),

        Text(
          onboardingData[currentIndex]['description']!,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: descSize,
            color: Colors.white.withOpacity(0.8),
            height: 1.6,
            letterSpacing: 0.1,
            shadows: const [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 2,
                color: Colors.black54,
              ),
            ],
          ),
        ),

        SizedBox(height: isDesktop ? 30 : 40),

        SizedBox(
          width: double.infinity,
          height: isDesktop ? 45 : 55,
          child: ElevatedButton(
            onPressed: () async {
              await _markGetStartedSeen();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              elevation: 0,
              shadowColor: AppTheme.primaryColor.withOpacity(0.3),
            ),
            child: Text(
              'Get Started',
              style: GoogleFonts.inter(
                fontSize: isDesktop ? 18 : 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),

        SizedBox(height: isDesktop ? 15 : 20),

        DotsIndicator(
          dotsCount: onboardingData.length,
          position: currentIndex,
          decorator: DotsDecorator(
            activeColor: Colors.white,
            color: Colors.white.withOpacity(0.4),
            size: Size.square(isDesktop ? 6.0 : 8.0),
            activeSize: Size(isDesktop ? 12.0 : 16.0, isDesktop ? 6.0 : 8.0),
            activeShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5.0),
            ),
          ),
        ),

        SizedBox(height: isDesktop ? 10 : 20),
      ],
    );
  }
}

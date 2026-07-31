import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // اگر نصب نکردی هنوز، خط پایین رو بخون

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // FlutterNativeSplash.remove();
  // تنظیم رنگ استاتوس بار و جهت صفحه
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp( MaterialApp(
    theme: ThemeData(
      fontFamily: 'Vazir',
    ),
    home: RozhbinApp(), // مستقیم می‌رویم سراغ صفحه اصلی که شامل همه چیز است
    debugShowCheckedModeBanner: false,
  ));
}

class RozhbinApp extends StatefulWidget {
  const RozhbinApp({super.key});

  @override
  State<RozhbinApp> createState() => _RozhbinAppState();
}

class _RozhbinAppState extends State<RozhbinApp> with TickerProviderStateMixin {
  // کنترلرهای وب‌ویو
  InAppWebViewController? _webViewController;
  late PullToRefreshController _pullToRefreshController;

  // وضعیت‌ها
  bool _isLoading = true;
  bool _isError = false;
  int _loadingProgress = 0;
  bool _splashAnimDone = false;
  bool _isRedirecting = false;

  // وضعیت اسپلش اسکرین
  bool _showSplash = true;
  late AnimationController _splashAnimController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // تنظیمات رنگ و لینک
  final Color orangeColor = const Color(0xFFF39534);
  final String allowedDomain = "rozhbin.ir";
  final String initialUrl = "https://rozhbin.ir";

  @override
  void initState() {
    super.initState();
    _setupPullToRefresh();
    _setupSplashAnimation();
  }

  // ۱. تنظیمات انیمیشن اسپلش (دقیقاً مثل کد قبلی خودت)
  void _setupSplashAnimation() {
    _splashAnimController = AnimationController(
      duration: const Duration(seconds: 3), // مدت زمان نمایش اسپلش
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _splashAnimController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _splashAnimController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _splashAnimController.forward();

    // وقتی انیمیشن تمام شد، اسپلش را حذف کن
    _splashAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _splashAnimDone = true;
        _tryHideSplash();
      }
    });
  }

  void _tryHideSplash() {
    if (_splashAnimDone && !_isLoading && mounted) {
      setState(() {
        _showSplash = false;
      });
    }
  }


  void _setupPullToRefresh() {
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: orangeColor),
      onRefresh: () async {
        if (await _checkInternet()) {
          _webViewController?.reload();
        } else {
          _pullToRefreshController.endRefreshing();
          setState(() => _isError = true);
        }
      },
    );
  }

  Future<bool> _checkInternet() async {
    // اگر پکیج connectivity_plus نصب نیست، موقتا return true کن
    // ولی برای عملکرد درست باید نصب باشه: flutter pub add connectivity_plus
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false;
      }
    } catch (e) {
      // اگر ارور داد یعنی پکیج نصب نیست یا دسترسی نداره
      return true;
    }
    return true;
  }

  @override
  void dispose() {
    _splashAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_webViewController != null && await _webViewController!.canGoBack()) {
          _webViewController!.goBack();
        } else {
          // خروج از برنامه اگر بک نداشت
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Color(0xFF1500FF),
        body: Stack(
          children: [
            // لایه ۱ (زیرین): وب‌ویو - همزمان با اسپلش لود می‌شود
            _buildWebView(),

            // لایه ۲: نوار لودینگ بالای صفحه (فقط وقتی اسپلش رفت نشان بده)
            if (!_showSplash && _isLoading && !_isError && !_isRedirecting)
              Positioned(
                top: 0, left: 0, right: 0,
                child: SafeArea(
                  child: LinearProgressIndicator(
                    value: _loadingProgress / 100,
                    color: orangeColor,
                    backgroundColor: Colors.transparent,
                    minHeight: 3,
                  ),
                ),
              ),

            // لایه ۳: اسپلش اسکرین کاستوم (روی همه چیز)
            // از AnimatedOpacity استفاده می‌کنیم تا موقع حذف شدن فید بشه
            IgnorePointer(
              ignoring: !_showSplash, // وقتی محو شد، تاچ رو نگیره
              child: AnimatedOpacity(
                opacity: _showSplash ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: _buildCustomSplashScreen(),
              ),
            ),

            // لایه ۴: صفحه انتقال (ریدایرکت)
            if (_isRedirecting) _buildRedirectPage(),
          ],
        ),
      ),
    );
  }

  // --- ویجت وب‌ویو ---
  Widget _buildWebView() {
    return SafeArea(
      child: Stack(
        children: [
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useHybridComposition: true,
              allowsInlineMediaPlayback: true,
              cacheEnabled: true,
              domStorageEnabled: true,
              supportZoom: false,
              transparentBackground: true, // مهم: برای اینکه لحظه اول سفید نباشه
            ),
            pullToRefreshController: _pullToRefreshController,
            onWebViewCreated: (controller) {
              _webViewController = controller;
              // بلافاصله شروع به لود کن (زیر اسپلش)
              _startLoading();
            },
            onLoadStart: (controller, url) {
              setState(() { _isLoading = true; _isError = false; });
            },
            onLoadStop: (controller, url) {
              _pullToRefreshController.endRefreshing();
              setState(() { _isLoading = false; });
              _tryHideSplash();
            },
            onReceivedError: (controller, request, error) {
              // جلوگیری از خطای SSL یا قطع شدن
              // فقط اگر خطای اصلی باشه
              if (request.isForMainFrame ?? true) {
                _pullToRefreshController.endRefreshing();
                controller.stopLoading();
                setState(() { _isError = true; _isLoading = false; });
              }
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              var uri = navigationAction.request.url!;
              if (uri.host.contains("rozhbin.ir")) {
                return NavigationActionPolicy.ALLOW;
              }
              _handleExternalLink(uri.toString());
              return NavigationActionPolicy.CANCEL;
            },
            onProgressChanged: (controller, progress) {
              setState(() => _loadingProgress = progress);
              if (progress == 100) _pullToRefreshController.endRefreshing();
            },
          ),

          // صفحه ارور (اگر نت نبود)
          if (_isError)
            Container(
              color: Colors.white,
              child: _buildErrorPage(),
            ),
        ],
      ),
    );
  }

  // --- ویجت اسپلش اسکرین (همان دیزاین خودت) ---
  Widget _buildCustomSplashScreen() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF786DFB), // آبی تیره
            Color(0xFF1500FF), // مشکی
          ],
        ),
      ),
      child: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // لوگو
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.9),
                    border: Border.all(
                      color: orangeColor.withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: orangeColor.withOpacity(0.1),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    "assets/icon.png", // آیکون موقت، عکس خودت رو بذار
                    width: 200,
                    height: 200,
                  ),
                ),
                const SizedBox(height: 50),
                // متن
                const Text(
                  "آکادمی روژبین",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Vazir',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "... در حال بار گذاری",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    fontFamily: 'Vazir',
                  ),
                ),
                const SizedBox(height: 40),
                // لودینگ پایین اسپلش
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    color: orangeColor,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- متدهای کمکی (لودینگ، ارور و ...) ---

  Future<void> _startLoading() async {
    if (await _checkInternet()) {
      setState(() => _isError = false);
      _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(initialUrl)));
    } else {
      setState(() { _isError = true; _isLoading = false; });
    }
  }

  Future<void> _handleExternalLink(String url) async {
    setState(() => _isRedirecting = true);
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } finally {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _isRedirecting = false);
    }
  }

  Widget _buildErrorPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text("اتصال اینترنت برقرار نیست", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              setState(() => _isLoading = true);
              _startLoading();
            },
            style: ElevatedButton.styleFrom(backgroundColor: orangeColor),
            child: const Text("تلاش مجدد", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildRedirectPage() {
    return Container(
      color: Colors.white.withOpacity(0.95),
      child: Center(
        child: CircularProgressIndicator(color: orangeColor),
      ),
    );
  }
}
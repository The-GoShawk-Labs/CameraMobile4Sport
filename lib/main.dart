import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/court_statistician_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VolleyLiveApp());
}

class VolleyLiveApp extends StatelessWidget {
  const VolleyLiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => P2PConnectionProvider()),
        ChangeNotifierProvider(create: (_) => MatchProvider()),
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        ChangeNotifierProvider(create: (_) => StreamerProvider()),
        ChangeNotifierProvider(create: (_) => CourtStatisticianProvider()),
      ],
      child: MaterialApp.router(
        title: 'VolleyLive Analytics',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        routerConfig: AppRouter.router,
      ),
    );
  }
}

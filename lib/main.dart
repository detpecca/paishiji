import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/core/router.dart';
import 'package:paishiji/core/theme.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/connection_tester.dart';
import 'package:paishiji/data/providers/key_vault.dart';
import 'package:paishiji/features/home/home_page.dart';

void main() {
  runApp(const ProviderScope(child: PaishijiApp()));
}

/// 顶层 Provider：AppServices。生产用 SecureStorageKeyVault + HttpConnectionTester。
/// 测试可 override 此 provider 注入内存实现（红线#2：测试零真实 API/secure 插件）。
final appServicesProvider = FutureProvider<AppServices>((ref) async {
  final scope = DataScope(AppDatabase());
  final services = AppServices(
    scope,
    SecureStorageKeyVault(),
    HttpConnectionTester(),
  );
  await services.bootstrap();
  ref.onDispose(services.dispose);
  return services;
});

class PaishijiApp extends ConsumerWidget {
  const PaishijiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(appServicesProvider);
    return servicesAsync.when(
      loading: () => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _Splash(),
      ),
      error: (e, st) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: _BootError(error: '$e'),
      ),
      data: (services) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: '拍食记',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: AppRouter(services).config,
        builder: (context, child) => AppServicesScope(
          services: services,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('启动失败'),
              const SizedBox(height: 8),
              Text(error, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
